extends Spatial
## A replicated character: exported articulated model (or a procedural
## placeholder with the same hierarchy) driven by the procedural animation
## equations from assets/README.md (player_model.gd, infected_model.gd).

# reach, freq, freq_per_speed, arm, leg, bounce, sway, lean
const LOD_ENTER_SQUARED = 30.0 * 30.0
const LOD_EXIT_SQUARED = 27.0 * 27.0

const GAIT = {
	"drip": [1.15, 2.6, 1.7, 0.55, 0.45, 0.050, 0.06, -0.10],
	"gutter": [0.55, 5.0, 2.6, 0.70, 0.55, 0.025, 0.02, -0.25],
	"mister": [0.30, 2.4, 1.4, 0.20, 0.35, 0.060, 0.07, 0.03],
	"cloudburst": [0.30, 2.4, 1.4, 0.20, 0.35, 0.060, 0.07, 0.03],
	"sleet": [0.70, 5.5, 1.7, 0.55, 0.85, 0.050, 0.14, -0.15],
	"hailstone": [0.25, 1.8, 1.7, 0.55, 0.36, 0.070, 0.06, -0.10],
	"undertow": [0.24, 2.2, 1.7, 0.95, 0.45, 0.050, 0.06, -0.17],
	"static": [0.57, 5.0, 1.7, 0.70, 0.45, 0.050, 0.12, -0.10],
	"smog": [0.25, 1.8, 1.7, 0.55, 0.45, 0.080, 0.13, -0.10],
	"thunderhead": [0.35, 3.3, 1.7, 0.55, 0.45, 0.110, 0.12, -0.10],
}
const PLACEHOLDER_COLORS = {
	"drip": Color("#6fd65a"), "gutter": Color("#4b5f4a"), "mister": Color("#9a6bd6"),
	"hailstone": Color("#cfe6ff"), "sleet": Color("#9fd8ff"), "smog": Color("#55585f"),
	"static": Color("#ffe066"), "thunderhead": Color("#3d4a8a"), "undertow": Color("#2e8f8a"),
	"cloudburst": Color("#b48cff"), "cumulus": Color("#c8cbd8"), "turned": Color("#8ce64d"),
}

const PIVOTS = ["Rig", "Body", "Head", "Jaw", "ArmL", "ArmR", "ElbowL", "ElbowR", "LegL", "LegR", "KneeL", "KneeR",
	"Hips", "Torso", "ForearmL", "ForearmR", "ShinL", "ShinR", "WeaponMount", "Sparks",
	"MinibossMantle", "MinibossHalo", "MinibossGroundAura", "StormCrownOuter", "StormCrownInner",
	"Sac0", "Sac1", "Sac2", "SacHalo0", "SacHalo1", "SacHalo2", "Core", "CoreRings", "Shell"]

var kind = "enemy"        # enemy | player | turned | boss
var type = ""
var id = 0
var model: Spatial
var parts = {}
var rest = {}
var _rest_rotation = {}
var weapon_mount: Spatial
var held_item = ""
var state = "ok"
var anim = "idle"
var pitch = 0.0
var dying = false
var die_left = 0.0
var spawn_left = 0.0
var hp = 1.0

var _clock = 0.0
var _time = 0.0
var _speed = 0.0
var _last_pos = Vector3.ZERO
var _has_last = false
var _hurt = 0.0
var _hurt_side = 1.0
var _head_kick = 0.0
var _anticipation = 0.0
var _attack = 0.0
var _down = 0.0
var _gait: Array = GAIT["drip"]
var _lod_acc = 0.0
var _rig
var _fall_axis = Vector3.RIGHT
var _fall_dir = Vector3.ZERO
var _linger = 0.0
var _fall_from = Vector3.ZERO
var _model_rest = Transform()
var tarp: MeshInstance            # Full: raised-tarp sheet (world/full_fx.gd make_tarp)


