extends SceneTree
## Byte-exact examples and real transcript, plus a desktop microbenchmark.
## godot --path clients/car --no-window -s res://tests/wire_codec.gd

const Bin = preload("res://core/variant_bin.gd")
const JsonCodec = preload("res://core/variant_codec.gd")
const DOCS = "res://../../docs/open-protocol/"
const ITERATIONS = 4000

var _failures = 0
var _workloads = {}


func _init() -> void:
	_examples()
	_more_values()
	_transcript()
	for method in ["_spawn_enemy", "_sync_progress", "_push_transform", "catch-up"]:
		_benchmark(method, _workloads.get(method, []))
	print("WIRE codec failures=%d" % _failures)
	quit(int(_failures > 0))


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("WIRE FAIL ", label)


func _hex(text: String) -> PoolByteArray:
	var wide = text.replace(" ", "").replace("\r", "").replace("\n", "")
	var bytes = PoolByteArray()
	bytes.resize(wide.length() / 2)
	for i in bytes.size():
		bytes[i] = ("0x" + wide.substr(i * 2, 2)).hex_to_int()
	return bytes


func _file(name: String) -> String:
	var file = File.new()
	var err = file.open(DOCS + name, File.READ)
	_check(err == OK, "read " + name)
	return file.get_as_text() if err == OK else ""


func _rpc(node: String, method: String, args: Array, mode := 2) -> Dictionary:
	return {"t": "rpc", "node": node, "method": method, "args": args, "mode": mode, "ch": 0}


func _examples() -> void:
	var section = _file("spec-full.md").get_slice("## 10. Worked binary examples", 1).get_slice("## 11. Errors", 0)
	var fixture = section.split("```text\n")
	_check(fixture.size() == 10, "nine worked binary examples")
	var typed_strings = Bin.typed_array([], Bin.V.STRING)
	var examples = [
		_rpc("Net", "_hello", ['{"name":"3DS","color":1,"skin":0,"colors":[]}', 19]),
		_rpc("Net", "_request_ready", [true]),
		_rpc("Net", "_confirm_run_ready", []),
		_rpc("Main/Players/P_5", "_push_transform", [Vector3(3, 0.2, 0), 1.5, -0.25, Vector3(0, 0, -5)], 1),
		_rpc("Main/Enemies", "_sync_enemies", [PoolIntArray([1]), PoolVector3Array([Vector3(10, 0.5, -4)]), PoolRealArray([1.5])], 1),
		_rpc("Main/RunLoot", "_request_starter", [1, 0]),
		_rpc("WeatherManager", "_receive_phase", [3, 1, 44.045620832318136]),
		_rpc("GameManager/MutationRoll", "_sync_active", [typed_strings, typed_strings]),
		_rpc("Test", "path", [NodePath("/root/Main/Level/Puddles/MainW")])
	]
	var sizes = [80, 32, 28, 86, 76, 51, 63, 67, 68]
	for i in min(9, fixture.size() - 1):
		var bytes = _hex(fixture[i + 1].get_slice("```", 0))
		var encoded = Bin.encode_frame(examples[i])
		if i == 8:
			# The last example supplies only the NodePath value.
			encoded = encoded.subarray(encoded.size() - bytes.size(), encoded.size() - 1)
		_check(bytes.size() == sizes[i] and encoded.hex_encode() == bytes.hex_encode(), "spec example %d bytes" % (i + 1))
		if i != 8:
			_check(Bin.encode_frame(Bin.decode_frame(bytes, true)).hex_encode() == bytes.hex_encode(), "spec example %d round trip" % (i + 1))
	var plain = Bin.decode_frame(Bin.encode_frame(examples[7]))
	_check(plain.get("args") == [[], []], "typed arrays produce ordinary arrays")


