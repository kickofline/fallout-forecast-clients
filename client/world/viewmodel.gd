extends Spatial
## First-person weapon (assets/weapons/view/<id>.glb) with the original's
## placement, ADS, walk bob, kick/recoil and reload part motion
## (weapon_holder.gd / item_pose.gd numbers from assets/README.md).

var item = ""
var meta = {}
var model: Spatial
var aim = 0.0
var kick = 0.0
var recoil = 0.0
var reloading = false
var speed = 0.0
var _bob = 0.0
var _part: Spatial
var _part_rest = Transform()
var _reload_t = 0.0
var _muzzle: Spatial
var _swap = 0.0
var _view_basis = Basis()
var _hip_pos = Vector3(0.17, -0.16, -0.32)
var _ads_pos = Vector3(0, -0.12, -0.4)
var _view_rot = Vector3.ZERO


func set_item(id) -> void:
	var s = "" if id == null else str(id)
	if s == item:
		return
	item = s
	if model:
		model.queue_free()
		model = null
	_part = null
	_muzzle = null
	meta = Assets.weapon(s) if not s.empty() else {}
	if s.empty():
		return
	var scene = Assets.weapon_view(s)
	if scene:
		var part = str(Assets.weapon(s).get("animated_part", ""))
		model = RetroMat.instance_merged(scene, ["Muzzle", "Sight", "LeftHand", "RightHand", part])
	else:
		model = _placeholder()
	add_child(model)
	RetroMat.prepare(model)
	_disable_shadows(model)
	var vp = meta.get("view_position", [0.17, -0.16, -0.32])
	_hip_pos = Vector3(vp[0], vp[1], vp[2])
	var vr = meta.get("view_rotation_degrees", [0, 0, 0])
	_view_rot = Vector3(vr[0], vr[1], vr[2])
	var sc = float(meta.get("view_scale", 1.0))
	_view_basis = Basis(Vector3(deg2rad(_view_rot.x), deg2rad(_view_rot.y), deg2rad(_view_rot.z))).scaled(Vector3.ONE * sc)
	var sight = meta.get("sight")
	if sight is Array:
		_ads_pos = Vector3(0, 0, -float(meta.get("ads_eye_relief", 0.4))) - _view_basis.xform(Vector3(sight[0], sight[1], sight[2]))
	else:
		_ads_pos = Vector3(0, -0.12, _hip_pos.z - 0.08)
	var part_name = str(meta.get("animated_part", ""))
	if not part_name.empty():
		_part = model.find_node(part_name, true, false) as Spatial
		if _part:
			_part_rest = _part.transform
	_muzzle = model.find_node("Muzzle", true, false) as Spatial
	_swap = 1.0


func _disable_shadows(n: Node) -> void:
	if n is GeometryInstance:
		n.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_disable_shadows(c)


func _placeholder() -> Spatial:
	var root = Spatial.new()
	var m = SpatialMaterial.new()
	m.albedo_color = Color("#3b3f46")
	var body = MeshInstance.new()
	var c = CubeMesh.new()
	c.size = Vector3(0.07, 0.09, 0.5)
	body.mesh = c
	body.material_override = m
	body.translation = Vector3(0, 0, -0.2)
	root.add_child(body)
	var muzzle = Spatial.new()
	muzzle.name = "Muzzle"
	muzzle.translation = Vector3(0, 0.01, -0.47)
	root.add_child(muzzle)
	return root


func muzzle_position() -> Vector3:
	if _muzzle:
		return _muzzle.global_transform.origin
	var mz = meta.get("muzzle")
	if mz is Array and model:
		return model.global_transform.xform(Vector3(mz[0], mz[1], mz[2]))
	return global_transform.origin + global_transform.basis.xform(Vector3(0.15, -0.1, -0.7))


func tracer_color() -> Color:
	var c = meta.get("tracer_color")
	if c is String:
		return Color(c)
	return Color(1.0, 0.85, 0.5)


func fire() -> void:
	kick = 1.0
	recoil = min(recoil + 0.6, 1.4)


func _process(delta: float) -> void:
	if model == null:
		return
	kick = max(0.0, kick - delta * 6.0)
	recoil = max(0.0, recoil - delta * 2.8)
	_swap = max(0.0, _swap - delta * 3.0)
	_bob += delta * speed * 1.6
	var bob = Vector3(sin(_bob) * 0.012, abs(cos(_bob)) * 0.014, 0.0) * min(speed, 6.0) / 6.0 * (1.0 - aim * 0.85)
	var pos = _hip_pos.linear_interpolate(_ads_pos, aim) + bob + Vector3(0, -_swap * 0.25, 0.08 * kick)
	var rot = _view_rot + Vector3(6.0 * kick + 8.0 * recoil, 0, 0)
	if reloading:
		_reload_t += delta
		rot.x -= 18.0 * min(1.0, _reload_t * 5.0)
		pos.y -= 0.03
	else:
		_reload_t = max(0.0, _reload_t - delta * 3.0)
	var sc = float(meta.get("view_scale", 1.0))
	model.transform = Transform(Basis(Vector3(deg2rad(rot.x), deg2rad(rot.y), deg2rad(rot.z))).scaled(Vector3.ONE * sc), pos)
	if _part:
		var k = (0.5 - 0.5 * cos(_reload_t * 8.0)) if reloading else 0.0
		var t = _part_rest
		match _part.name:
			"Pump":
				t.origin.z += 0.055 * (k if reloading else kick)
			"Magazine":
				t.origin.y -= 0.095 * k
			"Cylinder":
				t.origin.x -= 0.048 * k
			"Bolt":
				t.origin.z += 0.045 * (k if reloading else kick)
			"Barrel":
				t.basis = t.basis.rotated(Vector3.RIGHT, -0.72 * k)
			"Lid":
				t.basis = t.basis.rotated(Vector3.RIGHT, -1.4 * k)
		_part.transform = t
		if _part.name == "Fan":
			_part.rotate_x(delta * 20.0)
		elif _part.name == "Dish":
			_part.rotate_y(delta * 3.0)
