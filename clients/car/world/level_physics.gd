extends Reference
## Level collision + navigation for the Full tier and solo play.
##
## Contract:
##   var lp = preload("res://world/level_physics.gd").new()
##   var info = lp.build(level_root, map_id)   # call once after the level is instanced
##   info.navigation  -> Navigation (Godot 3) node or null; parented under level_root
##                       and named "LevelNavigation" (solo code may also find it
##                       with level_root.get_node_or_null("LevelNavigation"))
##   info.shelters    -> Array of Area (layer 4) built from the map sidecar `shelters`
##   info.source      -> "exported" (assets/maps/<id>_physics.json) | "trimesh_fallback"
##   info.nav_floor_offset -> metres the navmesh sits above the floor (path points
##                       are that high; subtract it to get feet height)
##   info.stats       -> {boxes, cylinders, spheres, capsules, convex, triangles,
##                        shelters, nav_polygons, load_ms, build_ms}
##
## Collision layers (match the native game, client-responsibilities.md §3):
##   bit 0 (layer 1) world geometry: floors, walls, roofs, props. Player KCC,
##                   roof rays and enemy movement collide with this.
##   bit 3 (layer 4) shelter areas (Area nodes from the map sidecar `shelters`).
## Enemies/players are NOT on layer 1.
##
## The exported file keeps the game's own primitive shapes (boxes, cylinders,
## convex hulls); only CSG trees are triangles. Shapes are grouped into
## StaticBodies per CELL x CELL metre grid cell so the broadphase can cull.
##
## Navigation: Navigation.get_simple_path(from, to) in world coordinates.

const WORLD_LAYER = 1
const SHELTER_LAYER = 1 << 3
const CELL = 32.0

var _shape_cache = {}


func build(level_root: Spatial, map_id: String) -> Dictionary:
	var t0 = OS.get_ticks_usec()
	var data = _read_json(_physics_path(map_id))
	var t_load = OS.get_ticks_usec()
	var info = {"navigation": null, "shelters": [], "source": "trimesh_fallback",
		"nav_floor_offset": 0.0, "stats": {}}
	var stats = {}
	if data.empty():
		var n = 0
		for mi in _meshes(level_root):
			mi.create_trimesh_collision()
			n += 1
		stats["fallback_meshes"] = n
	else:
		stats = _build_collision(level_root, data)
		info.source = "exported"
		var nav = data.get("nav", {})
		if nav is Dictionary and nav.get("polygons", []).size() > 0:
			info.navigation = _build_nav(level_root, nav)
			info.nav_floor_offset = float(nav.get("floor_offset", 0.0))
			stats["nav_polygons"] = nav.polygons.size()
	info.shelters = _build_shelters(level_root, map_id)
	stats["shelters"] = info.shelters.size()
	stats["load_ms"] = (t_load - t0) / 1000.0
	stats["build_ms"] = (OS.get_ticks_usec() - t_load) / 1000.0
	info.stats = stats
	print("PHYSICS %s source=%s %s" % [map_id, info.source, _fmt(stats)])
	return info


# ------------------------------------------------------------------ collision

