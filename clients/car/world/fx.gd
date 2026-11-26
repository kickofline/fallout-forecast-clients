extends Spatial
## Pooled one-shot effects: tracers, muzzle flashes, hit sparks, death puffs.

const TRACERS = 32
const SPARKS = 10
const FLASHES = 8

var _tracers = []
var _tracer_i = 0
var _sparks = []
var _spark_i = 0
var _flashes = []
var _flash_i = 0
var _beam = CubeMesh.new()


func _ready() -> void:
	_beam.size = Vector3(1, 1, 1)
	for i in TRACERS:
		var mi = MeshInstance.new()
		mi.mesh = _beam
		var m = SpatialMaterial.new()
		m.flags_unshaded = true
		m.flags_transparent = true
		m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
		mi.material_override = m
		mi.visible = false
		mi.set_meta("life", 0.0)
		mi.set_meta("w", 0.025)
		mi.set_meta("full", false)
		add_child(mi)
		_tracers.append(mi)
	for i in SPARKS:
		var p = CPUParticles.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 10
		p.lifetime = 0.32
		p.local_coords = false
		p.direction = Vector3(0, 1, 0)
		p.spread = 180.0
		p.initial_velocity = 4.5
		p.initial_velocity_random = 0.6
		p.gravity = Vector3(0, -12, 0)
		p.scale_amount = 1.0
		var q = QuadMesh.new()
		q.size = Vector2(0.06, 0.06)
		p.mesh = q
		var m2 = SpatialMaterial.new()
		m2.flags_unshaded = true
		m2.vertex_color_use_as_albedo = true
		m2.params_billboard_mode = SpatialMaterial.BILLBOARD_ENABLED
		p.material_override = m2
		add_child(p)
		_sparks.append(p)
	for i in FLASHES:
		var f = MeshInstance.new()
		var q2 = QuadMesh.new()
		q2.size = Vector2(0.5, 0.5)
		f.mesh = q2
		var m3 = SpatialMaterial.new()
		m3.flags_unshaded = true
		m3.flags_transparent = true
		m3.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
		m3.params_billboard_mode = SpatialMaterial.BILLBOARD_ENABLED
		m3.albedo_color = Color(1.0, 0.8, 0.4, 1.0)
		m3.albedo_texture = _flash_texture()
		f.material_override = m3
		f.visible = false
		f.set_meta("life", 0.0)
		add_child(f)
		_flashes.append(f)


func _flash_texture() -> ImageTexture:
	var img = Image.new()
	img.create(16, 16, false, Image.FORMAT_RGBA8)
	img.lock()
	for y in 16:
		for x in 16:
			var d = Vector2(x - 7.5, y - 7.5).length() / 7.5
			var star: float = max(0.0, 1.0 - min(abs(x - 7.5), abs(y - 7.5)) / 2.0) * (1.0 - d)
			var a: float = clamp(max(1.0 - d * 1.4, star), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.unlock()
	var t = ImageTexture.new()
	t.create_from_image(img, 0)
	return t


## Draw the same material variants that the pool uses during combat.
func warmup(root: Spatial) -> void:
	var beam: MeshInstance = _tracers[0].duplicate()
	root.add_child(beam)
	beam.translation = Vector3(-0.8, 0.5, -3.0)
	beam.scale = Vector3(0.5, 0.05, 0.05)
	beam.show()
	var muzzle: MeshInstance = _flashes[0].duplicate()
	root.add_child(muzzle)
	muzzle.translation = Vector3(0.0, 0.5, -3.0)
	muzzle.show()
	if Settings.particle_density > 0.01:
		var sparks: CPUParticles = _sparks[0].duplicate()
		root.add_child(sparks)
		sparks.translation = Vector3(0.8, 0.5, -3.0)
		sparks.local_coords = true
		sparks.emitting = true


## `width` 0.025 is a bullet streak; `full` draws the whole segment at once
## (stream weapons: washer, leaf blower, zapper, disruptor).
func tracer(from: Vector3, to: Vector3, color := Color(1.0, 0.85, 0.5), width := 0.025, full := false) -> void:
	var length = from.distance_to(to)
	if length < 0.3:
		return
	var mi: MeshInstance = _tracers[_tracer_i]
	_tracer_i = (_tracer_i + 1) % TRACERS
	# A short bright streak that travels along the shot.
	mi.set_meta("from", from)
	mi.set_meta("to", to)
	mi.set_meta("life", 0.0)
	mi.set_meta("dur", clamp(length / 260.0, 0.04, 0.12) if not full else 0.09)
	mi.set_meta("w", width)
	mi.set_meta("full", full)
	(mi.material_override as SpatialMaterial).albedo_color = Color(color.r, color.g, color.b, 0.9)
	mi.visible = true
	_place_tracer(mi, 0.0)


func _place_tracer(mi: MeshInstance, t: float) -> void:
	var from: Vector3 = mi.get_meta("from")
	var to: Vector3 = mi.get_meta("to")
	var length = from.distance_to(to)
	var streak: float = min(length, 4.0)
	var head = from.linear_interpolate(to, clamp(t, 0.0, 1.0))
	var tail = head - (to - from).normalized() * streak * clamp(t * 3.0, 0.2, 1.0)
	if mi.get_meta("full"):
		head = to
		tail = from
	var mid = (head + tail) * 0.5
	var dir = head - tail
	if dir.length() < 0.01:
		return
	var up = Vector3.UP if abs(dir.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis = Transform().looking_at(dir, up).basis
	var w = float(mi.get_meta("w"))
	mi.global_transform = Transform(basis.scaled(Vector3(w, w, dir.length())), mid)


func flash(at: Vector3, size := 0.5, color := Color(1.0, 0.8, 0.4), life := 0.06) -> void:
	var f: MeshInstance = _flashes[_flash_i]
	_flash_i = (_flash_i + 1) % FLASHES
	f.global_transform = Transform(Basis().scaled(Vector3.ONE * size / 0.5), at)
	f.set_meta("life", life)
	(f.material_override as SpatialMaterial).albedo_color = color
	f.visible = true


func spark(at: Vector3, color := Color(1.0, 0.9, 0.5), amount_scale := 1.0) -> void:
	if Settings.particle_density <= 0.01:
		return
	var p: CPUParticles = _sparks[_spark_i]
	_spark_i = (_spark_i + 1) % SPARKS
	p.global_transform.origin = at
	p.color = color
	p.initial_velocity = 4.5 * amount_scale
	p.restart()
	p.emitting = true


func _process(delta: float) -> void:
	var _pt = OS.get_ticks_usec()
	_process_body(delta)
	Settings.prof_add("fx", OS.get_ticks_usec() - _pt)


func _process_body(delta: float) -> void:
	for mi in _tracers:
		if not mi.visible:
			continue
		var life: float = mi.get_meta("life") + delta
		mi.set_meta("life", life)
		var dur: float = mi.get_meta("dur")
		if life >= dur + 0.05:
			mi.visible = false
		else:
			_place_tracer(mi, life / dur)
	for f in _flashes:
		if not f.visible:
			continue
		var l: float = f.get_meta("life") - delta
		f.set_meta("life", l)
		if l <= 0.0:
			f.visible = false