func setup_enemy(enemy_type: String) -> void:
	type = enemy_type
	kind = "boss" if type == "cumulus" else ("turned" if type == "turned" else "enemy")
	_gait = GAIT.get(type, GAIT["gutter"])
	var scene = Assets.enemy_scene(type)
	if scene:
		_use_scene(scene, kind == "enemy" and type != "cloudburst")
	else:
		_use_model(_placeholder(PLACEHOLDER_COLORS.get(type, Color("#6fd65a")), type == "turned" or kind == "boss"))
	if type == "cloudburst" and not scene:
		model.scale = Vector3.ONE * 2.5
	spawn_left = 0.6


func setup_player(model_id: String, suit: Color) -> void:
	kind = "player"
	var scene = Assets.player_scene(model_id)
	if scene:
		_use_scene(scene, false)
	else:
		_use_model(_placeholder(suit, true))


func _use_scene(scene: PackedScene, static_lod: bool) -> void:
	_rig = RetroMat.actor_batch.instance(scene, PIVOTS, static_lod)
	_use_model(_rig.root if _rig else RetroMat.instance_merged(scene, PIVOTS))


func _use_model(m: Spatial) -> void:
	if model:
		model.queue_free()
	model = m
	add_child(model)
	RetroMat.prepare(model)
	parts.clear()
	rest.clear()
	_rest_rotation.clear()
	for n in PIVOTS:
		var node = model.find_node(n, true, false) as Spatial
		if node:
			parts[n] = node
			rest[n] = node.transform
			_rest_rotation[n] = node.transform.basis.get_euler()
	weapon_mount = parts.get("WeaponMount")
	if _rig:
		_rig.set_style(RetroMat.snap if Settings.retro_enabled else 0.0, RetroMat.wetness)
		_rig.update_pose()


## Procedural stand-in with the player/infected hierarchy (boxes).
func _placeholder(color: Color, humanlike: bool) -> Spatial:
	var root = Spatial.new()
	var mat = SpatialMaterial.new()
	mat.albedo_color = color
	var dark = SpatialMaterial.new()
	dark.albedo_color = color.darkened(0.45)
	var eye = SpatialMaterial.new()
	eye.flags_unshaded = true
	eye.albedo_color = Color("#d8ff6a") if not humanlike else Color("#66dfda")
	var hips = _pivot(root, "Hips", Vector3(0, 0.92, 0))
	var torso = _pivot(hips, "Torso", Vector3(0, 0.12, 0))
	_box(torso, Vector3(0, 0.25, 0), Vector3(0.5, 0.55, 0.28), mat)
	var head = _pivot(torso, "Head", Vector3(0, 0.6, 0))
	_box(head, Vector3(0, 0.12, 0), Vector3(0.3, 0.3, 0.3), mat)
	_box(head, Vector3(0, 0.14, -0.16), Vector3(0.22, 0.06, 0.02), eye)
	for side in [-1.0, 1.0]:
		var s = "L" if side < 0 else "R"
		var arm = _pivot(torso, "Arm" + s, Vector3(0.3 * side, 0.46, 0))
		_box(arm, Vector3(0, -0.14, 0), Vector3(0.14, 0.3, 0.14), mat)
		var fore = _pivot(arm, "Forearm" + s, Vector3(0, -0.29, 0))
		_box(fore, Vector3(0, -0.13, 0), Vector3(0.12, 0.28, 0.12), dark)
		var leg = _pivot(hips, "Leg" + s, Vector3(0.12 * side, -0.06, 0))
		_box(leg, Vector3(0, -0.2, 0), Vector3(0.17, 0.4, 0.17), dark)
		var shin = _pivot(leg, "Shin" + s, Vector3(0, -0.4, 0))
		_box(shin, Vector3(0, -0.22, 0), Vector3(0.15, 0.44, 0.15), dark)
	var mount = _pivot(root, "WeaponMount", Vector3(0.3, 0.92, 0))
	mount.name = "WeaponMount"
	return root


func _pivot(parent: Spatial, n: String, at: Vector3) -> Spatial:
	var p = Spatial.new()
	p.name = n
	p.translation = at
	parent.add_child(p)
	return p


