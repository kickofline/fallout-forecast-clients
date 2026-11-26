extends Node
## Fallout Forecast Open Protocol Thin v1 (docs/open-protocol.md).
## One WebSocket, JSON text frames. TLS certificates are verified.
##
## The socket is polled from a helper thread (every ~10 ms) as well as from
## the main loop, both under one mutex. Socket callbacks only queue raw
## events; the main thread parses and dispatches them. That keeps the
## WebSocket answering the server's heartbeat pings while the main thread is
## blocked (map load, first-draw shader compiles), which otherwise made the
## server drop the car a few seconds into every run.

signal phase_changed(phase)          # "offline" | "connecting" | "online" | "retuning"
signal welcomed(data)
signal status_changed(state, msg)
signal lobby_updated(data)
signal load_requested(map_id)
signal snapshot(data)
signal events(list)
signal draft(data)
signal draft_done
signal tape(data)
signal results(data)
signal failed(msg)

const PROTOCOL = 1
const CLIENT = "car/0.1"
const CONNECT_TIMEOUT = 10.0
const RETRIES = 6
const SNAP_RATE = 15

var phase = "offline"
var state = "disconnected"          # last bridge status state
var status_msg = ""
var you = 0
var maps = []                        # [{id,name}]
var lobby = {}
var last_error = ""
var rtt_ms = -1.0
var bridge_offset_ms = 0.0          # bridge t_ms - local ms (smoothed)
var snaps_received = 0
var bytes_in = 0
var current_map = ""

var _ws: WebSocketClient
var _url = ""
var _name = ""
var _connect_left = 0.0
var _ping_left = 0.0
var _retry = 0
var _retry_left = -1.0
var _want_online = false
var _offset_init = false
var _welcomed = false

# Threaded polling.
var _mutex = Mutex.new()
var _thread: Thread
var _thread_run = false
var _inbox = []                     # [gen, kind, payload...] queued by socket callbacks
var _gen = 0                        # socket generation (drops events from old sockets)
var _main_tick_ms = 0               # last main-loop poll (int: written by main, read by thread)
var _keepalive_ms = 0               # last thread-side keepalive ping
var _online_flag = 0                # 1 while welcomed (int for the thread)
var close_code = -1                 # last close code from the server (-1: none / unclean)
var close_reason = ""
var no_thread = false               # test switch: --net-no-thread


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	no_thread = "--net-no-thread" in Settings.args()
	_main_tick_ms = OS.get_ticks_msec()
	if not no_thread:
		_thread_run = true
		_thread = Thread.new()
		_thread.start(self, "_net_loop")


func _exit_tree() -> void:
	_thread_run = false
	if _thread and _thread.is_active():
		_thread.wait_to_finish()


## Helper thread: keep the socket serviced (heartbeat pongs, TLS, reads) even
## when the main loop is stuck for seconds. Sends a keepalive app ping if the
## main loop has not run for over a second.
func _net_loop(_unused) -> void:
	while _thread_run:
		_mutex.lock()
		if _ws:
			_ws.poll()
			var now = OS.get_ticks_msec()
			if _online_flag == 1 and now - _main_tick_ms > 1000 and now - _keepalive_ms > 1000:
				_keepalive_ms = now
				_put({"t": "ping", "ms": now})
		_mutex.unlock()
		OS.delay_msec(10)


func connect_to(url: String, player_name: String) -> void:
	_url = url.strip_edges()
	_name = player_name.strip_edges()
	if _name.empty():
		_name = "Honda"
	_want_online = true
	_retry = 0
	last_error = ""
	_open()


func leave() -> void:
	_want_online = false
	_retry_left = -1.0
	_mutex.lock()
	if _ws and _ws.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_put({"t": "leave"})
		_ws.get_peer(1).close(1000, "leave")
	_mutex.unlock()
	_online_flag = 0
	_set_phase("offline")
	state = "disconnected"


func is_online() -> bool:
	return phase == "online"


func send(msg: Dictionary) -> void:
	_mutex.lock()
	_put(msg)
	_mutex.unlock()


## Caller holds _mutex.
func _put(msg: Dictionary) -> void:
	if _ws == null or _ws.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		return
	var peer = _ws.get_peer(1)
	if not peer.is_connected_to_host():
		return
	peer.put_packet(to_json(msg).to_utf8())


func lobby_action(action: String, extra := {}) -> void:
	var msg = {"t": "lobby", "a": action}
	for k in extra:
		msg[k] = extra[k]
	send(msg)


