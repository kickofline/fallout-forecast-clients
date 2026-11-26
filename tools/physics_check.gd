extends SceneTree
## Headless Godot 3 check of world/level_physics.gd against native-game answers.
##
##   godot --path clients/car --no-window -s ../../tools/physics_check.gd -- \
##     --verify=DIR [--maps=pinecrest,harbor,maple_hollow]
##
## DIR holds <map>_physics_verify.json written by the exporter's
## --physics-verify=DIR flag (native roof-ray / shelter-volume results at
## standable sample points, and native nav paths between spawns). Per map it
## reports build time, a native-size capsule settling and walking from every
## player spawn, roof-ray and shelter-volume agreement, and get_simple_path
## success from every enemy/drain spawn to every player spawn.

const LevelPhysics = preload("res://world/level_physics.gd")

var verify_dir = ""
var maps = ["pinecrest", "harbor", "maple_hollow"]
var failures = 0


func _init():
	for a in OS.get_cmdline_args():
		if a.begins_with("--verify="):
			verify_dir = a.substr(9)
		elif a.begins_with("--maps="):
			maps = a.substr(7).split(",", false)
	call_deferred("_run")


func _run():
	for id in maps:
		yield(_check_map(id), "completed")
	print("PHYSCHECK done failures=%d" % failures)
	quit(1 if failures else 0)


func _check_map(id: String):
	yield(self, "idle_frame")
	var level = Spatial.new()
	level.name = "Level_" + id
	root.add_child(level)
	var t0 = OS.get_ticks_usec()
	var info = LevelPhysics.new().build(level, id)
	var build_ms = (OS.get_ticks_usec() - t0) / 1000.0
	if info.source != "exported":
		print("PHYSCHECK %s FAIL source=%s" % [id, info.source])
		failures += 1
	yield(self, "physics_frame")
	yield(self, "physics_frame")
	var fix = _read_json(verify_dir.plus_file("%s_physics_verify.json" % id))
	var space = level.get_world().direct_space_state

	# --- walk from every player spawn
	var walk_ok = 0
	var spawns = fix.get("player_spawns", [])
	for s in spawns:
		var r = yield(_walk(level, Vector3(s[0], s[1], s[2])), "completed")
		if r.floor and r.moved >= 2:
			walk_ok += 1
		else:
			print("  walk FAIL at %s: %s" % [str(s), str(r)])
	# --- roof rays and shelter volumes
	var roof_match = 0
	var vol_match = 0
	var roof_miss = []
	var vol_miss = []
	var samples = fix.get("samples", [])
	for smp in samples:
		var p = Vector3(smp[0], smp[1], smp[2])
		var roof = not space.intersect_ray(p + Vector3.UP, p + Vector3.UP * 41.0, [], 1).empty()
		var vol = not space.intersect_point(p + Vector3.UP * 1.65, 1, [], 1 << 3, false, true).empty()
		if roof == bool(smp[3]):
			roof_match += 1
		elif roof_miss.size() < 6:
			roof_miss.append("%s native=%s" % [str(p), str(smp[3])])
		if vol == bool(smp[4]):
			vol_match += 1
		elif vol_miss.size() < 6:
			vol_miss.append("%s native=%s" % [str(p), str(smp[4])])
	# --- navigation
	var nav = info.navigation
	var nav_ok = 0
	var nav_native_ok = 0
	var nav_t = OS.get_ticks_usec()
	var paths = fix.get("paths", [])
	var len_ratio = []
	for pth in paths:
		if pth.ok:
			nav_native_ok += 1
		if nav == null:
			continue
		var a = Vector3(pth.a[0], pth.a[1], pth.a[2])
		var b = Vector3(pth.b[0], pth.b[1], pth.b[2])
		var pts = nav.get_simple_path(a, b, true)
		var ok = pts.size() > 0 and Vector2(pts[-1].x - b.x, pts[-1].z - b.z).length() < 1.5
		if ok:
			nav_ok += 1
			var l = 0.0
			for k in range(1, pts.size()):
				l += pts[k].distance_to(pts[k - 1])
			if pth.len > 0.0:
				len_ratio.append(l / pth.len)
		elif pth.ok:
			print("  nav FAIL %s -> %s (%d pts)" % [pth.from, pth.to, pts.size()])
	var nav_ms = (OS.get_ticks_usec() - nav_t) / 1000.0
	len_ratio.sort()
	var med = len_ratio[len_ratio.size() / 2] if not len_ratio.empty() else 0.0
	print("PHYSCHECK %s build=%.1fms (load %.1f, build %.1f) walk=%d/%d roof=%d/%d volume=%d/%d nav=%d/%d (native %d) path_len_ratio_median=%.3f nav_query_ms=%.1f" % [
		id, build_ms, info.stats.get("load_ms", 0), info.stats.get("build_ms", 0),
		walk_ok, spawns.size(), roof_match, samples.size(), vol_match, samples.size(),
		nav_ok, paths.size(), nav_native_ok, med, nav_ms])
	if not roof_miss.empty():
		print("  roof mismatches: ", roof_miss)
	if not vol_miss.empty():
		print("  volume mismatches: ", vol_miss)
	if walk_ok < spawns.size() or nav_ok < nav_native_ok:
		failures += 1
	if samples.size() > 0 and (roof_match < samples.size() * 0.99 or vol_match < samples.size() * 0.99):
		failures += 1
	level.queue_free()
	yield(self, "idle_frame")


## Settle a native-size capsule (r 0.4, h 1.8) at `at`, then walk 1.2 s at
## 5 m/s in four directions; `moved` counts directions that covered >= 3 m.
func _walk(level: Spatial, at: Vector3):
	var kb = KinematicBody.new()
	kb.collision_layer = 2
	kb.collision_mask = 1
	var cs = CollisionShape.new()
	var cap = CapsuleShape.new()
	cap.radius = 0.4
	cap.height = 1.0
	cs.shape = cap
	cs.transform = Transform(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.9, 0))
	kb.add_child(cs)
	level.add_child(kb)
	kb.global_transform.origin = at + Vector3(0, 0.05, 0)
	var vel = Vector3.ZERO
	for _i in 30:
		yield(self, "physics_frame")
		vel.y -= 9.8 / 60.0
		vel = kb.move_and_slide_with_snap(vel, Vector3.DOWN * 0.3, Vector3.UP, true)
	var floor_ok = kb.is_on_floor()
	var settled_y = kb.global_transform.origin.y
	var moved = 0
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var start = kb.global_transform.origin
		for _i in 72:
			yield(self, "physics_frame")
			vel = Vector3(dir.x * 5.0, vel.y - 9.8 / 60.0, dir.z * 5.0)
			vel = kb.move_and_slide_with_snap(vel, Vector3.DOWN * 0.3, Vector3.UP, true)
		var d = kb.global_transform.origin - start
		if Vector2(d.x, d.z).length() >= 3.0:
			moved += 1
		kb.global_transform.origin = start
	kb.queue_free()
	return {"floor": floor_ok, "moved": moved, "settled_dy": stepify(settled_y - at.y, 0.01)}


static func _read_json(p: String) -> Dictionary:
	var f = File.new()
	if f.open(p, File.READ) != OK:
		print("PHYSCHECK cannot open ", p)
		return {}
	var r = JSON.parse(f.get_as_text())
	f.close()
	return r.result if r.error == OK and r.result is Dictionary else {}
