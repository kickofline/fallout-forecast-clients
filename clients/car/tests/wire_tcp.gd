extends SceneTree
## Loopback TCP framing, stalled-main-loop RTT, and remote disconnect.
## godot --path clients/car --no-window -s res://tests/wire_tcp.gd

const TcpLink = preload("res://core/tcp_full_link.gd")
const Bin = preload("res://core/variant_bin.gd")
const PORT = 17953

var _link
var _received = []
var _closed = []
var _failures = 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("WIRE TCP FAIL ", label)


func _frame(payload: PoolByteArray) -> PoolByteArray:
	var stream = StreamPeerBuffer.new()
	stream.put_u32(payload.size())
	stream.put_data(payload)
	return stream.data_array


func _read(peer: StreamPeerTCP) -> PoolByteArray:
	var deadline = OS.get_ticks_msec() + 1000
	while peer.get_available_bytes() < 4 and OS.get_ticks_msec() < deadline:
		OS.delay_msec(5)
	if peer.get_available_bytes() < 4:
		return PoolByteArray()
	var size = peer.get_u32()
	while peer.get_available_bytes() < size and OS.get_ticks_msec() < deadline:
		OS.delay_msec(5)
	if peer.get_available_bytes() < size:
		return PoolByteArray()
	return peer.get_data(size)[1]


func _on_message(msg: Dictionary) -> void:
	_received.append(msg)


func _on_closed(code: int, why: String) -> void:
	_closed.append([code, why])


func _run() -> void:
	var server = TCP_Server.new()
	if server.listen(PORT, "127.0.0.1") != OK:
		printerr("WIRE TCP cannot listen on loopback port ", PORT)
		quit(1)
		return
	_link = TcpLink.new("127.0.0.1:%d" % PORT)
	_link.connect("message", self, "_on_message")
	_link.connect("closed", self, "_on_closed")
	_link.open({"v": 1, "tier": "full", "enc": "bin"})
	var deadline = OS.get_ticks_msec() + 1000
	while not server.is_connection_available() and OS.get_ticks_msec() < deadline:
		OS.delay_msec(5)
	if not server.is_connection_available():
		_link.close()
		printerr("WIRE TCP no connection")
		quit(1)
		return
	var peer = server.take_connection()
	peer.set_no_delay(true)
	var hello = JSON.parse(_read(peer).get_string_from_utf8()).result
	_check(hello is Dictionary and hello.get("t") == "hello" and hello.get("enc") == "bin", "JSON hello")
	var welcome = _frame(to_json({"t": "welcome", "enc": "bin", "you": 25}).to_utf8())
	peer.put_data(welcome.subarray(0, 1))
	OS.delay_msec(50)
	_link.poll(0.0)
	_check(_received.empty(), "partial length")
	peer.put_data(welcome.subarray(2, 6))
	OS.delay_msec(50)
	_link.poll(0.0)
	_check(_received.empty(), "partial payload")
	OS.delay_msec(450)
	var batch = welcome.subarray(7, welcome.size() - 1)
	var raw = PoolByteArray([0, 255, 1, 2])
	var rpc = {"t": "rpc", "node": "Net", "method": "_rtt_ping", "args": [314, 2.5], "mode": 0}
	batch.append_array(_frame(Bin.encode_frame(rpc)))
	batch.append_array(_frame(Bin.encode_frame({"t": "raw", "data": raw, "ch": 5, "mode": 1})))
	peer.put_data(batch)
	var pong = Bin.decode_frame(_read(peer))
	_check(pong.get("method") == "_rtt_pong" and pong.get("args") == [314], "binary RTT reply while main loop stalled")
	_check(_received.empty(), "thread does not emit messages")
	_link.poll(0.0)
	_check(_received.size() == 3, "three coalesced messages in order")
	if _received.size() == 3:
		_check(_received[0].get("t") == "welcome" and _received[1].get("method") == "_rtt_ping", "coalesced text and RPC")
		_check(_received[1].get("rtt_answered") == true, "main loop sees that RTT is already answered")
		_check(_received[2].get("t") == "raw" and _received[2].get("data").hex_encode() == raw.hex_encode(), "inbound raw bytes")
	_link.send({"t": "raw", "data": raw, "ch": 3, "mode": 0})
	var outbound = Bin.decode_frame(_read(peer))
	_check(outbound.get("t") == "raw" and outbound.get("ch") == 3 and outbound.data.hex_encode() == raw.hex_encode(), "outbound raw bytes")
	peer.put_data(_frame(to_json({"t": "error", "msg": "fixture finished"}).to_utf8()))
	peer.disconnect_from_host()
	deadline = OS.get_ticks_msec() + 1000
	while _closed.empty() and OS.get_ticks_msec() < deadline:
		_link.poll(0.0)
		OS.delay_msec(5)
	_link.poll(0.0)
	_check(_closed == [[-1, "fixture finished"]], "EOF reports server diagnostic once")
	_link.close()
	server.stop()
	print("WIRE TCP failures=%d" % _failures)
	quit(int(_failures > 0))
