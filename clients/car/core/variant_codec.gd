extends Reference
## Open Protocol Full tier: Godot Variant <-> JSON mapping (spec-full.md §7).
##
## decode(): JSON value (as parsed by Godot 3's JSON.parse) -> Godot 3 Variant.
## encode(): Godot 3 Variant -> JSON-ready value (feed it to to_json()).
##
## Godot 3's JSON parser turns every number into a float, so decode() turns
## integral numbers (|n| <= 2^53) back into ints. Use float() where a value is
## a float that can be integral (100.0 health, 12.0 seconds).
##
## Godot 4-only types map to the closest Godot 3 value: v2i -> Vector2,
## v3i -> Vector3, rect2i -> Rect2, v4/v4i -> Quat, proj -> Array of 4 Arrays,
## pi64 -> Array of ints, pf64 -> PoolRealArray, pv4 -> Array of Quat,
## sn -> String.

const MAX_SAFE = 9007199254740991.0


## A value sent verbatim (already in wire form), e.g. Codec.raw_int(5).
class Raw:
	extends Reference
	var json
	func _init(j) -> void:
		json = j


static func raw_int(n: int) -> Raw:
	return Raw.new({"_t": "i", "v": n})


static func raw_float(x: float) -> Raw:
	return Raw.new({"_t": "f", "v": x})


static func decode_args(args) -> Array:
	var out = []
	if args is Array:
		for a in args:
			out.append(decode(a))
	return out


static func encode_args(args: Array) -> Array:
	var out = []
	for a in args:
		out.append(encode(a))
	return out


static func decode(j):
	match typeof(j):
		TYPE_REAL:
			if j == floor(j) and abs(j) <= MAX_SAFE:
				return int(j)
			return j
		TYPE_ARRAY:
			var a = []
			a.resize(j.size())
			for i in j.size():
				a[i] = decode(j[i])
			return a
		TYPE_DICTIONARY:
			if j.size() == 2 and j.has("_t") and j.has("v") and j["_t"] is String:
				return _tagged(j["_t"], j["v"])
			var d = {}
			for k in j:
				d[k] = decode(j[k])
			return d
	return j


static func _f(x) -> float:
	return float(x) if x != null else 0.0