func choose(kind: String, index: int) -> void:
	send({"t": "choice", "kind": kind, "i": index})


## Bridge clock estimate in local ms.
func bridge_now_ms() -> float:
	return OS.get_ticks_msec() + bridge_offset_ms


func _open() -> void:
	_close_socket()
	_gen += 1
	close_code = -1
	close_reason = ""
	var ws = WebSocketClient.new()
	ws.verify_ssl = true
	ws.connect("connection_established", self, "_on_open", [_gen])
	ws.connect("connection_error", self, "_on_error", [_gen])
	ws.connect("connection_closed", self, "_on_closed", [_gen])
	ws.connect("server_close_request", self, "_on_close_request", [_gen])
	ws.connect("data_received", self, "_on_data", [_gen])
	_welcomed = false
	_offset_init = false
	_mutex.lock()
	_ws = ws
	var err = _ws.connect_to_url(_url, PoolStringArray(), false)
	_mutex.unlock()
	if err != OK:
		_fail("BAD SERVER URL (%d)" % err)
		return
	_connect_left = CONNECT_TIMEOUT
	_set_phase("connecting" if _retry == 0 else "retuning")


## Main thread only, never from inside a socket callback (the old code freed
## the WebSocketClient while it was emitting connection_closed).
func _close_socket() -> void:
	_online_flag = 0
	_mutex.lock()
	var ws = _ws
	_ws = null
	if ws:
		for sig in ["connection_established", "connection_error", "connection_closed", "server_close_request", "data_received"]:
			for c in ws.get_signal_connection_list(sig):
				ws.disconnect(sig, c.target, c.method)
		ws.disconnect_from_host(1000, "")
	_inbox.clear()
	_mutex.unlock()


func _process(delta: float) -> void:
	var _pt = OS.get_ticks_usec()
	_process_body(delta)
	Settings.prof_add("net", OS.get_ticks_usec() - _pt)


func _process_body(delta: float) -> void:
	var now = OS.get_ticks_msec()
	var gap = now - _main_tick_ms
	_main_tick_ms = now
	if gap > 750 and phase != "offline":
		print("NET main loop stalled %d ms (socket kept alive by %s)" % [gap, "nothing" if no_thread else "net thread"])
	_mutex.lock()
	if _ws:
		_ws.poll()
	var batch = _inbox
	_inbox = []
	_mutex.unlock()
	_dispatch(batch)
	if phase == "connecting" or phase == "retuning":
		if _ws and _ws.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_CONNECTING:
			_connect_left -= delta
			if _connect_left <= 0.0:
				_lost("NO ANSWER")
	if _retry_left >= 0.0:
		_retry_left -= delta
		if _retry_left < 0.0 and _want_online:
			_open()
	if phase == "online":
		_ping_left -= delta
		if _ping_left <= 0.0:
			_ping_left = 1.0
			send({"t": "ping", "ms": OS.get_ticks_msec()})


# ---- socket callbacks: run inside _ws.poll() on either thread, mutex held.
# They only queue; _dispatch() handles everything on the main thread.
func _on_open(_protocol, gen: int) -> void:
	if gen != _gen or _ws == null:
		return
	_ws.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	# 15 Hz snapshots: JSON parsing is a real cost on the head unit, and the
	# 100 ms interpolation delay still brackets two snapshots.
	_put({"t": "hello", "v": PROTOCOL, "tier": "thin", "name": _name, "client": CLIENT, "rate": SNAP_RATE})
	_inbox.append([gen, "open"])


func _on_error(gen: int) -> void:
	_inbox.append([gen, "error"])


func _on_close_request(code: int, reason: String, gen: int) -> void:
	_inbox.append([gen, "close_req", code, reason])


func _on_closed(clean, gen: int) -> void:
	_inbox.append([gen, "closed", bool(clean)])


func _on_data(gen: int) -> void:
	if gen != _gen or _ws == null:
		return
	var peer = _ws.get_peer(1)
	while peer.get_available_packet_count() > 0:
		_inbox.append([gen, "data", peer.get_packet()])