func _box(parent: Spatial, at: Vector3, size: Vector3, mat: Material) -> void:
	var mi = MeshInstance.new()
	var cube = CubeMesh.new()
	cube.size = size
	mi.mesh = cube
	mi.material_override = mat
	mi.translation = at
	parent.add_child(mi)


## Third-person weapon on WeaponMount (view glb x1.6, per README).
func set_item(item_id) -> void:
	var id_s = "" if item_id == null else str(item_id)
	if id_s == held_item or weapon_mount == null:
		return
	held_item = id_s
	for c in weapon_mount.get_children():
		c.queue_free()
	if id_s.empty():
		return
	var scene = Assets.weapon_view(id_s)
	if scene:
		var w: Spatial = RetroMat.instance_merged(scene, ["Muzzle", "Sight", "LeftHand", "RightHand"])
		w.scale = Vector3.ONE * 1.6
		w.translation = -Vector3(0.026, -0.045, 0.033)
		weapon_mount.add_child(w)
		RetroMat.prepare(w)


## Pulses from events.
func hurt(head: bool) -> void:
	_hurt = 1.0
	_hurt_side = -1.0 if randf() < 0.5 else 1.0
	if head:
		_head_kick = 1.0


func set_anim(a: String) -> void:
	if a == anim:
		return
	if a == "windup":
		_anticipation = 1.0
	elif anim == "windup" or a == "attack":
		_attack = 1.0
	if a == "stagger":
		hurt(false)
	anim = a


## Death. With a throw vector the body topples along it (enemy_base
## make_corpse: 84 degrees in 0.38 s, slides 0.6 m), lies for `linger` s and
## sinks; without one it is the short Thin fall.
func kill(throw_vec := Vector3.ZERO, linger := 0.0) -> void:
	dying = true
	die_left = 0.9
	_linger = linger
	var d = Vector3(throw_vec.x, 0, throw_vec.z)
	if linger > 0.0:
		if d.length_squared() < 0.01:
			d = global_transform.basis.z
		_fall_dir = d.normalized()
		_fall_axis = Vector3.UP.cross(_fall_dir).normalized()
		_fall_from = translation
		if model:
			_model_rest = model.transform
		die_left = 0.38 + linger + 1.2


func _process(delta: float) -> void:
	var _pt = OS.get_ticks_usec()
	_process_body(delta)
	Settings.prof_add("actors", OS.get_ticks_usec() - _pt)


func _process_body(delta: float) -> void:
	_time += delta
	var pos = global_transform.origin
	if _has_last and delta > 0.0:
		var v = (pos - _last_pos) / delta
		v.y = 0.0
		_speed = lerp(_speed, min(v.length(), 12.0), 1.0 - exp(-10.0 * delta))
	_last_pos = pos
	_has_last = true
	if model == null:
		return
	if spawn_left > 0.0:
		spawn_left = max(0.0, spawn_left - delta)
		model.translation.y = -spawn_left * 2.0
	elif not dying:
		model.translation.y = 0.0
	if dying and _linger > 0.0:
		die_left -= delta
		var t = 0.38 + _linger + 1.2 - die_left
		var k2: float = clamp(t / 0.38, 0.0, 1.0)
		model.transform = Transform(Basis(global_transform.basis.xform_inv(_fall_axis).normalized(), deg2rad(84.0) * k2 * k2), Vector3.ZERO) * _model_rest
		translation = _fall_from + _fall_dir * 0.6 * k2 + Vector3(0, -0.8 * clamp((t - 0.38 - _linger) / 1.2, 0.0, 1.0), 0)
		if die_left <= 0.0:
			queue_free()
		return
	if dying:
		die_left -= delta
		var k: float = clamp(1.0 - die_left / 0.9, 0.0, 1.0)
		model.rotation.x = -k * 1.45
		model.translation.y = -max(0.0, k - 0.6) * 1.5
		if die_left <= -0.2:
			queue_free()
		return
	var cam = get_viewport().get_camera()
	if _rig:
		_rig.set_style(RetroMat.snap if Settings.retro_enabled else 0.0, RetroMat.wetness)
	if cam and spawn_left <= 0.0:
		var dist_squared = pos.distance_squared_to(cam.global_transform.origin)
		if _rig and _rig.still_mesh:
			_rig.set_still(dist_squared > (LOD_EXIT_SQUARED if _rig.still else LOD_ENTER_SQUARED))
			if _rig.still:
				_advance_infected(delta)
				return
		# Off-screen actors and distant bosses/teammates animate at ~10 Hz.
		if dist_squared > LOD_ENTER_SQUARED or cam.is_position_behind(pos):
			_lod_acc += delta
			if _lod_acc < 0.1:
				return
			delta = _lod_acc
		_lod_acc = 0.0
	match kind:
		"player", "turned":
			_animate_player(delta)
		"boss":
			_animate_boss(delta)
		_:
			_animate_infected(delta)
	if _rig:
		_rig.update_pose()


