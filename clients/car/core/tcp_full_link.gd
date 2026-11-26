extends "res://core/network_full_link.gd"
## Full-tier raw TCP. Each message has a u32 LE payload length (§3.2).

const MAX_QUEUE = 524288
const READ_CHUNK = 65536
const LEAVE_TIMEOUT_MS = 200

var _tcp: StreamPeerTCP
var _connected = false
var _rx = PoolByteArray()
var _tx = PoolByteArray()
var _reader = StreamPeerBuffer.new()
var _writer = StreamPeerBuffer.new()


func _init(address: String) -> void:
	endpoint = address


func _open_socket() -> void:
	var address = endpoint.strip_edges()
	if address.begins_with("tcp://"):
		address = address.substr(6)
	var split = address.rfind(":")
	var host = address.substr(0, split) if split >= 0 else ""
	var port = address.substr(split + 1)
	if host.begins_with("[") and host.ends_with("]"):
		host = host.substr(1, host.length() - 2)
	if host.empty() or not port.is_valid_integer() or int(port) < 1 or int(port) > 65535:
		_socket_closed(-1, "TCP SERVER MUST BE HOST:PORT")
		return
	_tcp = StreamPeerTCP.new()
	var err = _tcp.connect_to_host(host, int(port))
	if err != OK:
		_socket_closed(-1, "TCP CONNECTION FAILED (%d)" % err)


func _poll_socket() -> void:
	var status = _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		_socket_closed(-1, "SIGNAL LOST" if _connected else "TCP CONNECTION FAILED")
		return
	if not _connected:
		_connected = true
		_tcp.set_no_delay(true)
		_socket_opened()
		if _terminal:
			return
	# A non-blocking read of one byte also lets Godot detect EOF when no
	# bytes are pending. An idle connection instead returns OK with 0 bytes.
	var result = _tcp.get_partial_data(max(1, min(READ_CHUNK, _tcp.get_available_bytes())))
	if result[0] != OK:
		_socket_closed(-1, "SIGNAL LOST")
		return
	if not result[1].empty():
		_rx.append_array(result[1])
		_receive_frames()
	_flush()


func _receive_frames() -> void:
	_reader.data_array = _rx
	while _reader.get_available_bytes() >= 4:
		var start = _reader.get_position()
		var length = _reader.get_u32()
		if length < 1 or length > MAX_RECEIVE:
			_socket_closed(-1, "INVALID TCP FRAME LENGTH")
			break
		if _reader.get_available_bytes() < length:
			_reader.seek(start)
			break
		var data: PoolByteArray = _reader.get_data(length)[1]
		_queue_packet(data, data[0] >= 0x09)
	var consumed = _reader.get_position()
	_reader.clear()
	if consumed == _rx.size():
		_rx.resize(0)
	elif consumed > 0:
		_rx = _rx.subarray(consumed, _rx.size() - 1)


func _put_packet(data: PoolByteArray, _is_text: bool) -> void:
	if not _connected or _terminal:
		return
	if _tx.size() + 4 + data.size() > MAX_QUEUE:
		_socket_closed(-1, "TCP SEND BUFFER FULL")
		return
	_writer.seek(0)
	_writer.put_u32(data.size())
	_tx.append_array(_writer.data_array)
	_tx.append_array(data)
	_flush()


func _flush() -> void:
	if _tx.empty() or _terminal:
		return
	var result = _tcp.put_partial_data(_tx)
	if result[0] != OK:
		_socket_closed(-1, "TCP SEND FAILED")
	elif result[1] == _tx.size():
		_tx.resize(0)
	elif result[1] > 0:
		_tx = _tx.subarray(result[1], _tx.size() - 1)


func _close_socket(graceful: bool) -> void:
	if _tcp:
		if graceful:
			var deadline = OS.get_ticks_msec() + LEAVE_TIMEOUT_MS
			while not _tx.empty() and not _terminal and OS.get_ticks_msec() < deadline:
				_flush()
				if not _tx.empty():
					OS.delay_msec(2)
		_tcp.disconnect_from_host()
		_tcp = null
	_connected = false
	_rx.resize(0)
	_tx.resize(0)
