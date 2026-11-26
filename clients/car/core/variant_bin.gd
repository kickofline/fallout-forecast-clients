extends Reference
## Godot 4.7 Variant wire format for Open Protocol Full (§§8–10).
## StreamPeerBuffer handles little-endian scalars and bulk byte copies.
## Decode projects Godot 4-only types to the same values as variant_codec.gd.

const JsonCodec = preload("res://core/variant_codec.gd")
const RPC = 0x03
const RAW = 0x04
const MAX_DEPTH = 32
const FLAG_64 = 1 << 16

# Godot 4 wire IDs, independent of Godot 3's TYPE_* constants.
enum V {
	NIL, BOOL, INT, FLOAT, STRING, VECTOR2, VECTOR2I, RECT2, RECT2I, VECTOR3,
	VECTOR3I, TRANSFORM2D, VECTOR4, VECTOR4I, PLANE, QUAT, BOX3, BASIS, TRANSFORM3D,
	PROJECTION, COLOR, STRING_NAME, NODE_PATH, RESOURCE_ID, OBJECT, CALLABLE, SIGNAL,
	DICTIONARY, ARRAY, BYTES, INT32S, INT64S, FLOAT32S, FLOAT64S, STRINGS,
	VECTOR2S, VECTOR3S, COLORS, VECTOR4S
}
const PACKED_TYPES = [V.BYTES, V.INT32S, V.FLOAT32S, V.STRINGS, V.VECTOR2S, V.VECTOR3S, V.COLORS]
const PACKED_STRIDES = [4, 8, 4, 8, 4, 8, 12, 16, 16]

# Optional metadata for values Godot 3 cannot distinguish on its own.
# The normal decode path returns ordinary Godot 3 Variants.
class TypedContainer:
	extends Reference
	var value
	var kinds: int
	var first
	var second

	func _init(contents, type_kinds: int, first_type, second_type = null) -> void:
		value = contents
		kinds = type_kinds
		first = first_type
		second = second_type


class PackedValue:
	extends Reference
	var wire_type: int
	var values: Array

	func _init(type: int, contents: Array) -> void:
		wire_type = type
		values = contents


static func typed_array(values: Array, builtin_type: int) -> TypedContainer:
	return TypedContainer.new(values, 1, builtin_type)


# Godot 3 has no packed int64, float64 or Vector4 type. Supply an Array
# (using Quats for Vector4s, as in the JSON codec) with its wire type.
static func packed_value(wire_type: int, values: Array) -> PackedValue:
	return PackedValue.new(wire_type, values)


static func encode_frame(msg: Dictionary) -> PoolByteArray:
	var w = Writer.new()
	var mode = int(msg.get("mode", 2 if msg.get("rel", true) else 1))
	var channel = int(msg.get("ch", 0))
	if mode < 0 or mode > 2 or channel < 0 or channel > 255:
		return PoolByteArray()
	if msg.get("t") == "raw":
		if typeof(msg.get("data")) != TYPE_RAW_ARRAY:
			return PoolByteArray()
		w.stream.put_u8(RAW)
		w.stream.put_u8(mode)
		w.stream.put_u8(channel)
		w.stream.put_data(msg.data)
	elif msg.get("t") == "rpc":
		var path = str(msg.get("node", ""))
		if path.begins_with("/root/"):
			path = path.substr(6)
		elif path.begins_with("/"):
			path = path.substr(1)
		var node_bytes = path.to_utf8()
		var method_bytes = str(msg.get("method", "")).to_utf8()
		var args = msg.get("args", [])
		if node_bytes.size() > 65535 or method_bytes.size() > 255 or not args is Array or args.size() > 255:
			return PoolByteArray()
		w.stream.put_u8(RPC)
		w.stream.put_u8(mode)
		w.stream.put_u8(channel)
		w.stream.put_u16(node_bytes.size())
		w.stream.put_data(node_bytes)
		w.stream.put_u8(method_bytes.size())
		w.stream.put_data(method_bytes)
		w.stream.put_u8(args.size())
		for arg in args:
			w.value(arg, 0)
			if w.bad:
				return PoolByteArray()
	else:
		return PoolByteArray()
	return w.stream.data_array


