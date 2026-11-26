extends RefCounted
## Exports a map's static collision (physics layer 1) and baked navigation mesh
## for the Godot 3 client (`clients/car/world/level_physics.gd`).
##
## Collision keeps the game's own primitives where it has them (StaticBody3D
## box/cylinder/sphere/capsule/convex shapes, and CSGBox3D/CSGCylinder3D roots
## with use_collision and no CSG children). Everything else (CSG trees,
## concave shapes) is merged into one world-space triangle soup. Transforms are
## written orthonormal with the scale baked into the shape sizes, because Godot
## 3's Bullet backend handles scaled shapes poorly.
##
## Output: `maps/<id>_physics.json`
##   boxes      flat floats, 15 per box:  basis x,y,z columns (9), origin (3), size (3)
##   cylinders  flat floats, 14 per cyl:  basis (9), origin (3), radius, height
##   spheres    flat floats, 4 per sphere: origin (3), radius
##   capsules   flat floats, 14 per cap:  basis (9), origin (3), radius, total height (axis = basis y)
##   convex     array of flat float arrays (world-space points, 3 per point)
##   trimesh    flat floats, 9 per triangle (world space)
##   nav        {vertices: flat floats, polygons: [[i,...],...], cell_size, cell_height,
##               agent_radius, agent_height, agent_max_climb, agent_max_slope,
##               floor_offset (median height of nav vertices above the floor)}

const WORLD_LAYER := 1
const SHELTER_LAYER := 1 << 3
const ROUND := 0.0001

var stats := {}


func export_physics(level: Node3D, map_id: String, out_dir: String, verify_dir := "") -> Dictionary:
	var t0 := Time.get_ticks_usec()
	stats = {"boxes": 0, "cylinders": 0, "spheres": 0, "capsules": 0, "convex": 0,
		"trimesh_triangles": 0, "csg_primitive": 0, "csg_baked": 0, "concave_shapes": 0, "skipped": []}
	var data := {
		"version": 1,
		"map": map_id,
		"layer": WORLD_LAYER,
		"boxes": [], "cylinders": [], "spheres": [], "capsules": [],
		"convex": [], "trimesh": [],
	}
	_collect_bodies(level, data)
	_collect_csg(level, data)
	data["nav"] = _collect_nav(level)
	data["stats"] = stats.duplicate()
	stats["nav_vertices"] = data.nav.vertices.size() / 3
	stats["nav_polygons"] = data.nav.polygons.size()
	data["stats"] = stats.duplicate()

	var rel := "maps/%s_physics.json" % map_id
	var path := out_dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "", false))
	f.close()
	var bytes := FileAccess.get_file_as_bytes(path).size()
	print("  physics %s: %d boxes, %d cyl, %d sph, %d cap, %d convex, %d tris, nav %d verts / %d polys, %.1f KB (%.0f ms)" % [
		map_id, stats.boxes, stats.cylinders, stats.spheres, stats.capsules, stats.convex,
		stats.trimesh_triangles, stats.nav_vertices, stats.nav_polygons, bytes / 1024.0,
		(Time.get_ticks_usec() - t0) / 1000.0])
	if not stats.skipped.is_empty():
		print("  physics skipped: ", stats.skipped)
	if not verify_dir.is_empty():
		await _write_verify(level, map_id, data, verify_dir)
	var summary := stats.duplicate()
	summary.erase("skipped")
	summary["file"] = rel
	summary["bytes"] = bytes
	return summary


# ------------------------------------------------------------------ bodies

func _collect_bodies(level: Node3D, data: Dictionary) -> void:
	for node in level.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if body is Area3D or not (body.collision_layer & WORLD_LAYER):
			continue
		if not body.is_inside_tree() or _hidden_disabled(body):
			continue
		for child in body.get_children():
			if child is CollisionShape3D:
				var cs := child as CollisionShape3D
				if cs.disabled or cs.shape == null:
					continue
				_add_shape(cs.shape, cs.global_transform, data, str(body.get_path()))
			elif child is CollisionPolygon3D:
				var cp := child as CollisionPolygon3D
				if cp.disabled:
					continue
				_add_polygon(cp, data)


func _hidden_disabled(body: CollisionObject3D) -> bool:
	return body.process_mode == Node.PROCESS_MODE_DISABLED and body.disable_mode == CollisionObject3D.DISABLE_MODE_REMOVE