func _rot(n: String, x: float, y = null, z = null) -> void:
	var p: Spatial = parts.get(n)
	if p == null:
		return
	var r: Vector3 = _rest_rotation[n]
	p.rotation = Vector3(x, r.y if y == null else y, r.z if z == null else z)


func _animate_player(delta: float) -> void:
	var turned = kind == "turned" or state == "turned"
	var sprinting = _speed > 6.5
	_clock += delta * (2.0 + _speed * 1.6)
	var stride: float = clamp(_speed / 5.0, 0.0, 1.3)
	_down = move_toward(_down, 1.0 if state == "downed" else 0.0, delta * 3.0)
	for i in 2:
		var s: String = ["L", "R"][i]
		var phase = PI * i
		_rot("Leg" + s, sin(_clock + phase) * 0.7 * stride)
		_rot("Shin" + s, -max(0.0, -sin(_clock + phase)) * 1.1 * stride - 0.05)
	var bob: float = abs(sin(_clock)) * 0.05 * stride
	var breathe = sin(_time * 2.0) * 0.012
	var hips: Spatial = parts.get("Hips")
	if hips:
		hips.translation.y = 0.92 + bob - _down * 0.62
	model.rotation.z = lerp(0.0, 1.35, _down)
	var aim_lift = -pitch * 0.65
	if turned:
		_rot("ArmL", 1.4 + sin(_clock) * 0.15, 0.0, 0.1)
		_rot("ArmR", 1.4 - sin(_clock) * 0.15, 0.0, -0.1)
		_rot("ForearmL", 0.2)
		_rot("ForearmR", 0.3)
		_rot("Torso", 0.35)
		_rot("Head", 0.3, 0.0, 0.35)
		return
	_rot("Torso", -pitch * 0.35 + (0.25 if sprinting else 0.06) + breathe)
	_rot("Head", -pitch * 0.55)
	if sprinting:
		_rot("ArmL", 0.6 + sin(_clock) * 0.25, 0.0, 0.2)
		_rot("ArmR", 0.9 - sin(_clock) * 0.25, 0.0, -0.25)
		_rot("ForearmL", 1.2)
		_rot("ForearmR", 1.1)
	else:
		_rot("ArmL", 1.25 + aim_lift, 0.15, 0.25)
		_rot("ArmR", 1.35 + aim_lift, -0.3, -0.35)
		_rot("ForearmL", 0.55)
		_rot("ForearmR", 0.25)
	if _down > 0.0:
		var crawl = sin(_time * 3.0)
		var arm: Spatial = parts.get("ArmR")
		if arm:
			arm.rotation = arm.rotation.linear_interpolate(Vector3(2.6 + crawl * 0.3, 0, -0.2), _down)
		var leg: Spatial = parts.get("LegL")
		if leg:
			leg.rotation.x = lerp(leg.rotation.x, 0.3 + crawl * 0.2, _down)
	if weapon_mount and parts.has("ForearmR"):
		var fore: Spatial = parts["ForearmR"]
		var t = model.global_transform.affine_inverse() * fore.global_transform
		weapon_mount.transform = Transform(t.basis, t.xform(Vector3(0, -0.29, 0)))