static func decode_frame(bytes: PoolByteArray, preserve_types := false) -> Dictionary:
	if bytes.size() < 3:
		return {}
	var r = Reader.new(bytes, preserve_types)
	var tag = r.stream.get_u8()
	var mode = r.stream.get_u8()
	var channel = r.stream.get_u8()
	if mode > 2:
		return {}
	if tag == RAW:
		return {"t": "raw", "mode": mode, "ch": channel, "rel": mode == 2,
			"data": r.bytes(r.stream.get_available_bytes())}
	if tag != RPC or not r.need(2):
		return {}
	var node = r.string(r.stream.get_u16())
	if not r.need(1):
		return {}
	var method = r.string(r.stream.get_u8())
	if not r.need(1):
		return {}
	var count = r.stream.get_u8()
	if not r.need(count * 4):
		return {}
	var args = []
	args.resize(count)
	for i in count:
		args[i] = r.value(0)
		if r.bad:
			return {}
	if r.stream.get_available_bytes() != 0:
		return {}
	return {"t": "rpc", "node": node, "method": method, "args": args,
		"mode": mode, "ch": channel, "rel": mode == 2}


class Writer:
	var stream = StreamPeerBuffer.new()
	var scratch: StreamPeerBuffer
	var bad = false

	func padded_bytes(raw: PoolByteArray) -> void:
		stream.put_u32(raw.size())
		if not raw.empty():
			stream.put_data(raw)
			match (-raw.size()) & 3:
				1:
					stream.put_u8(0)
				2:
					stream.put_u16(0)
				3:
					stream.put_u16(0)
					stream.put_u8(0)

	func vec2(v: Vector2) -> void:
		stream.put_float(v.x)
		stream.put_float(v.y)

	func vec3(v: Vector3) -> void:
		stream.put_float(v.x)
		stream.put_float(v.y)
		stream.put_float(v.z)

	func rgba(c: Color) -> void:
		stream.put_float(c.r)
		stream.put_float(c.g)
		stream.put_float(c.b)
		stream.put_float(c.a)

	func quat(q: Quat) -> void:
		stream.put_float(q.x)
		stream.put_float(q.y)
		stream.put_float(q.z)
		stream.put_float(q.w)

	func basis(b: Basis) -> void:
		for row in 3:
			stream.put_float(b.x[row])
			stream.put_float(b.y[row])
			stream.put_float(b.z[row])

	func float_value(n: float) -> void:
		# Compare after an actual f32 round trip. Variant floats are double.
		if scratch == null:
			scratch = StreamPeerBuffer.new()
		scratch.seek(0)
		scratch.put_float(n)
		scratch.seek(0)
		if scratch.get_float() == n:
			stream.put_u32(V.FLOAT)
			stream.put_float(n)
		else:
			stream.put_u32(V.FLOAT | FLAG_64)
			stream.put_double(n)

	func node_path(path: NodePath) -> void:
		stream.put_u32(V.NODE_PATH)
		stream.put_u32(path.get_name_count() | 0x80000000)
		stream.put_u32(path.get_subname_count())
		stream.put_u32(int(path.is_absolute()))
		for i in path.get_name_count():
			padded_bytes(path.get_name(i).to_utf8())
		for i in path.get_subname_count():
			padded_bytes(path.get_subname(i).to_utf8())

	func container_type(kind: int, hint) -> void:
		match kind:
			1:
				stream.put_u32(hint)
			2, 3:
				padded_bytes(str(hint).to_utf8())

	func container(v, kinds: int, first, second, depth: int) -> void:
		var dictionary = v is Dictionary
		stream.put_u32((V.DICTIONARY if dictionary else V.ARRAY) | (kinds << 16))
		container_type(kinds & 3, first)
		if dictionary:
			container_type((kinds >> 2) & 3, second)
		stream.put_u32(v.size())
		for item in v:
			value(item, depth + 1)
			if dictionary:
				value(v[item], depth + 1)
			if bad:
				return

	func packed(v, wire_type: int) -> void:
		stream.put_u32(wire_type)
		if wire_type == V.BYTES:
			padded_bytes(v)
			return
		stream.put_u32(v.size())
		match wire_type:
			V.INT32S:
				for n in v:
					stream.put_32(n)
			V.INT64S:
				for n in v:
					stream.put_64(n)
			V.FLOAT32S:
				for n in v:
					stream.put_float(n)
			V.FLOAT64S:
				for n in v:
					stream.put_double(n)
			V.STRINGS:
				for s in v:
					# Godot's PackedStringArray includes the terminating NUL.
					var utf8 = s.to_utf8()
					utf8.append(0)
					padded_bytes(utf8)
			V.VECTOR2S:
				for a in v:
					vec2(a)
			V.VECTOR3S:
				for a in v:
					vec3(a)
			V.COLORS:
				for c in v:
					rgba(c)
			V.VECTOR4S:
				for q in v:
					quat(q)

	func value(v, depth: int) -> void:
		if bad or depth > MAX_DEPTH:
			bad = true
			return
		match typeof(v):
			TYPE_NIL:
				stream.put_u32(V.NIL)
			TYPE_BOOL:
				stream.put_u32(V.BOOL)
				stream.put_u32(int(v))
			TYPE_INT:
				if v >= -2147483648 and v <= 2147483647:
					stream.put_u32(V.INT)
					stream.put_32(v)
				else:
					stream.put_u32(V.INT | FLAG_64)
					stream.put_64(v)
			TYPE_REAL:
				float_value(v)
			TYPE_STRING:
				stream.put_u32(V.STRING)
				padded_bytes(v.to_utf8())
			TYPE_VECTOR2:
				stream.put_u32(V.VECTOR2)
				vec2(v)
			TYPE_VECTOR3:
				stream.put_u32(V.VECTOR3)
				vec3(v)
			TYPE_RECT2:
				stream.put_u32(V.RECT2)
				vec2(v.position)
				vec2(v.size)
			TYPE_TRANSFORM2D:
				stream.put_u32(V.TRANSFORM2D)
				vec2(v.x)
				vec2(v.y)
				vec2(v.origin)
			TYPE_PLANE:
				stream.put_u32(V.PLANE)
				vec3(v.normal)
				stream.put_float(v.d)
			TYPE_QUAT:
				stream.put_u32(V.QUAT)
				quat(v)
			TYPE_AABB:
				stream.put_u32(V.BOX3)
				vec3(v.position)
				vec3(v.size)
			TYPE_BASIS:
				stream.put_u32(V.BASIS)
				basis(v)
			TYPE_TRANSFORM:
				stream.put_u32(V.TRANSFORM3D)
				basis(v.basis)
				vec3(v.origin)
			TYPE_COLOR:
				stream.put_u32(V.COLOR)
				rgba(v)
			TYPE_NODE_PATH:
				node_path(v)
			TYPE_ARRAY, TYPE_DICTIONARY:
				container(v, 0, null, null, depth)
			TYPE_RAW_ARRAY, TYPE_INT_ARRAY, TYPE_REAL_ARRAY, TYPE_STRING_ARRAY, TYPE_VECTOR2_ARRAY, TYPE_VECTOR3_ARRAY, TYPE_COLOR_ARRAY:
				packed(v, PACKED_TYPES[typeof(v) - TYPE_RAW_ARRAY])
			TYPE_OBJECT:
				if v is TypedContainer:
					container(v.value, v.kinds, v.first, v.second, depth)
				elif v is PackedValue and v.wire_type in [V.INT64S, V.FLOAT64S, V.VECTOR4S]:
					packed(v.values, v.wire_type)
				elif v is JsonCodec.Raw:
					value(JsonCodec.decode(v.json), depth + 1)
				else:
					bad = true
			_:
				bad = true