func _build_collision(level_root: Spatial, data: Dictionary) -> Dictionary:
	var root = Spatial.new()
	root.name = "LevelCollision"
	level_root.add_child(root)
	var cells = {}
	var st = {"boxes": 0, "cylinders": 0, "spheres": 0, "capsules": 0, "convex": 0, "triangles": 0}
	var a = data.get("boxes", [])
	for i in range(0, a.size() - 14, 15):
		var xf = _xf(a, i)
		var s = Vector3(a[i + 12], a[i + 13], a[i + 14])
		_add(root, cells, xf, _shape("b%.3f,%.3f,%.3f" % [s.x, s.y, s.z], "box", s))
		st.boxes += 1
	a = data.get("cylinders", [])
	for i in range(0, a.size() - 13, 14):
		var xf = _xf(a, i)
		var rh = Vector2(a[i + 12], a[i + 13])
		_add(root, cells, xf, _shape("c%.3f,%.3f" % [rh.x, rh.y], "cylinder", rh))
		st.cylinders += 1
	a = data.get("spheres", [])
	for i in range(0, a.size() - 3, 4):
		var xf = Transform(Basis(), Vector3(a[i], a[i + 1], a[i + 2]))
		_add(root, cells, xf, _shape("s%.3f" % a[i + 3], "sphere", a[i + 3]))
		st.spheres += 1
	a = data.get("capsules", [])
	for i in range(0, a.size() - 13, 14):
		# Godot 3 capsules lie along local Z and `height` excludes the caps.
		var xf = _xf(a, i) * Transform(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		var rh = Vector2(a[i + 12], max(0.0, a[i + 13] - 2.0 * a[i + 12]))
		_add(root, cells, xf, _shape("p%.3f,%.3f" % [rh.x, rh.y], "capsule", rh))
		st.capsules += 1
	for pts in data.get("convex", []):
		var shape = ConvexPolygonShape.new()
		shape.points = _v3s(pts)
		var centre = Vector3.ZERO
		for p in shape.points:
			centre += p
		centre /= max(1, shape.points.size())
		_add(root, cells, Transform(Basis(), Vector3.ZERO), shape, centre)
		st.convex += 1
	var tri = data.get("trimesh", [])
	if tri.size() >= 9:
		var shape = ConcavePolygonShape.new()
		shape.set_faces(_v3s(tri))
		var body = _body(root, "Trimesh")
		var o = body.create_shape_owner(body)
		body.shape_owner_add_shape(o, shape)
		st.triangles = tri.size() / 9
	st["bodies"] = root.get_child_count()
	return st


func _add(root: Spatial, cells: Dictionary, xf: Transform, shape: Shape, at = null) -> void:
	var p = xf.origin if at == null else at
	var key = Vector2(floor(p.x / CELL), floor(p.z / CELL))
	var body = cells.get(key)
	if body == null:
		body = _body(root, "Cell_%d_%d" % [key.x, key.y])
		cells[key] = body
	var o = body.create_shape_owner(body)
	body.shape_owner_add_shape(o, shape)
	body.shape_owner_set_transform(o, xf)


func _body(root: Spatial, name: String) -> StaticBody:
	var body = StaticBody.new()
	body.name = name
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	root.add_child(body)
	return body


func _shape(key: String, kind: String, v):
	if _shape_cache.has(key):
		return _shape_cache[key]
	var s
	match kind:
		"box":
			s = BoxShape.new()
			s.extents = v * 0.5
		"cylinder":
			s = CylinderShape.new()
			s.radius = v.x
			s.height = v.y
		"sphere":
			s = SphereShape.new()
			s.radius = v
		"capsule":
			s = CapsuleShape.new()
			s.radius = v.x
			s.height = v.y
	_shape_cache[key] = s
	return s


static func _xf(a: Array, i: int) -> Transform:
	return Transform(
		Vector3(a[i], a[i + 1], a[i + 2]),
		Vector3(a[i + 3], a[i + 4], a[i + 5]),
		Vector3(a[i + 6], a[i + 7], a[i + 8]),
		Vector3(a[i + 9], a[i + 10], a[i + 11]))


static func _v3s(a: Array) -> PoolVector3Array:
	var out = PoolVector3Array()
	out.resize(a.size() / 3)
	for i in out.size():
		out[i] = Vector3(a[i * 3], a[i * 3 + 1], a[i * 3 + 2])
	return out


# ------------------------------------------------------------------ navigation

func _build_nav(level_root: Spatial, nav: Dictionary) -> Navigation:
	var mesh = NavigationMesh.new()
	mesh.set_vertices(_v3s(nav.get("vertices", [])))
	for poly in nav.polygons:
		mesh.add_polygon(PoolIntArray(poly))
	var cs = float(nav.get("cell_size", 0.25))
	mesh.cell_size = cs
	mesh.cell_height = float(nav.get("cell_height", 0.25))
	mesh.agent_radius = float(nav.get("agent_radius", 0.5))
	mesh.agent_height = float(nav.get("agent_height", 1.5))
	mesh.agent_max_climb = float(nav.get("agent_max_climb", 0.25))
	mesh.agent_max_slope = float(nav.get("agent_max_slope", 45.0))
	var navigation = Navigation.new()
	navigation.name = "LevelNavigation"
	navigation.cell_size = cs
	navigation.cell_height = float(nav.get("cell_height", 0.25))
	level_root.add_child(navigation)
	var inst = NavigationMeshInstance.new()
	inst.name = "NavMesh"
	inst.navmesh = mesh
	navigation.add_child(inst)
	# Paths work this frame instead of after the next physics step.
	NavigationServer.map_force_update(navigation.get_rid())
	return navigation


# ------------------------------------------------------------------ shelters

func _build_shelters(level_root: Spatial, map_id: String) -> Array:
	var recs = _read_json("res://assets/maps/%s.json" % map_id).get("shelters", [])
	var out = []
	if recs.empty():
		return out
	var root = Spatial.new()
	root.name = "LevelShelters"
	level_root.add_child(root)
	for r in recs:
		var shape
		match str(r.get("shape", "")):
			"box":
				shape = BoxShape.new()
				shape.extents = _v(r.get("size", [1, 1, 1])) * 0.5
			"cylinder":
				shape = CylinderShape.new()
				shape.radius = float(r.get("radius", 1.0))
				shape.height = float(r.get("height", 1.0))
			"sphere":
				shape = SphereShape.new()
				shape.radius = float(r.get("radius", 1.0))
			_:
				continue
		var area = Area.new()
		area.name = str(r.get("name", "Shelter")).replace("@", "_").replace("/", "_")
		area.collision_layer = SHELTER_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		var rot = _v(r.get("rot", [0, 0, 0]))
		if r.has("yaw") and not r.has("rot"):
			rot = Vector3(0, float(r.yaw), 0)
		area.transform = Transform(Basis(rot), _v(r.get("pos", [0, 0, 0])))
		area.set_meta("tree_canopy", bool(r.get("is_tree_canopy", false)))
		area.add_to_group("shelter")
		var cs = CollisionShape.new()
		cs.shape = shape
		area.add_child(cs)
		root.add_child(area)
		out.append(area)
	return out


# ------------------------------------------------------------------ helpers

func _physics_path(map_id: String) -> String:
	var assets = Engine.get_main_loop().root.get_node_or_null("Assets") if Engine.get_main_loop() else null
	if assets and assets.has_method("entry"):
		var e = assets.entry("maps", map_id)
		if e.get("physics") is String:
			return assets.path(e.physics)
	return "res://assets/maps/%s_physics.json" % map_id


static func _read_json(p: String) -> Dictionary:
	var f = File.new()
	if not f.file_exists(p) or f.open(p, File.READ) != OK:
		return {}
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	return parsed.result if parsed.error == OK and parsed.result is Dictionary else {}


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


static func _fmt(d: Dictionary) -> String:
	var parts = []
	for k in d:
		parts.append("%s=%s" % [k, str(d[k])])
	return " ".join(parts)


func _meshes(node: Node, out := []) -> Array:
	if node is MeshInstance and node.mesh:
		out.append(node)
	for c in node.get_children():
		_meshes(c, out)
	return out
