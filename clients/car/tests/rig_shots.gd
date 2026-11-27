extends SceneTree
## Deterministic character portraits for before/after visual comparison:
## every enemy type and player suit, posed by world/actor.gd
## (walk 3/4 front, walk side, wind-up / downed) under a fixed light.
##
## godot --path clients/car -s res://tests/rig_shots.gd -- --shots=DIR [--verify-batched] [--no-retro]
## Not exported (tests/).

const W = 960
const H = 400

var _dir = ""
var _verify_batched = false
var _jobs = []
var _vp: Viewport
var _stage: Spatial
var _cam: Camera
var _wait = 0
var _name = ""


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	for arg in OS.get_cmdline_args():
		var a = str(arg)
		if a.begins_with("--shots="):
			_dir = a.substr(8)
		elif a == "--verify-batched":
			_verify_batched = true
		elif a == "--no-retro":
			root.get_node("Settings").retro_enabled = false
	if _dir.empty() or Directory.new().make_dir_recursive(_dir) != OK:
		printerr("Pass a writable --shots=DIR")
		quit(1)
		return
	var assets = root.get_node("Assets")
	for t in assets.ids("enemies"):
		_jobs.append(["enemy", t])
	for p in assets.ids("players"):
		_jobs.append(["player", p])
	_vp = Viewport.new()
	_vp.size = Vector2(W, H)
	_vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	_vp.msaa = Viewport.MSAA_DISABLED
	root.add_child(_vp)
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1d2430")
	env.ambient_light_color = Color("#7d8aa3")
	env.ambient_light_energy = 0.55
	var we = WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun = DirectionalLight.new()
	sun.light_color = Color("#ffe2c0")
	sun.light_energy = 1.0
	sun.rotation = Vector3(deg2rad(-50), deg2rad(-35), 0)
	_vp.add_child(sun)
	_cam = Camera.new()
	_cam.fov = 40
	_vp.add_child(_cam)
	_cam.current = true
	_next()


func _bounds(scene: PackedScene) -> AABB:
	var inst: Spatial = scene.instance()
	var box = AABB()
	var first = true
	var stack = [[inst, Transform()]]
	while not stack.empty():
		var it = stack.pop_back()
		var n = it[0]
		var xf: Transform = it[1]
		for c in n.get_children():
			if c is Spatial:
				var cx = xf * c.transform
				if c is MeshInstance and c.mesh and c.visible:
					var b = cx.xform(c.mesh.get_aabb())
					box = b if first else box.merge(b)
					first = false
				stack.append([c, cx])
	inst.free()
	return box


func _next() -> void:
	if _stage:
		_stage.queue_free()
		_stage = null
	if _jobs.empty():
		print("RIGSHOTS done")
		quit(0)
		return
	var job = _jobs.pop_front()
	_name = job[1]
	var Actor = load("res://world/actor.gd")
	var assets = root.get_node("Assets")
	var scene = assets.enemy_scene(_name) if job[0] == "enemy" else assets.player_scene(_name)
	var box = _bounds(scene)
	_stage = Spatial.new()
	_vp.add_child(_stage)
	var size = max(box.size.y, max(box.size.x, box.size.z) * 0.8)
	var gap = max(box.size.x, box.size.z) * 1.35 + 0.3
	if _name == "cumulus":
		gap = box.size.x * 1.05
	var center = box.position + box.size * 0.5
	var dist = (size * 0.5 + gap * 0.25) / tan(deg2rad(_cam.fov * 0.5)) * 1.15 + max(box.size.z, box.size.x) * 0.5
	var horiz = (gap * 1.5 + max(box.size.x, box.size.z) * 0.5) / tan(deg2rad(_cam.fov * 0.5)) / (float(W) / H) + max(box.size.z, 0.5)
	dist = max(dist, horiz)
	_cam.transform = Transform(Basis(Vector3.RIGHT, deg2rad(-8)), Vector3(0, center.y + dist * 0.14, dist))
	_cam.far = dist * 4.0 + 50.0
	var yaws = [deg2rad(200), deg2rad(270), deg2rad(160)]
	for i in 3:
		var a = Actor.new()
		_stage.add_child(a)
		a.set_process(false)
		if job[0] == "enemy":
			a.setup_enemy(_name)
		else:
			a.setup_player(_name, Color("#2ec9c9"))
			a.set_item(["pump_shotgun", "nail_driver", "service_revolver"][i])
			a.pitch = 0.15
		if _verify_batched and (a._rig == null or a._rig.mesh.mesh.get_surface_count() > 2):
			printerr("Invalid actor batch ", _name)
			quit(1)
			return
		a.spawn_left = 0.0
		a.translation = Vector3((i - 1) * gap, 0, 0)
		a.rotation.y = yaws[i]
		a._speed = 2.6 if i < 2 else 0.0
		a._clock = 1.1 + i * 0.7
		a._time = 1.3 + i
		a.hp = 1.0 if i < 2 else 0.2
		if i == 2:
			if job[0] == "enemy":
				a.set_anim("windup")
				a._anticipation = 0.8
			else:
				a.state = "downed"
				a._down = 1.0
		seed(7 + i)
		a._process_body(0.11)
	_wait = 4


func _idle(_dt: float) -> bool:
	if _stage == null:
		return false
	_wait -= 1
	if _wait == 0:
		var img = _vp.get_texture().get_data()
		img.flip_y()
		img.save_png(_dir.plus_file(_name + ".png"))
		_next()
	return false
