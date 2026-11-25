extends Spatial
## Local weather visuals (port of weather/weather_fx.gd for GLES2):
## procedural sky + ambient + sun from environments.json, per-phase linear
## fog (fog_depth_*_gles2), fallout-green rain following the camera,
## lightning flash + bolt, acid puddles, storm wetness on PS1 materials.
## Fog stays enabled; only begin/end/colour change (no shader recompiles).

var env = Environment.new()
var sun = DirectionalLight.new()
var sky = ProceduralSky.new()
var camera: Camera
var phase = "calm"
var intensity = 0.0
var flash = 0.0

var _cfg = {}
var _phases = {}
var _flash_cfg = {"fade_rate": 2.6, "sky_boost": 0.85, "ambient_boost": 0.4, "sun_boost": 0.5}
var _base_ambient = Color("#9e80a8")
var _fog_begin = 200.0
var _fog_end = 260.0
var _fog_color = Color("#6b6185")
var _sky_energy = 1.0
var _ambient_energy = 0.9
var _sun_energy = 1.1
var _rain: CPUParticles
var _rain_mat = SpatialMaterial.new()
var _rain_amount = 0
var _rain_color = Color(0.42, 0.92, 0.36, 0.42)
var _bolts = []
var _sky_murk = -1.0
var _sky_top = Color("#1c1638")
var _sky_horizon = Color("#d9586b")
var _ground_horizon = Color("#6b3a55")
var _puddles = {}
var _puddle_mat = SpatialMaterial.new()
var _acid_puddle_mat = SpatialMaterial.new()
var _puddle_mesh = CylinderMesh.new()


static func hex(s, fallback := Color.white) -> Color:
	## glTF/Godot 4 hex is #RRGGBB[AA]; Godot 3's parser reads #AARRGGBB.
	if not (s is String) or not s.begins_with("#"):
		return fallback
	var h: String = s.substr(1)
	if h.length() == 8:
		return Color8(("0x" + h.substr(0, 2)).hex_to_int(), ("0x" + h.substr(2, 2)).hex_to_int(),
			("0x" + h.substr(4, 2)).hex_to_int(), ("0x" + h.substr(6, 2)).hex_to_int())
	if h.length() == 6:
		return Color8(("0x" + h.substr(0, 2)).hex_to_int(), ("0x" + h.substr(2, 2)).hex_to_int(),
			("0x" + h.substr(4, 2)).hex_to_int())
	return fallback


func setup(map_id: String, cfg: Dictionary, world_env: WorldEnvironment) -> void:
	_cfg = cfg
	_phases = cfg.get("phases", {}) if cfg.get("phases") is Dictionary else {}
	if cfg.get("lightning_flash") is Dictionary:
		_flash_cfg = cfg.lightning_flash
	var sky_cfg: Dictionary = cfg.get("sky", {}) if cfg.get("sky") is Dictionary else {}
	sky.sky_top_color = hex(sky_cfg.get("sky_top_color"), Color("#1c1638"))
	sky.sky_horizon_color = hex(sky_cfg.get("sky_horizon_color"), Color("#d9586b"))
	sky.sky_curve = float(sky_cfg.get("sky_curve", 0.12))
	_sky_top = sky.sky_top_color
	_sky_horizon = sky.sky_horizon_color
	_ground_horizon = hex(sky_cfg.get("ground_horizon_color"), Color("#6b3a55"))
	sky.ground_bottom_color = hex(sky_cfg.get("ground_bottom_color"), Color("#1a1426"))
	sky.ground_horizon_color = hex(sky_cfg.get("ground_horizon_color"), Color("#6b3a55"))
	sky.ground_curve = float(sky_cfg.get("ground_curve", 0.02))
	sky.sun_latitude = 12.0
	sky.sun_angle_max = 8.0
	sky.sun_color = Color("#ffa885")
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.background_sky = sky
	var amb: Dictionary = cfg.get("ambient", {}) if cfg.get("ambient") is Dictionary else {}
	_base_ambient = hex(amb.get("color"), Color("#9e80a8"))
	env.ambient_light_color = _base_ambient
	env.ambient_light_energy = float(amb.get("energy", 0.9))
	env.ambient_light_sky_contribution = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_depth_enabled = true
	env.fog_height_enabled = false
	env.fog_depth_curve = 1.0
	env.fog_sun_amount = 0.0
	env.glow_enabled = false
	world_env.environment = env
	var sun_cfg: Dictionary = cfg.get("sun", {}) if cfg.get("sun") is Dictionary else {}
	sun.light_color = hex(sun_cfg.get("color"), Color("#ffa885"))
	_sun_energy = float(sun_cfg.get("energy", 1.1))
	sun.light_energy = _sun_energy
	var rot = sun_cfg.get("rotation_rad")
	if rot is Array and rot.size() == 3:
		sun.rotation = Vector3(rot[0], rot[1], rot[2])
	else:
		sun.rotation = Vector3(-0.489, -1.047, 0.0)
	sun.shadow_enabled = false
	sun.light_specular = 0.3
	add_child(sun)
	_build_rain()
	_puddle_mesh.top_radius = 1.0
	_puddle_mesh.bottom_radius = 1.0
	_puddle_mesh.height = 0.02
	_puddle_mesh.radial_segments = 14
	_puddle_mesh.rings = 1
	for m in [_puddle_mat, _acid_puddle_mat]:
		m.flags_transparent = true
		m.flags_unshaded = true
	_puddle_mat.albedo_color = hex("#4d9e45b3")
	_acid_puddle_mat.albedo_color = hex("#6be033d1")
	_apply_phase(0.0, true)