func _advance_infected(delta: float) -> void:
	_clock += delta * (_gait[1] + _speed * _gait[2])
	_hurt = max(0.0, _hurt - delta * 5.0)
	_head_kick = max(0.0, _head_kick - delta * 4.0)
	_anticipation = max(0.0, _anticipation - delta * 2.0)
	if anim == "windup":
		_anticipation = max(_anticipation, 0.8)
	_attack = max(0.0, _attack - delta * 3.0)


func _animate_infected(delta: float) -> void:
	_advance_infected(delta)
	var reach: float = _gait[0]
	var amount: float = clamp(_speed / 3.5, 0.0, 1.2)
	var idx = 0
	for s in ["L", "R"]:
		var phase = 0.0 if s == "L" else PI
		_rot("Arm" + s, reach + sin(_clock + phase) * _gait[3] * amount * 0.4 + _anticipation * 1.1 - _attack * 1.3 - _hurt * 0.7)
		_rot("Elbow" + s, 0.25 + 0.2 * sin(_clock * 0.7 + idx) + _attack * 0.6)
		var lphase = PI if s == "L" else 0.0
		_rot("Leg" + s, sin(_clock + lphase) * _gait[4] * amount)
		_rot("Knee" + s, -max(0.0, -sin(_clock + lphase)) * 0.7 * amount - 0.08)
		idx += 1
	var body: Spatial = parts.get("Body")
	if body:
		var base: Transform = rest["Body"]
		body.translation.y = base.origin.y + abs(sin(_clock)) * _gait[5] * max(amount, 0.2)
		body.rotation = Vector3(_gait[7] + _hurt * 0.35, 0.0, sin(_clock * 0.5) * _gait[6] + _hurt * 0.22 * _hurt_side)
		if type == "thunderhead":
			var charge = _anticipation
			body.scale = Vector3.ONE * (1.0 + charge * (0.53 + 0.035 * sin(12.0 * _clock)))
	_rot("Head", _head_kick * 0.7)
	_rot("Jaw", 0.18 + 0.1 * abs(sin(_clock * 3.1)) + _anticipation * 0.4 + _attack * 0.3)
	var sparks: Spatial = parts.get("Sparks")
	if sparks:
		sparks.visible = randf() < 0.6
	for n in ["MinibossMantle", "MinibossHalo"]:
		if parts.has(n):
			parts[n].rotate_y(2.4 * delta)
	if parts.has("MinibossGroundAura"):
		parts["MinibossGroundAura"].rotate_y(-0.9 * delta)


func _animate_boss(delta: float) -> void:
	var body: Spatial = parts.get("Body")
	if body:
		body.rotate_y(0.15 * delta)
	if parts.has("StormCrownOuter"):
		var c: Spatial = parts["StormCrownOuter"]
		c.rotation = Vector3(c.rotation.x, c.rotation.y - 1.15 * delta, -0.18 + sin(_time * 1.4) * 0.1)
	if parts.has("StormCrownInner"):
		var c2: Spatial = parts["StormCrownInner"]
		c2.rotation = Vector3(-0.26 + cos(_time * 1.7) * 0.1, c2.rotation.y + 1.55 * delta, c2.rotation.z)
	var sacs_left = 3 if hp > 0.5 else (1 if hp > 0.25 else 0)
	var speed = 0.55 + 0.22 * (3 - sacs_left)
	for i in 3:
		var sac: Spatial = parts.get("Sac%d" % i)
		if sac:
			var a = _time * speed + i * TAU / 3.0
			sac.translation = Vector3(cos(a) * 5.0, -1.2, sin(a) * 5.0)
			sac.visible = i < sacs_left
			sac.scale = Vector3.ONE * (1.0 + 0.12 * sin(5.0 * _time + i * 2.1))
	if parts.has("Core"):
		parts["Core"].visible = sacs_left == 0
		parts["Core"].rotation += Vector3(1.1, 2.2, 0) * delta
	if parts.has("Shell"):
		parts["Shell"].visible = sacs_left > 0
