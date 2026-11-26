extends "res://core/full_link.gd"
## Full-tier transport over WebSocket with JSON frames (spec-common §3.1,
## spec-full §6–7). Same threading model as the Thin core/net.gd: the socket
## is polled from a helper thread (every ~10 ms) and from poll(), both under
## one mutex; socket callbacks only queue raw packets, and poll() parses and
## emits on the main thread. That keeps WebSocket heartbeat pongs flowing
## while the main thread is blocked by a map load or a shader compile.
##
## While the main loop is stalled (> 400 ms) the helper thread also answers
## Net._rtt_ping itself so the host's RTT estimate (used for lag
## compensation) does not jump.

const Codec = preload("res://core/variant_codec.gd")
const CONNECT_TIMEOUT = 10.0

var url = ""
var close_code = -1
var close_reason = ""
var bytes_in = 0
var msgs_in = 0
var no_thread = false

var _ws: WebSocketClient
var _mutex = Mutex.new()
var _thread: Thread
var _thread_run = false
var _inbox = []
var _hello = {}
var _connect_left = 0.0
var _connected = false
var _closed_emitted = false
var _main_tick_ms = 0
var _stall_pongs = 0


func _init(server_url: String) -> void:
	url = server_url


func open(hello: Dictionary) -> void:
	_hello = hello.duplicate()
	_hello["t"] = "hello"
	close_code = -1
	close_reason = ""
	_closed_emitted = false
	_connected = false
	_main_tick_ms = OS.get_ticks_msec()
	var ws = WebSocketClient.new()
	ws.verify_ssl = true
	ws.connect("connection_established", self, "_on_open")
	ws.connect("connection_error", self, "_on_error")
	ws.connect("connection_closed", self, "_on_closed")
	ws.connect("server_close_request", self, "_on_close_request")
	ws.connect("data_received", self, "_on_data")
	_mutex.lock()
	_ws = ws
	var err = _ws.connect_to_url(url, PoolStringArray(), false)
	_mutex.unlock()
	if err != OK:
		_inbox.append(["error", "BAD SERVER URL (%d)" % err])
		return
	_connect_left = CONNECT_TIMEOUT
	print("NET full connect %s" % url)
	if not no_thread:
		_thread_run = true
		_thread = Thread.new()
		_thread.start(self, "_net_loop")


func _net_loop(_unused) -> void:
	while _thread_run:
		_mutex.lock()
		if _ws:
			_ws.poll()
		_mutex.unlock()
		OS.delay_msec(10)


func send(msg: Dictionary) -> void:
	var wire = msg
	if str(msg.get("t", "")) == "rpc":
		wire = {"t": "rpc", "node": msg.get("node", ""), "method": msg.get("method", ""),
			"args": Codec.encode_args(msg.get("args", []))}
		if msg.has("rel"):
			wire["rel"] = bool(msg.rel)
	var text = to_json(wire)
	_mutex.lock()
	_put_text(text)
	_mutex.unlock()


## Caller holds _mutex.
func _put_text(text: String) -> void:
	if _ws == null or _ws.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		return
	var peer = _ws.get_peer(1)
	if peer.is_connected_to_host():
		peer.put_packet(text.to_utf8())


func poll(delta: float) -> void:
	_main_tick_ms = OS.get_ticks_msec()
	_mutex.lock()
	if _ws:
		_ws.poll()
	var batch = _inbox
	_inbox = []
	_mutex.unlock()
	if not _connected and _ws and not _closed_emitted:
		_connect_left -= delta
		if _connect_left <= 0.0:
			_emit_closed(-1, "NO ANSWER")
			return
	for ev in batch:
		match ev[0]:
			"open":
				_connected = true
				print("NET full open %s" % url)
			"error":
				_emit_closed(-1, str(ev[1]) if ev.size() > 1 else "CONNECTION FAILED")
				return
			"close_req":
				close_code = int(ev[1])
				close_reason = str(ev[2])
				print("NET full close request code=%d reason='%s'" % [close_code, close_reason])
			"closed":
				_emit_closed(close_code, close_reason if not close_reason.empty() else ("SIGNAL LOST" if bool(ev[1]) else "SIGNAL LOST - NO CLOSE FRAME"))
				return
			"data":
				var raw: PoolByteArray = ev[1]
				bytes_in += raw.size()
				var parsed = JSON.parse(raw.get_string_from_utf8())
				if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
					continue
				var msg: Dictionary = parsed.result
				msgs_in += 1
				var t = str(msg.get("t", ""))
				if t == "rpc":
					msg["args"] = Codec.decode_args(msg.get("args", []))
					msg["node"] = str(msg.get("node", ""))
					msg["method"] = str(msg.get("method", ""))
				elif t == "welcome":
					you = int(msg.get("you", 0))
				emit_signal("message", msg)
		if _ws == null:
			return


func _emit_closed(code: int, reason: String) -> void:
	if _closed_emitted:
		return
	_closed_emitted = true
	print("NET full closed code=%d reason='%s'" % [code, reason])
	_shutdown(false)
	emit_signal("closed", code, reason)


func close() -> void:
	_closed_emitted = true
	_mutex.lock()
	_put_text(to_json({"t": "leave"}))
	_mutex.unlock()
	_shutdown(true)


func _shutdown(graceful: bool) -> void:
	_thread_run = false
	if _thread and _thread.is_active():
		_thread.wait_to_finish()
	_thread = null
	_mutex.lock()
	var ws = _ws
	_ws = null
	if ws:
		for sig in ["connection_established", "connection_error", "connection_closed", "server_close_request", "data_received"]:
			for c in ws.get_signal_connection_list(sig):
				ws.disconnect(sig, c.target, c.method)
		if graceful:
			ws.poll()
		ws.disconnect_from_host(1000, "leave" if graceful else "")
	_inbox.clear()
	_mutex.unlock()


# ---- socket callbacks: inside _ws.poll() on either thread, mutex held.
func _on_open(_protocol) -> void:
	if _ws == null:
		return
	_ws.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	_put_text(to_json(_hello))
	_inbox.append(["open"])


func _on_error() -> void:
	_inbox.append(["error", "CONNECTION FAILED"])


func _on_close_request(code: int, reason: String) -> void:
	_inbox.append(["close_req", code, reason])


func _on_closed(clean) -> void:
	_inbox.append(["closed", bool(clean)])


func _on_data() -> void:
	if _ws == null:
		return
	var peer = _ws.get_peer(1)
	var stalled = OS.get_ticks_msec() - _main_tick_ms > 400
	while peer.get_available_packet_count() > 0:
		var pkt = peer.get_packet()
		if stalled:
			_stall_pong(pkt)
		_inbox.append(["data", pkt])


## Helper-thread RTT answer while the main loop is blocked.
func _stall_pong(pkt: PoolByteArray) -> void:
	if pkt.size() > 200:
		return
	var s = pkt.get_string_from_utf8()
	if s.find("\"_rtt_ping\"") < 0:
		return
	var p = JSON.parse(s)
	if p.error == OK and p.result is Dictionary and p.result.get("args") is Array and not p.result.args.empty():
		_stall_pongs += 1
		_put_text(to_json({"t": "rpc", "node": "Net", "method": "_rtt_pong", "args": [int(p.result.args[0])], "rel": false}))