func _build_rain() -> void:
	_rain = CPUParticles.new()
	_rain.emitting = false
	_rain.local_coords = false
	_rain.lifetime = 0.9
	_rain.preprocess = 0.9
	_rain.explosiveness = 0.0
	_rain.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(12, 1, 12)
	_rain.direction = Vector3(0.05, -1, 0.02)
	_rain.spread = 2.0
	_rain.gravity = Vector3.ZERO
	_rain.initial_velocity = 22.0
	var quad = QuadMesh.new()
	quad.size = Vector2(0.05, 0.9)
	_rain.mesh = quad
	_rain_mat.flags_unshaded = true
	_rain_mat.flags_transparent = true
	_rain_mat.params_billboard_mode = SpatialMaterial.BILLBOARD_FIXED_Y
	_rain_mat.albedo_color = _rain_color
	_rain_mat.flags_do_not_receive_shadows = true
	_rain.material_override = _rain_mat
	_rain.amount = 8
	add_child(_rain)


func update(delta: float, w: Dictionary) -> void:
	phase = str(w.get("phase", phase))
	intensity = float(w.get("intensity", intensity))
	_apply_phase(delta, false)
	if camera:
		_rain.global_transform.origin = camera.global_transform.origin + Vector3(0, 9, 0) - camera.global_transform.basis.z * 6.0
	for b in _bolts.duplicate():
		b.set_meta("life", float(b.get_meta("life")) - delta)
		if float(b.get_meta("life")) <= 0.0:
			_bolts.erase(b)
			b.queue_free()
		else:
			b.material_override.albedo_color.a = clamp(float(b.get_meta("life")) * 4.0, 0.0, 1.0)
	RetroMat.set_wetness(clamp(intensity / 0.7, 0.0, 1.0))
	Sound.ambience("rain", clamp(intensity * 1.2, 0.0, 1.0) * 0.5)
	Sound.ambience("storm_wind", clamp((intensity - 0.5) * 2.0, 0.0, 1.0) * 0.4)


func _phase_value(key: String, fallback):
	var p = _phases.get(phase)
	if p is Dictionary and p.has(key):
		return p[key]
	return fallback


