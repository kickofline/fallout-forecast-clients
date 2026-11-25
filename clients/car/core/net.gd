extends Node
## Fallout Forecast Open Protocol Thin v1 (docs/open-protocol.md).
## One WebSocket, JSON text frames. TLS certificates are verified.

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


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS


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
	if _ws and _ws.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		send({"t": "leave"})
		_ws.get_peer(1).close(1000, "leave")
	_set_phase("offline")
	state = "disconnected"


func is_online() -> bool:
	return phase == "online"


func send(msg: Dictionary) -> void:
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
	_ws = WebSocketClient.new()
	_ws.verify_ssl = true
	_ws.connect("connection_established", self, "_on_open")
	_ws.connect("connection_error", self, "_on_error")
	_ws.connect("connection_closed", self, "_on_closed")
	_ws.connect("server_close_request", self, "_on_close_request")
	_ws.connect("data_received", self, "_on_data")
	_welcomed = false
	_offset_init = false
	var err = _ws.connect_to_url(_url, PoolStringArray(), false)
	if err != OK:
		_fail("BAD SERVER URL (%d)" % err)
		return
	_connect_left = CONNECT_TIMEOUT
	_set_phase("connecting" if _retry == 0 else "retuning")


func _close_socket() -> void:
	if _ws:
		for sig in ["connection_established", "connection_error", "connection_closed", "server_close_request", "data_received"]:
			for c in _ws.get_signal_connection_list(sig):
				_ws.disconnect(sig, c.target, c.method)
		_ws.disconnect_from_host(1000, "")
		_ws = null


func _process(delta: float) -> void:
	if _ws:
		_ws.poll()
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


func _on_open(_protocol := "") -> void:
	_ws.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	send({"t": "hello", "v": PROTOCOL, "tier": "thin", "name": _name, "client": CLIENT})


func _on_error() -> void:
	_lost("CONNECTION FAILED")


func _on_close_request(code: int, reason: String) -> void:
	if not reason.empty():
		last_error = reason.to_upper()


func _on_closed(_clean := false) -> void:
	_lost(last_error if not last_error.empty() else "SIGNAL LOST")


func _lost(why: String) -> void:
	last_error = why
	_close_socket()
	if not _want_online:
		_set_phase("offline")
		return
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


func _on_data() -> void:
	var peer = _ws.get_peer(1)
	while peer.get_available_packet_count() > 0:
		var raw = peer.get_packet()
		bytes_in += raw.size()
		var parsed = JSON.parse(raw.get_string_from_utf8())
		if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
			continue
		_handle(parsed.result)
		if _ws == null:
			return


func _handle(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"welcome":
			_welcomed = true
			_retry = 0
			you = int(msg.get("you", 0))
			maps = msg.get("maps", []) if msg.get("maps") is Array else []
			_set_phase("online")
			emit_signal("welcomed", msg)
		"error":
			last_error = str(msg.get("msg", "ERROR")).to_upper()
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