static func _v3(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(_f(a[0]), _f(a[1]), _f(a[2]))
	return Vector3.ZERO


static func _v2(a) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(_f(a[0]), _f(a[1]))
	return Vector2.ZERO


static func _tagged(t: String, v):
	match t:
		"v3", "v3i":
			return _v3(v)
		"pv3":
			var p = PoolVector3Array()
			if v is Array:
				p.resize(v.size())
				for i in v.size():
					p[i] = _v3(v[i])
			return p
		"pi32":
			var pi = PoolIntArray()
			if v is Array:
				pi.resize(v.size())
				for i in v.size():
					pi[i] = int(v[i])
			return pi
		"pf32", "pf64":
			var pf = PoolRealArray()
			if v is Array:
				pf.resize(v.size())
				for i in v.size():
					pf[i] = _f(v[i])
			return pf
		"dict":
			var d = {}
			if v is Array:
				for pair in v:
					if pair is Array and pair.size() == 2:
						d[decode(pair[0])] = decode(pair[1])
			return d
		"np":
			return NodePath(str(v))
		"sn":
			return str(v)
		"i":
			return int(v)
		"i64":
			return int(str(v))
		"f":
			if v is String:
				match v:
					"NaN":
						return NAN
					"Inf":
						return INF
					"-Inf":
						return -INF
				return float(v)
			return _f(v)
		"v2", "v2i":
			return _v2(v)
		"rect2", "rect2i":
			if v is Array and v.size() >= 4:
				return Rect2(_f(v[0]), _f(v[1]), _f(v[2]), _f(v[3]))
			return Rect2()
		"color":
			if v is Array and v.size() >= 3:
				return Color(_f(v[0]), _f(v[1]), _f(v[2]), _f(v[3]) if v.size() >= 4 else 1.0)
			return Color.white
		"basis":
			if v is Array and v.size() >= 3:
				return Basis(_v3(v[0]), _v3(v[1]), _v3(v[2]))
			return Basis()
		"xform3d":
			if v is Array and v.size() >= 4:
				return Transform(Basis(_v3(v[0]), _v3(v[1]), _v3(v[2])), _v3(v[3]))
			return Transform()
		"xform2d":
			if v is Array and v.size() >= 3:
				return Transform2D(_v2(v[0]), _v2(v[1]), _v2(v[2]))
			return Transform2D()
		"quat", "v4", "v4i":
			if v is Array and v.size() >= 4:
				return Quat(_f(v[0]), _f(v[1]), _f(v[2]), _f(v[3]))
			return Quat()
		"plane":
			if v is Array and v.size() >= 4:
				return Plane(_f(v[0]), _f(v[1]), _f(v[2]), _f(v[3]))
			return Plane()
		"aabb":
			if v is Array and v.size() >= 2:
				return AABB(_v3(v[0]), _v3(v[1]))
			return AABB()
		"bytes":
			return Marshalls.base64_to_raw(str(v))
		"pi64":
			var a64 = []
			if v is Array:
				for x in v:
					a64.append(int(str(x)) if x is String else int(x))
			return a64
		"pstr":
			var ps = PoolStringArray()
			if v is Array:
				for x in v:
					ps.append(str(x))
			return ps
		"pv2":
			var p2 = PoolVector2Array()
			if v is Array:
				for x in v:
					p2.append(_v2(x))
			return p2
		"pcol":
			var pc = PoolColorArray()
			if v is Array:
				for x in v:
					pc.append(_tagged("color", x))
			return pc
		"pv4":
			var p4 = []
			if v is Array:
				for x in v:
					p4.append(_tagged("quat", x))
			return p4
		"proj":
			return decode(v)
	# Unknown tag (a newer server): keep the payload.
	return decode(v)


static func _a3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _num(x: float):
	if is_nan(x):
		return {"_t": "f", "v": "NaN"}
	if is_inf(x):
		return {"_t": "f", "v": "Inf" if x > 0.0 else "-Inf"}
	return x


static func encode(v):
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return v
		TYPE_INT:
			if abs(v) > MAX_SAFE:
				return {"_t": "i64", "v": str(v)}
			return v
		TYPE_REAL:
			return _num(v)
		TYPE_VECTOR3:
			return {"_t": "v3", "v": _a3(v)}
		TYPE_VECTOR2:
			return {"_t": "v2", "v": [v.x, v.y]}
		TYPE_RECT2:
			return {"_t": "rect2", "v": [v.position.x, v.position.y, v.size.x, v.size.y]}
		TYPE_TRANSFORM2D:
			return {"_t": "xform2d", "v": [[v.x.x, v.x.y], [v.y.x, v.y.y], [v.origin.x, v.origin.y]]}
		TYPE_PLANE:
			return {"_t": "plane", "v": [v.normal.x, v.normal.y, v.normal.z, v.d]}
		TYPE_QUAT:
			return {"_t": "quat", "v": [v.x, v.y, v.z, v.w]}
		TYPE_AABB:
			return {"_t": "aabb", "v": [_a3(v.position), _a3(v.size)]}
		TYPE_BASIS:
			return {"_t": "basis", "v": [_a3(v.x), _a3(v.y), _a3(v.z)]}
		TYPE_TRANSFORM:
			return {"_t": "xform3d", "v": [_a3(v.basis.x), _a3(v.basis.y), _a3(v.basis.z), _a3(v.origin)]}
		TYPE_COLOR:
			return {"_t": "color", "v": [v.r, v.g, v.b, v.a]}
		TYPE_NODE_PATH:
			return {"_t": "np", "v": str(v)}
		TYPE_DICTIONARY:
			var plain = true
			for k in v:
				if not (k is String) or k == "_t":
					plain = false
					break
			if plain:
				var d = {}
				for k in v:
					d[k] = encode(v[k])
				return d
			var pairs = []
			for k in v:
				pairs.append([encode(k), encode(v[k])])
			return {"_t": "dict", "v": pairs}
		TYPE_ARRAY:
			var a = []
			for x in v:
				a.append(encode(x))
			return a
		TYPE_RAW_ARRAY:
			return {"_t": "bytes", "v": Marshalls.raw_to_base64(v)}
		TYPE_INT_ARRAY:
			return {"_t": "pi32", "v": Array(v)}
		TYPE_REAL_ARRAY:
			var f = []
			for x in v:
				f.append(_num(x))
			return {"_t": "pf32", "v": f}
		TYPE_STRING_ARRAY:
			return {"_t": "pstr", "v": Array(v)}
		TYPE_VECTOR2_ARRAY:
			var p2 = []
			for x in v:
				p2.append([x.x, x.y])
			return {"_t": "pv2", "v": p2}
		TYPE_VECTOR3_ARRAY:
			var p3 = []
			for x in v:
				p3.append(_a3(x))
			return {"_t": "pv3", "v": p3}
		TYPE_COLOR_ARRAY:
			var pc = []
			for x in v:
				pc.append([x.r, x.g, x.b, x.a])
			return {"_t": "pcol", "v": pc}
		TYPE_OBJECT:
			if v is Raw:
				return v.json
	return null