func _apply_phase(delta: float, snap: bool) -> void:
	var fog_mul: float = [1.7, 1.25, 1.0][clamp(Settings.fog_quality, 0, 2)]
	var begin = float(_phase_value("fog_depth_begin_gles2", 200.0)) * fog_mul
	var end = float(_phase_value("fog_depth_end_gles2", 260.0)) * fog_mul
	var fog_col = hex(_phase_value("fog_color", "#6b6185"), Color("#6b6185"))
	var k = 1.0 if snap else 1.0 - exp(-1.2 * delta)
	_fog_begin = lerp(_fog_begin, begin, k)
	_fog_end = lerp(_fog_end, end, k)
	_fog_color = _fog_color.linear_interpolate(fog_col, k)
	_sky_energy = lerp(_sky_energy, float(_phase_value("sky_energy", 1.0)), k)
	_ambient_energy = lerp(_ambient_energy, float(_phase_value("ambient_energy", 0.9)), k)
	var sun_target = float(_phase_value("sun_energy", 1.1))
	flash = max(0.0, flash - delta * float(_flash_cfg.get("fade_rate", 2.6)))
	var glow = flash * flash
	env.fog_depth_begin = _fog_begin * (1.0 + glow * 0.25)
	env.fog_depth_end = max(_fog_end, _fog_begin + 5.0) * (1.0 + glow * 0.25)
	env.fog_color = _fog_color.linear_interpolate(Color(0.85, 1.0, 0.8), glow * 0.3)
	# Darken the sky toward the fog in a storm so the horizon reads as murk.
	var murk: float = clamp(intensity / 0.7, 0.0, 1.0)
	if abs(murk - _sky_murk) > 0.04 or snap:
		_sky_murk = murk
		var k2 = murk * 0.75
		sky.sky_top_color = _sky_top.linear_interpolate(_fog_color.darkened(0.35), k2)
		sky.sky_horizon_color = _sky_horizon.linear_interpolate(_fog_color, k2)
		sky.ground_horizon_color = _ground_horizon.linear_interpolate(_fog_color, k2)
	env.background_energy = _sky_energy * (1.0 - murk * 0.25) + glow * float(_flash_cfg.get("sky_boost", 0.85))
	env.ambient_light_energy = _ambient_energy * (1.0 + glow * float(_flash_cfg.get("ambient_boost", 0.4)))
	env.ambient_light_color = _base_ambient.linear_interpolate(_fog_color, murk * 0.35)
	sun.light_energy = lerp(sun.light_energy, sun_target, k) + glow * float(_flash_cfg.get("sun_boost", 0.5)) * 0.2
	if camera:
		camera.far = clamp(env.fog_depth_end + 15.0, 60.0, 400.0)
	# Rain amount by intensity, bucketed so the emitter isn't rebuilt often.
	_rain_color = hex(_phase_value("rain_color", "#6beb5c6b"), _rain_color)
	_rain_mat.albedo_color = _rain_color
	var want = int(round(intensity * 6.0)) * int(260 * Settings.particle_density)
	if want != _rain_amount:
		_rain_amount = want
		_rain.emitting = want > 0
		if want > 0:
			_rain.amount = want


func strike(at: Vector3) -> void:
	flash = Settings.flash_scale()
	var bolt = _make_bolt(at)
	add_child(bolt)
	bolt.set_meta("life", 0.28)
	_bolts.append(bolt)


func _make_bolt(at: Vector3) -> MeshInstance:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p = at + Vector3(rand_range(-6, 6), 45, rand_range(-6, 6))
	var steps = 9
	for i in steps:
		var t = float(i + 1) / steps
		var q = p.linear_interpolate(at, 1.0 / (steps - i))
		if i < steps - 1:
			q += Vector3(rand_range(-2.5, 2.5), 0, rand_range(-2.5, 2.5))
		var w = 0.35 * (1.0 - t * 0.6)
		for side in [Vector3(w, 0, 0), Vector3(0, 0, w)]:
			st.add_vertex(p - side)
			st.add_vertex(p + side)
			st.add_vertex(q + side)
			st.add_vertex(p - side)
			st.add_vertex(q + side)
			st.add_vertex(q - side)
		p = q
	var mi = MeshInstance.new()
	mi.mesh = st.commit()
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	m.albedo_color = Color(0.85, 1.0, 0.75, 1.0)
	mi.material_override = m
	return mi


func puddle(ev: Dictionary) -> void:
	var pid = ev.get("id")
	var on = bool(ev.get("on", true))
	var mi: MeshInstance = _puddles.get(pid)
	if not on:
		if mi:
			mi.queue_free()
			_puddles.erase(pid)
		return
	var pos = ev.get("pos")
	if not (pos is Array):
		return
	if mi == null:
		mi = MeshInstance.new()
		mi.mesh = _puddle_mesh
		add_child(mi)
		_puddles[pid] = mi
	mi.material_override = _acid_puddle_mat if phase == "acid_storm" else _puddle_mat
	var r = max(0.2, float(ev.get("radius", 1.5)))
	mi.global_transform = Transform(Basis().scaled(Vector3(r, 1, r)), Vector3(pos[0], float(pos[1]) + 0.03, pos[2]))