class Reader:
	var stream = StreamPeerBuffer.new()
	var bad = false
	var preserve_types: bool

	func _init(data: PoolByteArray, preserve: bool) -> void:
		stream.data_array = data
		preserve_types = preserve

	func need(n: int) -> bool:
		if n < 0 or n > stream.get_available_bytes():
			bad = true
		return not bad

	func bytes(n: int) -> PoolByteArray:
		if n == 0 or not need(n):
			return PoolByteArray()
		return stream.get_data(n)[1]

	func string(n: int) -> String:
		return stream.get_utf8_string(n) if n > 0 and need(n) else ""

	func padded_bytes() -> PoolByteArray:
		if not need(4):
			return PoolByteArray()
		var length = stream.get_u32()
		var pad = (-length) & 3
		if not need(length + pad):
			return PoolByteArray()
		var raw = bytes(length)
		if pad:
			stream.seek(stream.get_position() + pad)
		return raw

	func str4() -> String:
		if not need(4):
			return ""
		var length = stream.get_u32()
		var pad = (-length) & 3
		if not need(length + pad):
			return ""
		var text = string(length)
		if pad:
			stream.seek(stream.get_position() + pad)
		return text

	func component(wide: bool) -> float:
		return stream.get_double() if wide else stream.get_float()

	func vec2(wide: bool) -> Vector2:
		if wide:
			return Vector2(stream.get_double(), stream.get_double())
		return Vector2(stream.get_float(), stream.get_float())

	func vec3(wide: bool) -> Vector3:
		if wide:
			return Vector3(stream.get_double(), stream.get_double(), stream.get_double())
		return Vector3(stream.get_float(), stream.get_float(), stream.get_float())

	func quat(wide: bool) -> Quat:
		return Quat(component(wide), component(wide), component(wide), component(wide))

	func rgba() -> Color:
		return Color(stream.get_float(), stream.get_float(), stream.get_float(), stream.get_float())

	func basis(wide: bool) -> Basis:
		var a = vec3(wide)
		var b = vec3(wide)
		var c = vec3(wide)
		return Basis(Vector3(a.x, b.x, c.x), Vector3(a.y, b.y, c.y), Vector3(a.z, b.z, c.z))

	func node_path() -> NodePath:
		if not need(12):
			return NodePath("")
		var names = stream.get_u32()
		var subnames = stream.get_u32()
		var flags = stream.get_u32()
		if (names & 0x80000000) == 0:
			bad = true
			return NodePath("")
		names &= 0x7fffffff
		subnames += int((flags & 2) != 0)  # Legacy property subname.
		if not need((names + subnames) * 4):
			return NodePath("")
		var parts = PoolStringArray()
		for i in names:
			parts.append(str4())
			if bad:
				return NodePath("")
		var path = ("/" if flags & 1 else "") + parts.join("/")
		for i in subnames:
			path += ":" + str4()
			if bad:
				return NodePath("")
		return NodePath(path)

	func container_type(kind: int):
		match kind:
			1:
				if need(4):
					return stream.get_u32()
			2, 3:
				return str4()
		return null

	func container(dictionary: bool, kinds: int, depth: int):
		var first = container_type(kinds & 3)
		var second = container_type((kinds >> 2) & 3) if dictionary else null
		if not need(4):
			return null
		var count = stream.get_u32() & 0x7fffffff
		if not need(count * (8 if dictionary else 4)):
			return null
		var out
		if dictionary:
			out = {}
			for i in count:
				var key = value(depth + 1)
				var item = value(depth + 1)
				if bad:
					return null
				out[key] = item
		else:
			out = []
			out.resize(count)
			for i in count:
				out[i] = value(depth + 1)
				if bad:
					return null
		if preserve_types and kinds:
			return TypedContainer.new(out, kinds, first, second)
		return out

	func packed(wire_type: int, wide: bool):
		if wire_type == V.BYTES:
			return padded_bytes()
		if not need(4):
			return null
		var count = stream.get_u32()
		var stride = PACKED_STRIDES[wire_type - V.INT32S]
		if wide and (wire_type == V.VECTOR2S or wire_type == V.VECTOR3S or wire_type == V.VECTOR4S):
			stride *= 2
		if not need(count * stride):
			return null
		match wire_type:
			V.INT32S:
				var ints = PoolIntArray()
				ints.resize(count)
				for i in count:
					ints[i] = stream.get_32()
				return ints
			V.INT64S:
				var longs = []
				longs.resize(count)
				for i in count:
					longs[i] = stream.get_64()
				return PackedValue.new(wire_type, longs) if preserve_types else longs
			V.FLOAT32S, V.FLOAT64S:
				if preserve_types and wire_type == V.FLOAT64S:
					var doubles = []
					doubles.resize(count)
					for i in count:
						doubles[i] = stream.get_double()
					return PackedValue.new(wire_type, doubles)
				var floats = PoolRealArray()
				floats.resize(count)
				for i in count:
					floats[i] = component(wire_type == V.FLOAT64S)
				return floats
			V.STRINGS:
				var strings = PoolStringArray()
				strings.resize(count)
				for i in count:
					strings[i] = str4()
					if bad:
						return null
				return strings
			V.VECTOR2S:
				var points = PoolVector2Array()
				points.resize(count)
				for i in count:
					points[i] = vec2(wide)
				return points
			V.VECTOR3S:
				var points = PoolVector3Array()
				points.resize(count)
				for i in count:
					points[i] = vec3(wide)
				return points
			V.COLORS:
				var colors = PoolColorArray()
				colors.resize(count)
				for i in count:
					colors[i] = rgba()
				return colors
			V.VECTOR4S:
				var points = []
				points.resize(count)
				for i in count:
					points[i] = quat(wide)
				return PackedValue.new(wire_type, points) if preserve_types else points

	func value(depth: int):
		if depth > MAX_DEPTH or not need(4):
			bad = true
			return null
		var header = stream.get_u32()
		var type = header & 255
		var wide = (header & FLAG_64) != 0
		var width = 8 if wide else 4
		match type:
			V.NIL:
				return null
			V.BOOL:
				return stream.get_u32() != 0 if need(4) else null
			V.INT:
				if need(width):
					return stream.get_64() if wide else stream.get_32()
			V.FLOAT:
				if need(width):
					return component(wide)
			V.STRING, V.STRING_NAME:
				return str4()
			V.VECTOR2:
				if need(2 * width):
					return vec2(wide)
			V.VECTOR2I:
				if need(8):
					return Vector2(stream.get_32(), stream.get_32())
			V.RECT2:
				if need(4 * width):
					return Rect2(vec2(wide), vec2(wide))
			V.RECT2I:
				if need(16):
					return Rect2(stream.get_32(), stream.get_32(), stream.get_32(), stream.get_32())
			V.VECTOR3:
				if need(3 * width):
					return vec3(wide)
			V.VECTOR3I:
				if need(12):
					return Vector3(stream.get_32(), stream.get_32(), stream.get_32())
			V.TRANSFORM2D:
				if need(6 * width):
					return Transform2D(vec2(wide), vec2(wide), vec2(wide))
			V.VECTOR4, V.QUAT:
				if need(4 * width):
					return quat(wide)
			V.VECTOR4I:
				if need(16):
					return Quat(stream.get_32(), stream.get_32(), stream.get_32(), stream.get_32())
			V.PLANE:
				if need(4 * width):
					return Plane(vec3(wide), component(wide))
			V.BOX3:
				if need(6 * width):
					return AABB(vec3(wide), vec3(wide))
			V.BASIS:
				if need(9 * width):
					return basis(wide)
			V.TRANSFORM3D:
				if need(12 * width):
					return Transform(basis(wide), vec3(wide))
			V.PROJECTION:
				if need(16 * width):
					var columns = []
					for i in 4:
						columns.append([component(wide), component(wide), component(wide), component(wide)])
					return columns
			V.COLOR:
				if need(16):
					return rgba()
			V.NODE_PATH:
				return node_path()
			V.DICTIONARY:
				return container(true, (header >> 16) & 15, depth)
			V.ARRAY:
				return container(false, (header >> 16) & 3, depth)
			_:
				if type >= V.BYTES and type <= V.VECTOR4S:
					return packed(type, wide)
				bad = true
		return null