func _dispatch(batch: Array) -> void:
	if batch.empty():
		return
	# After a long stall only the newest snapshots matter (the world keeps 40).
	var data_count = 0
	for ev in batch:
		if ev[1] == "data":
			data_count += 1
	var skip_snaps = max(0, data_count - 60)
	for ev in batch:
		if ev[0] != _gen:
			continue
		match ev[1]:
			"open":
				print("NET open %s" % _url)
			"error":
				print("NET connection error (%s)" % _url)
				_lost("CONNECTION FAILED")
			"close_req":
				close_code = int(ev[2])
				close_reason = str(ev[3])
				print("NET server close request code=%d reason='%s'" % [close_code, close_reason])
			"closed":
				var why = _close_text(bool(ev[2])) if _want_online else "LEFT"
				print("NET closed clean=%s code=%d reason='%s' -> %s" % [str(ev[2]), close_code, close_reason, why])
				_lost(why)
			"data":
				var raw: PoolByteArray = ev[2]
				bytes_in += raw.size()
				var parsed = JSON.parse(raw.get_string_from_utf8())
				if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
					continue
				if skip_snaps > 0 and str(parsed.result.get("t", "")) == "snap":
					skip_snaps -= 1
					continue
				var _t = OS.get_ticks_usec()
				_handle(parsed.result)
				Settings.prof_add("n_" + str(parsed.result.get("t", "")), OS.get_ticks_usec() - _t)
		if ev[0] != _gen or _ws == null:
			return


func _close_text(clean: bool) -> String:
	if close_code >= 0:
		var r = close_reason.strip_edges().to_upper()
		return "CLOSED %d%s" % [close_code, (" - " + r) if not r.empty() else ""]
	return "SIGNAL LOST - NO CLOSE FRAME" if not clean else "SIGNAL LOST"


func _lost(why: String) -> void:
	_close_socket()
	if not _want_online:
		# We left on purpose; the socket closing is expected, not an error.
		_set_phase("offline")
		return
	last_error = why
	print("NET lost: %s (phase=%s state=%s)" % [why, phase, state])
	# Retry only once we had a session (welcomed) or while still retrying one.
	if (_welcomed or phase == "retuning") and _retry < RETRIES:
		_retry += 1
		_retry_left = min(8.0, pow(2.0, _retry - 1))
		_set_phase("retuning")
	else:
		_fail(why)


func _fail(why: String) -> void:
	last_error = why
	_want_online = false
	_retry_left = -1.0
	_close_socket()
	state = "disconnected"
	_set_phase("offline")
	emit_signal("failed", why)


func _set_phase(p: String) -> void:
	if p != phase:
		phase = p
		emit_signal("phase_changed", p)


func _handle(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"welcome":
			_welcomed = true
			_online_flag = 1
			_retry = 0
			you = int(msg.get("you", 0))
			maps = msg.get("maps", []) if msg.get("maps") is Array else []
			_set_phase("online")
			emit_signal("welcomed", msg)
		"error":
			last_error = str(msg.get("msg", "ERROR")).to_upper()
			print("NET server error: %s" % last_error)
			_fail(last_error)
		"status":
			state = str(msg.get("state", state))
			status_msg = str(msg.get("msg", "")) if msg.get("msg") != null else ""
			emit_signal("status_changed", state, status_msg)
		"lobby":
			lobby = msg
			if msg.get("maps") is Array and not msg.maps.empty():
				maps = msg.maps
			emit_signal("lobby_updated", msg)
		"load":
			current_map = str(msg.get("map", ""))
			emit_signal("load_requested", current_map)
		"snap":
			snaps_received += 1
			_track_clock(float(msg.get("t_ms", 0.0)))
			emit_signal("snapshot", msg)
		"ev":
			if msg.get("list") is Array:
				emit_signal("events", msg.list)
		"draft":
			emit_signal("draft", msg)
		"draft_done":
			emit_signal("draft_done")
		"tape":
			emit_signal("tape", msg)
		"results":
			emit_signal("results", msg)
		"ping":
			send({"t": "pong", "ms": msg.get("ms", 0)})
		"pong":
			var sample = OS.get_ticks_msec() - float(msg.get("ms", 0))
			rtt_ms = sample if rtt_ms < 0.0 else lerp(rtt_ms, sample, 0.25)


func _track_clock(t_ms: float) -> void:
	if t_ms <= 0.0:
		return
	var sample = t_ms - OS.get_ticks_msec()
	if not _offset_init:
		bridge_offset_ms = sample
		_offset_init = true
	elif sample > bridge_offset_ms:
		# Packet arrived "early" relative to estimate: snap toward it fast.
		bridge_offset_ms = lerp(bridge_offset_ms, sample, 0.5)
	else:
		# Late packets (jitter) pull the estimate down slowly.
		bridge_offset_ms = lerp(bridge_offset_ms, sample, 0.02)
