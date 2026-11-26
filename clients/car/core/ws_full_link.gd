extends "res://core/network_full_link.gd"
## Full-tier WebSocket transport. JSON controls always use the text opcode.

var _ws: WebSocketClient
var _requested_code = -1
var _requested_reason = ""


func _init(server_url: String) -> void:
	endpoint = server_url


func _open_socket() -> void:
	_requested_code = -1
	_requested_reason = ""
	_ws = WebSocketClient.new()
	_ws.verify_ssl = true
	_ws.set_buffers(512, 1024, 512, 1024)
	_ws.connect("connection_established", self, "_on_open")
	_ws.connect("connection_error", self, "_on_error")
	_ws.connect("connection_closed", self, "_on_close")
	_ws.connect("server_close_request", self, "_on_close_request")
	_ws.connect("data_received", self, "_on_data")
	var err = _ws.connect_to_url(endpoint, PoolStringArray(), false)
	if err != OK:
		_socket_closed(-1, "BAD SERVER URL (%d)" % err)


func _poll_socket() -> void:
	if _ws:
		_ws.poll()


func _put_packet(data: PoolByteArray, is_text: bool) -> void:
	if _ws == null or _ws.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		return
	var peer = _ws.get_peer(1)
	if peer.is_connected_to_host():
		peer.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT if is_text else WebSocketPeer.WRITE_MODE_BINARY)
		if peer.put_packet(data) != OK:
			_socket_closed(-1, "WEBSOCKET SEND FAILED")


func _close_socket(graceful: bool) -> void:
	if _ws == null:
		return
	_ws.disconnect("connection_established", self, "_on_open")
	_ws.disconnect("connection_error", self, "_on_error")
	_ws.disconnect("connection_closed", self, "_on_close")
	_ws.disconnect("server_close_request", self, "_on_close_request")
	_ws.disconnect("data_received", self, "_on_data")
	if graceful:
		_ws.poll()
	_ws.disconnect_from_host(1000, "leave" if graceful else "")
	_ws = null


func _on_open(_protocol) -> void:
	_socket_opened()


func _on_error() -> void:
	_socket_closed(_requested_code, _requested_reason if not _requested_reason.empty() else "CONNECTION FAILED")


func _on_close_request(code: int, reason: String) -> void:
	_requested_code = code
	_requested_reason = reason


func _on_close(clean: bool) -> void:
	var reason = _requested_reason
	if reason.empty():
		reason = "SIGNAL LOST" if clean else "SIGNAL LOST - NO CLOSE FRAME"
	_socket_closed(_requested_code, reason)


func _on_data() -> void:
	var peer = _ws.get_peer(1)
	while not _terminal and peer.get_available_packet_count() > 0:
		var data = peer.get_packet()
		_queue_packet(data, peer.was_string_packet())