func _more_values() -> void:
	var basis = Basis(Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9))
	var key = NodePath("Parent/Child:material:color")
	var data = _hex("000102fdfeff")
	var values = [null, false, -2147483648, 2147483647, -2147483649, 9223372036854775807,
		0.2, INF, -INF, "A 🌦 z", Vector2(2, -3), Rect2(1, 2, 3, 4),
		Transform2D(Vector2(1, 2), Vector2(3, 4), Vector2(5, 6)),
		Plane(1, 2, 3, 4), Quat(0.1, 0.2, 0.3, 0.4),
		AABB(Vector3(1, 2, 3), Vector3(4, 5, 6)), basis,
		Transform(basis, Vector3(8, 9, 10)), Color(0.1, 0.2, 0.3, 0.4),
		key, {key: [true, null, {"int": -42}]}, data,
		PoolIntArray([-1, 123]), PoolRealArray([1.25, -2.5]), PoolStringArray(["", "rain", "🌦"]),
		PoolVector2Array([Vector2(-1, 2)]), PoolVector3Array([Vector3(3, 0, -4)]), PoolColorArray([Color.red])]
	var bytes = Bin.encode_frame(_rpc("Test", "雨", values))
	var result = Bin.decode_frame(bytes)
	_check(result.get("method") == "雨" and _equal(result.get("args"), values), "additional Godot 3 values")
	var godot4_values = [
		[values[17], "120000000000803f000080400000e040000000400000a04000000041000040400000c04000001041000000410000104100002041"],
		[values[24], "22000000030000000100000000000000050000007261696e0000000005000000f09f8ca600000000"],
		[Bin.packed_value(Bin.V.INT64S, [-2147483649, 9223372036854775807]), "1f00000002000000ffffff7fffffffffffffffffffffff7f"],
		[Bin.packed_value(Bin.V.FLOAT64S, [0.2, 1.5]), "21000000020000009a9999999999c93f000000000000f83f"],
		[Bin.packed_value(Bin.V.VECTOR4S, [Quat(1, 2, 3, 4)]), "26000000010000000000803f000000400000404000008040"]
	]
	for fixture in godot4_values:
		var encoded = Bin.encode_frame(_rpc("N", "P", [fixture[0]]))
		_check(encoded.hex_encode() == "03020001004e015001" + fixture[1], "Godot 4 value " + fixture[1].substr(0, 2))
		_check(Bin.encode_frame(Bin.decode_frame(encoded, true)).hex_encode() == encoded.hex_encode(), "Godot 4 value round trip")
	var nan_result = Bin.decode_frame(Bin.encode_frame(_rpc("Test", "nan", [NAN])))
	_check(not nan_result.empty() and is_nan(nan_result.args[0]), "NaN value")
	var raw = {"t": "raw", "data": data, "ch": 7, "mode": 0}
	var raw_bytes = Bin.encode_frame(raw)
	_check(raw_bytes.hex_encode() == "040007000102fdfeff", "raw envelope bytes")
	var decoded = Bin.decode_frame(raw_bytes)
	_check(decoded.get("mode") == 0 and decoded.get("ch") == 7 and _equal(decoded.get("data"), data), "raw envelope decode")
	for i in range(1, bytes.size() - 1):
		_check(Bin.decode_frame(bytes.subarray(0, i - 1)).empty(), "truncated frame at %d" % i)
	var bogus = _hex("03020001004e0150011c000000ffffff7f")
	_check(Bin.decode_frame(bogus).empty(), "reject oversized Variant count")
	var object = _hex("03020001004e01500118000000")
	_check(Bin.decode_frame(object).empty(), "reject object Variant")
	var trailing = Bin.encode_frame(_rpc("N", "P", [1]))
	trailing.append(0)
	_check(Bin.decode_frame(trailing).empty(), "reject extra bytes after RPC args")


func _equal(a, b) -> bool:
	var ta = typeof(a)
	var tb = typeof(b)
	if ta in [TYPE_INT, TYPE_REAL] and tb in [TYPE_INT, TYPE_REAL]:
		if ta == TYPE_INT and tb == TYPE_INT or is_inf(a) or is_inf(b):
			return a == b
		return is_equal_approx(a, b) or (is_nan(a) and is_nan(b))
	if ta != tb:
		return false
	match ta:
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for i in a.size():
				if not _equal(a[i], b[i]):
					return false
			return true
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for key in a:
				if not b.has(key) or not _equal(a[key], b[key]):
					return false
			return true
		TYPE_RAW_ARRAY, TYPE_INT_ARRAY, TYPE_REAL_ARRAY, TYPE_STRING_ARRAY, TYPE_VECTOR2_ARRAY, TYPE_VECTOR3_ARRAY, TYPE_COLOR_ARRAY:
			return _equal(Array(a), Array(b))
	return a == b


func _transcript() -> void:
	var count = 0
	var catchup = []
	var in_catchup = false
	for line in _file("transcripts/full-bin.jsonl").split("\n", false):
		var parsed = JSON.parse(line)
		if parsed.error != OK:
			_check(false, "transcript JSON")
			continue
		var row: Dictionary = parsed.result
		if not row.has("hex") or row.msg.get("t") != "rpc":
			continue
		count += 1
		var bytes = _hex(row.hex)
		var decoded = Bin.decode_frame(bytes)
		var expected: Dictionary = row.msg
		var method = str(expected.get("method"))
		var label = "transcript RPC %d %s" % [count, method]
		_check(decoded.get("node") == expected.get("node") and decoded.get("method") == method
			and decoded.get("ch") == expected.get("ch") and decoded.get("rel") == expected.get("rel"), label + " envelope")
		_check(_equal(decoded.get("args"), JsonCodec.decode_args(expected.get("args"))), label + " args")
		var replay = Bin.decode_frame(bytes, true)
		_check(Bin.encode_frame(replay).hex_encode() == row.hex, label + " bytes")
		if method in ["_spawn_enemy", "_sync_progress", "_push_transform"] and not _workloads.has(method):
			_workloads[method] = [[bytes, replay]]
		if method == "_report_in_run" and catchup.empty():
			in_catchup = true
		if in_catchup and row.dir == "s2c":
			catchup.append([bytes, replay])
			if method == "_confirm_run_ready":
				in_catchup = false
	_workloads["catch-up"] = catchup
	_check(count > 0, "transcript contains RPCs")
	print("WIRE transcript RPCs=%d" % count)


func _benchmark(label: String, batch: Array) -> void:
	if batch.empty():
		_check(false, "benchmark fixture " + label)
		return
	var iterations = int(ITERATIONS / batch.size())
	var start = OS.get_ticks_usec()
	for i in iterations:
		for item in batch:
			Bin.decode_frame(item[0])
	var decode_us = float(OS.get_ticks_usec() - start) / iterations
	start = OS.get_ticks_usec()
	for i in iterations:
		for item in batch:
			Bin.encode_frame(item[1])
	var encode_us = float(OS.get_ticks_usec() - start) / iterations
	print("WIRE perf %s frames=%d decode_us=%.1f encode_us=%.1f" % [label, batch.size(), decode_us, encode_us])
