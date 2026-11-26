extends "res://core/full_link.gd"
## Shared polling and Open Protocol message handling for WebSocket and TCP.
## Socket operations run under one mutex. Only poll() emits FullLink signals.

const JsonCodec = preload("res://core/variant_codec.gd")
const BinaryCodec = preload("res://core/variant_bin.gd")
const MAX_SEND = 65536
const MAX_RECEIVE = 524284
const CONNECT_TIMEOUT_MS = 10000
const SERVER_CLOSE_FLUSH_MS = 1500

var endpoint = ""
var close_code = -1
var close_reason = ""
var bytes_in = 0
var msgs_in = 0
var no_thread = false

var _mutex = Mutex.new()
var _thread: Thread
var _running = false
var _active = false
var _terminal = false
var _inbox = []
var _hello = {}
var _binary = false
var _deadline = 0
var _main_tick_ms = 0
var _last_error = ""
var _last_error_ms = 0


func open(hello: Dictionary) -> void:
	_shutdown(false)
	you = 0
	close_code = -1
	close_reason = ""
	_terminal = false
	_last_error = ""
	_hello = hello.duplicate()
	_hello["t"] = "hello"
	_binary = _hello.get("enc") == "bin"
	_main_tick_ms = OS.get_ticks_msec()
	_deadline = _main_tick_ms + CONNECT_TIMEOUT_MS
	_active = true
	print("NET full connect %s (%s)" % [endpoint, _hello.get("enc", "json")])
	_open_socket()
	if not no_thread and not _terminal:
		_running = true
		_thread = Thread.new()
		if _thread.start(self, "_net_loop") != OK:
			_thread = null
			_running = false


func _net_loop(_unused) -> void:
	while true:
		_mutex.lock()
		var running = _running
		if running and not _terminal:
			_poll_socket()
		_mutex.unlock()
		if not running:
			return
		OS.delay_msec(10)


func send(msg: Dictionary) -> void:
	var binary = _binary and msg.get("t") in ["rpc", "raw"]
	var payload = BinaryCodec.encode_frame(msg) if binary else _encode_json(msg)
	if payload.empty() or payload.size() > MAX_SEND:
		push_error("NET full refused invalid or oversized outbound frame")
		return
	_mutex.lock()
	if _active and not _terminal:
		_put_packet(payload, not binary)
	_mutex.unlock()


func poll(_delta: float) -> void:
	_mutex.lock()
	if _active and not _terminal:
		_main_tick_ms = OS.get_ticks_msec()
		_poll_socket()
	var batch = _inbox
	_inbox = []
	_mutex.unlock()
	for event in batch:
		match event[0]:
			"closed":
				_finish_close(event[1], event[2])
				return
			"data":
				var raw: PoolByteArray = event[1]
				bytes_in += raw.size()
				var msg = _decode(raw, event[2])
				if msg.empty():
					continue
				msgs_in += 1
				if event[3]:
					msg["rtt_answered"] = true
				if msg.get("t") == "error":
					_last_error = str(msg.get("msg", ""))
					_last_error_ms = OS.get_ticks_msec()
				if msg.get("t") == "welcome":
					if msg.get("enc", "json") != _hello.get("enc", "json"):
						_finish_close(-1, "SERVER DID NOT ACCEPT ENCODING")
						return
					you = int(msg.get("you", 0))
					_deadline = 0
				emit_signal("message", msg)
		if not _active:
			return
	if _active and _deadline and OS.get_ticks_msec() >= _deadline:
		_finish_close(-1, "NO ANSWER")


func close() -> void:
	_shutdown(true)


func _finish_close(code: int, reason: String) -> void:
	if reason.begins_with("SIGNAL LOST") and not _last_error.empty() and OS.get_ticks_msec() - _last_error_ms <= SERVER_CLOSE_FLUSH_MS:
		reason = _last_error
	close_code = code
	close_reason = reason
	print("NET full closed code=%d reason='%s'" % [code, reason])
	_shutdown(false)
	emit_signal("closed", code, reason)


func _shutdown(graceful: bool) -> void:
	_mutex.lock()
	_running = false
	_mutex.unlock()
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	_mutex.lock()
	if _active and graceful and not _terminal and you != 0:
		_put_packet(_encode_json({"t": "leave"}), true)
	_close_socket(graceful)
	_active = false
	_inbox.clear()
	_mutex.unlock()


func _encode_json(msg: Dictionary) -> PoolByteArray:
	var wire = msg
	match msg.get("t"):
		"rpc":
			wire = msg.duplicate()
			wire["args"] = JsonCodec.encode_args(msg.get("args", []))
			wire.erase("mode")
		"raw":
			if typeof(msg.get("data")) != TYPE_RAW_ARRAY:
				return PoolByteArray()
			wire = msg.duplicate()
			wire["data"] = Marshalls.raw_to_base64(msg.data)
			wire.erase("mode")
	return to_json(wire).to_utf8()


func _decode(raw: PoolByteArray, is_text: bool) -> Dictionary:
	if not is_text:
		return BinaryCodec.decode_frame(raw) if _binary else {}
	var parsed = JSON.parse(raw.get_string_from_utf8())
	if parsed.error != OK or not parsed.result is Dictionary:
		return {}
	var msg: Dictionary = parsed.result
	match msg.get("t"):
		"rpc":
			msg["args"] = JsonCodec.decode_args(msg.get("args", []))
			msg["node"] = str(msg.get("node", ""))
			msg["method"] = str(msg.get("method", ""))
		"raw":
			if not msg.get("data") is String:
				return {}
			msg["data"] = Marshalls.base64_to_raw(msg.data)
	return msg


# Socket hooks and callbacks run with the mutex held, or before the worker starts.
func _open_socket() -> void:
	pass


func _poll_socket() -> void:
	pass


func _put_packet(_data: PoolByteArray, _is_text: bool) -> void:
	pass


func _close_socket(_graceful: bool) -> void:
	pass


func _socket_opened() -> void:
	print("NET full open %s" % endpoint)
	_put_packet(_encode_json(_hello), true)


func _socket_closed(code: int, reason: String) -> void:
	if not _terminal:
		_terminal = true
		_inbox.append(["closed", code, reason])


func _queue_packet(data: PoolByteArray, is_text: bool) -> void:
	if data.empty() or data.size() > MAX_RECEIVE:
		_socket_closed(-1, "INVALID SERVER FRAME LENGTH")
		return
	var answered = data.size() <= 200 and OS.get_ticks_msec() - _main_tick_ms > 400 and _stall_pong(data, is_text)
	_inbox.append(["data", data, is_text, answered])


## Answer game RTT probes while the main loop loads a map or compiles shaders.
func _stall_pong(data: PoolByteArray, is_text: bool) -> bool:
	if is_text and data.get_string_from_utf8().find("\"_rtt_ping\"") < 0:
		return false
	if not is_text and data[0] != BinaryCodec.RPC:
		return false
	var msg = _decode(data, is_text)
	if msg.get("node") != "Net" or msg.get("method") != "_rtt_ping" or msg.args.empty():
		return false
	var pong = {"t": "rpc", "node": "Net", "method": "_rtt_pong", "args": [int(msg.args[0])], "rel": false, "mode": 0}
	var payload = BinaryCodec.encode_frame(pong) if _binary else _encode_json(pong)
	_put_packet(payload, not _binary)
	return not _terminal