func _add_shape(shape: Shape3D, xf: Transform3D, data: Dictionary, src: String) -> void:
	var sc := xf.basis.get_scale()
	var basis := xf.basis.orthonormalized()
	var uniform := absf(sc.x - sc.y) < 0.001 and absf(sc.y - sc.z) < 0.001
	if shape is BoxShape3D:
		_push_xf(data.boxes, basis, xf.origin)
		_push_v(data.boxes, (shape as BoxShape3D).size * sc)
		stats.boxes += 1
	elif shape is CylinderShape3D and absf(sc.x - sc.z) < 0.001:
		var cy := shape as CylinderShape3D
		_push_xf(data.cylinders, basis, xf.origin)
		data.cylinders.append_array([_r(cy.radius * sc.x), _r(cy.height * sc.y)])
		stats.cylinders += 1
	elif shape is SphereShape3D and uniform:
		_push_v(data.spheres, xf.origin)
		data.spheres.append(_r((shape as SphereShape3D).radius * sc.x))
		stats.spheres += 1
	elif shape is CapsuleShape3D and absf(sc.x - sc.z) < 0.001:
		var cap := shape as CapsuleShape3D
		_push_xf(data.capsules, basis, xf.origin)
		data.capsules.append_array([_r(cap.radius * sc.x), _r(cap.height * sc.y)])
		stats.capsules += 1
	elif shape is ConvexPolygonShape3D:
		var pts := []
		for p in (shape as ConvexPolygonShape3D).points:
			_push_v(pts, xf * p)
		data.convex.append(pts)
		stats.convex += 1
	elif shape is ConcavePolygonShape3D:
		var faces := (shape as ConcavePolygonShape3D).get_faces()
		for p in faces:
			_push_v(data.trimesh, xf * p)
		stats.trimesh_triangles += faces.size() / 3
		stats.concave_shapes += 1
	else:
		# Non-uniformly scaled cylinders/spheres/capsules and anything exotic:
		# fall back to the shape's debug mesh as triangles.
		var mesh := shape.get_debug_mesh()
		var added := _add_mesh_faces(mesh, xf, data)
		if added == 0:
			stats.skipped.append("%s %s" % [src, shape.get_class()])


func _add_polygon(cp: CollisionPolygon3D, data: Dictionary) -> void:
	# Extruded 2D polygon (local XY, depth along Z) -> convex hull points.
	var pts := []
	var half := cp.depth * 0.5
	for v in cp.polygon:
		_push_v(pts, cp.global_transform * Vector3(v.x, v.y, -half))
		_push_v(pts, cp.global_transform * Vector3(v.x, v.y, half))
	data.convex.append(pts)
	stats.convex += 1


# ------------------------------------------------------------------ CSG

func _collect_csg(level: Node3D, data: Dictionary) -> void:
	for node in level.find_children("*", "CSGShape3D", true, false):
		var csg := node as CSGShape3D
		if csg.get_parent() is CSGShape3D:
			continue  # only roots own collision
		if not csg.use_collision or not (csg.collision_layer & WORLD_LAYER) or not csg.is_inside_tree():
			continue
		if not _has_csg_children(csg) and _csg_primitive(csg, data):
			stats.csg_primitive += 1
			continue
		var meshes := csg.get_meshes()
		if meshes.size() < 2 or meshes[1] == null:
			stats.skipped.append("%s empty CSG" % csg.get_path())
			continue
		_add_mesh_faces(meshes[1], csg.global_transform * (meshes[0] as Transform3D), data)
		stats.csg_baked += 1


func _has_csg_children(csg: CSGShape3D) -> bool:
	for c in csg.get_children():
		if c is CSGShape3D:
			return true
	return false


func _csg_primitive(csg: CSGShape3D, data: Dictionary) -> bool:
	var xf := csg.global_transform
	var sc := xf.basis.get_scale()
	var basis := xf.basis.orthonormalized()
	if csg is CSGBox3D:
		_push_xf(data.boxes, basis, xf.origin)
		_push_v(data.boxes, (csg as CSGBox3D).size * sc)
		stats.boxes += 1
		return true
	if csg is CSGCylinder3D and not (csg as CSGCylinder3D).cone and absf(sc.x - sc.z) < 0.001:
		var cy := csg as CSGCylinder3D
		_push_xf(data.cylinders, basis, xf.origin)
		data.cylinders.append_array([_r(cy.radius * sc.x), _r(cy.height * sc.y)])
		stats.cylinders += 1
		return true
	return false


func _add_mesh_faces(mesh: Mesh, xf: Transform3D, data: Dictionary) -> int:
	if mesh == null:
		return 0
	var faces := mesh.get_faces()
	for p in faces:
		_push_v(data.trimesh, xf * p)
	stats.trimesh_triangles += faces.size() / 3
	return faces.size() / 3


# ------------------------------------------------------------------ navigation

func _collect_nav(level: Node3D) -> Dictionary:
	var verts := []
	var polys := []
	var nav := {"vertices": verts, "polygons": polys}
	var offsets := []
	var space := level.get_world_3d().direct_space_state
	for node in level.find_children("*", "NavigationRegion3D", true, false):
		var region := node as NavigationRegion3D
		var nm := region.navigation_mesh
		if nm == null or not region.enabled:
			continue
		var base := verts.size() / 3
		var xf := region.global_transform
		var i := 0
		for v in nm.get_vertices():
			var w := xf * v
			_push_v(verts, w)
			if i % 7 == 0 and space:
				var q := PhysicsRayQueryParameters3D.create(w + Vector3.UP * 0.05, w + Vector3.DOWN * 2.0, WORLD_LAYER)
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					offsets.append(w.y - (hit.position as Vector3).y)
			i += 1
		for p in nm.get_polygon_count():
			var poly := []
			for idx in nm.get_polygon(p):
				poly.append(base + idx)
			polys.append(poly)
		nav["cell_size"] = nm.cell_size
		nav["cell_height"] = nm.cell_height
		nav["agent_radius"] = nm.agent_radius
		nav["agent_height"] = nm.agent_height
		nav["agent_max_climb"] = nm.agent_max_climb
		nav["agent_max_slope"] = nm.agent_max_slope
	offsets.sort()
	nav["floor_offset"] = _r(offsets[offsets.size() / 2]) if not offsets.is_empty() else 0.0
	return nav


# ------------------------------------------------------------------ verification fixture
## Native-game reference answers for the Godot 3 headless check
## (tools/physics_check.gd): standable sample points with the native roof-ray /
## shelter-volume result, and native nav path success between spawns.

func _write_verify(level: Node3D, map_id: String, data: Dictionary, verify_dir: String) -> void:
	var space := level.get_world_3d().direct_space_state
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in range(0, data.nav.vertices.size(), 3):
		var v := Vector3(data.nav.vertices[i], data.nav.vertices[i + 1], data.nav.vertices[i + 2])
		lo = lo.min(v)
		hi = hi.max(v)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var shape_q := PhysicsShapeQueryParameters3D.new()
	shape_q.shape = capsule
	shape_q.collision_mask = WORLD_LAYER
	var area_q := PhysicsPointQueryParameters3D.new()
	area_q.collide_with_areas = true
	area_q.collide_with_bodies = false
	area_q.collision_mask = SHELTER_LAYER
	var samples := []
	var step := 3.0
	var x := lo.x
	while x <= hi.x:
		var z := lo.z
		while z <= hi.z:
			var top := hi.y + 30.0
			var guard := 0
			while guard < 6:
				guard += 1
				var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, lo.y - 3.0, z), WORLD_LAYER)
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					break
				var p: Vector3 = hit.position
				top = p.y - 0.05
				if (hit.normal as Vector3).y < 0.7:
					continue
				shape_q.transform = Transform3D(Basis(), p + Vector3.UP * 0.95)
				if not space.intersect_shape(shape_q, 1).is_empty():
					continue
				var rq := PhysicsRayQueryParameters3D.create(p + Vector3.UP, p + Vector3.UP * 41.0, WORLD_LAYER)
				var roof := not space.intersect_ray(rq).is_empty()
				area_q.position = p + Vector3.UP * 1.65
				var vol := not space.intersect_point(area_q, 1).is_empty()
				samples.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001), roof, vol])
			z += step
		x += step
	# Native paths: every enemy/drain spawn to every player spawn. A fresh
	# headless nav map can report its first iteration before the region syncs.
	var nav_map := level.get_world_3d().navigation_map
	for _i in 60:
		if NavigationServer3D.map_get_iteration_id(nav_map) > 1 and NavigationServer3D.map_get_closest_point(nav_map, lo) != Vector3.ZERO:
			break
		await level.get_tree().physics_frame
	var paths := []
	var froms := []
	var tos := []
	for n in level.find_children("*", "Node3D", true, false):
		if n.is_in_group("enemy_spawn") or n.is_in_group("drain_spawn"):
			froms.append([str(n.name), (n as Node3D).global_position])
		if n.is_in_group("player_spawn"):
			tos.append([str(n.name), (n as Node3D).global_position])
	for a in froms:
		for b in tos:
			var path := NavigationServer3D.map_get_path(nav_map, a[1], b[1], true)
			var ok := not path.is_empty() and Vector2(path[-1].x - b[1].x, path[-1].z - b[1].z).length() < 1.5
			var length := 0.0
			for k in range(1, path.size()):
				length += path[k].distance_to(path[k - 1])
			paths.append({"from": a[0], "to": b[0], "a": _v(a[1]), "b": _v(b[1]), "ok": ok, "len": snappedf(length, 0.01), "points": path.size()})
	var out := {"map": map_id, "step": step, "samples": samples, "paths": paths,
		"player_spawns": tos.map(func(t): return _v(t[1]))}
	DirAccess.make_dir_recursive_absolute(verify_dir)
	var f := FileAccess.open(verify_dir.path_join("%s_physics_verify.json" % map_id), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	var roofed := 0
	var vols := 0
	for s in samples:
		roofed += int(s[3])
		vols += int(s[4])
	var path_ok := paths.filter(func(p): return p.ok).size()
	print("  verify %s: %d samples (%d roof, %d volume), native paths ok %d/%d" % [map_id, samples.size(), roofed, vols, path_ok, paths.size()])


# ------------------------------------------------------------------ helpers

func _push_xf(arr: Array, b: Basis, o: Vector3) -> void:
	_push_v(arr, b.x)
	_push_v(arr, b.y)
	_push_v(arr, b.z)
	_push_v(arr, o)


func _push_v(arr: Array, v: Vector3) -> void:
	arr.append(_r(v.x))
	arr.append(_r(v.y))
	arr.append(_r(v.z))


static func _r(f: float) -> float:
	return snappedf(f, ROUND)


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
