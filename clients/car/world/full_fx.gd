extends Spatial
## Full-tier world presentation that the Thin feed never needed. Everything
## here shares a handful of meshes and materials (cached per colour), uses
## fixed pools and allocates nothing per frame, because the head unit is
## draw-call bound:
##   - deployed effect zones (rim ring, dome shell, umbrella canopy model,
##     lightning-rod charge sweep, dome end-of-life warning pulse)
##   - enemy wind-up telegraphs (ground ring, Gutter lunge lane) and
##     Cloudburst / Mister landing rings
##   - harpoon bolt + winch cable, shell casings, death fragments, acid splats
##   - squad ping pillars, the airdrop beacon, raised-tarp sheets

const CASINGS = 12
const FRAGS = 18
const SPLATS = 10
const PINGS = 8
const TELLS = 10
const PING_COLORS = {"enemy": Color("#ff5689"), "danger": Color("#ff8a2a"), "revive": Color("#66dfda"),
	"shelter": Color("#9fb8ff"), "go": Color("#b8e56d")}
const ROD_COLOR = Color("#9fd8ff")
const DOME_WARNING_TIME = 3.0
const DOME_WARNING_COLOR = Color("#ffc365")
const HARPOON_FLIGHT = 0.07
const HARPOON_HOLD = 0.18
const HARPOON_REEL = 0.14

var _mats = {}
var _ring: ArrayMesh                 # flat annulus (Godot 3 has no TorusMesh)
var _disc = CylinderMesh.new()
var _hemi = SphereMesh.new()
var _box = CubeMesh.new()
var _pillar = CylinderMesh.new()
var _beam = CylinderMesh.new()
var _tarp = CubeMesh.new()
var _tarp_mat = SpatialMaterial.new()
var _casing_mat = SpatialMaterial.new()
var _frag_mats = []
var _splat_mat = SpatialMaterial.new()

var _casings = []      # [mi, vel, life]
var _casing_i = 0
var _frags = []        # [mi, vel, life]
var _frag_i = 0
var _splats = []       # [mi, life]
var _splat_i = 0
var _pings = []        # [mi, life]
var _ping_i = 0
var _tells = []        # [mi, life, total, follow(actor or null), kind]
var _tell_i = 0
var _zones = {}        # seq -> {root, rim, shell, left, kind, warn}
var _harpoons = []     # {bolt, cable, muzzle, contact, age}
var _beacon: Spatial
var _beacon_beam: MeshInstance
var _beacon_ring: MeshInstance
var _beacon_mat: SpatialMaterial
var _clock = 0.0


func _ready() -> void:
	_ring = _annulus(0.9, 24)
	_disc.top_radius = 1.0
	_disc.bottom_radius = 1.0
	_disc.height = 0.01
	_disc.radial_segments = 12
	_disc.rings = 1
	_hemi.radius = 1.0
	_hemi.height = 1.0
	_hemi.is_hemisphere = true
	_hemi.radial_segments = 16
	_hemi.rings = 5
	_box.size = Vector3.ONE
	_pillar.top_radius = 0.06
	_pillar.bottom_radius = 0.18
	_pillar.height = 1.0
	_pillar.radial_segments = 6
	_pillar.rings = 1
	_beam.top_radius = 0.14
	_beam.bottom_radius = 0.42
	_beam.height = 28.0
	_beam.radial_segments = 8
	_beam.rings = 1
	_tarp.size = Vector3(3.4, 0.05, 3.4)
	_tarp_mat.albedo_color = Color(0.2, 0.45, 0.9)
	_casing_mat.albedo_color = Color("#c9a24a")
	_casing_mat.metallic = 0.8
	_casing_mat.roughness = 0.3
	for c in [Color("#b5df68"), Color("#337c87")]:
		var m = SpatialMaterial.new()
		m.albedo_color = c
		_frag_mats.append(m)
	_splat_mat.flags_transparent = true
	_splat_mat.flags_unshaded = true
	_splat_mat.albedo_color = Color(0.45, 0.85, 0.25, 0.55)
	for i in CASINGS:
		_casings.append([_pooled(_box, _casing_mat), Vector3.ZERO, 0.0])
	for i in FRAGS:
		_frags.append([_pooled(_box, _frag_mats[i % 2]), Vector3.ZERO, 0.0])
	for i in SPLATS:
		_splats.append([_pooled(_disc, _splat_mat), 0.0])
	for i in PINGS:
		_pings.append([_pooled(_pillar, mat(Color.white, 0.55, true)), 0.0])
	for i in TELLS:
		_tells.append([_pooled(_ring, mat(Color(1.0, 0.36, 0.16), 0.8)), 0.0, 1.0, null, ""])


static func _annulus(inner: float, segs: int) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var a0 = TAU * i / segs
		var a1 = TAU * (i + 1) / segs
		var o0 = Vector3(cos(a0), 0, sin(a0))
		var o1 = Vector3(cos(a1), 0, sin(a1))
		for v in [o0 * inner, o0, o1, o0 * inner, o1, o1 * inner]:
			st.add_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


func _pooled(mesh: Mesh, m: Material) -> MeshInstance:
	var mi = MeshInstance.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


## Shared unshaded transparent material per colour + alpha (+ additive).
func mat(c: Color, alpha: float, add := false) -> SpatialMaterial:
	var key = "%s|%.2f|%s" % [c.to_html(false), alpha, str(add)]
	var m = _mats.get(key)
	if m == null:
		m = SpatialMaterial.new()
		m.flags_unshaded = true
		m.flags_transparent = true
		m.params_cull_mode = SpatialMaterial.CULL_DISABLED
		if add:
			m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
		m.albedo_color = Color(c.r, c.g, c.b, alpha)
		_mats[key] = m
	return m


# ------------------------------------------------------------------ tarps
func make_tarp() -> MeshInstance:
	var mi = MeshInstance.new()
	mi.mesh = _tarp
	mi.material_override = _tarp_mat
	mi.translation.y = 2.3
	mi.visible = false
	return mi


# ------------------------------------------------------------------ zones
## A deployed effect (projectile.gd _build_zone): coloured rim on the ground,
## a dome shell for shield_dome / bleach_bomb / disruptor, a sweep for the rod.
func zone_open(seq: int, id: String, at: Vector3, yaw: float, radius: float, color: Color, life: float) -> void:
	zone_close(seq)
	if radius <= 0.0 and id != "lightning_rod":
		return
	var root = Spatial.new()
	root.translation = at
	root.rotation.y = yaw
	add_child(root)
	var z = {"root": root, "left": max(0.0, life), "total": max(0.1, life), "id": id, "warn": -1}
	if radius > 0.0:
		var rim = MeshInstance.new()
		rim.mesh = _ring
		rim.material_override = mat(color, 0.65)
		rim.scale = Vector3(radius, 1.0, radius)
		rim.translation.y = 0.06
		root.add_child(rim)
		z["rim"] = rim
		z["radius"] = radius
	if id in ["shield_dome", "bleach_bomb", "disruptor"]:
		var shell = MeshInstance.new()
		shell.mesh = _hemi
		shell.material_override = mat(color, 0.16)
		shell.scale = Vector3(radius, radius, radius)
		shell.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		root.add_child(shell)
		z["shell"] = shell
		z["color"] = color
		if id == "shield_dome" and not Settings.reduced_flash and z.has("rim"):
			z["grow"] = 0.22
	if id == "lightning_rod":
		var sweep = MeshInstance.new()
		sweep.mesh = _ring
		sweep.material_override = mat(ROD_COLOR, 0.6, true)
		var r = max(radius, 1.0)
		sweep.scale = Vector3(r, 1.0, r)
		sweep.translation.y = 0.08
		root.add_child(sweep)
		z["sweep"] = sweep
		z["sweep_r"] = r
		z["spark_left"] = 0.0
	_zones[seq] = z


func zone_close(seq: int) -> void:
	var z = _zones.get(seq)
	if z == null:
		return
	_zones.erase(seq)
	if is_instance_valid(z.root):
		z.root.queue_free()


func zone_count() -> int:
	return _zones.size()


func _tick_zones(delta: float, fx) -> void:
	for seq in _zones:
		var z = _zones[seq]
		z.left = max(0.0, z.left - delta)
		if z.has("grow") and z.grow > 0.0:
			z.grow = max(0.0, z.grow - delta)
			var k = 1.0 - z.grow / 0.22
			var r = z.radius * lerp(0.18, 1.0, 1.0 - (1.0 - k) * (1.0 - k))
			z.rim.scale = Vector3(r, 1.0, r)
		if z.id == "shield_dome" and z.left <= DOME_WARNING_TIME:
			var warn = 0
			if not Settings.reduced_flash and z.left > 0.0 and fmod(DOME_WARNING_TIME - z.left, 0.5) < 0.2:
				warn = 1
			if warn != z.warn:
				z.warn = warn
				z.rim.material_override = mat(DOME_WARNING_COLOR, 0.96 if warn == 1 else 0.64)
				z.shell.material_override = mat(DOME_WARNING_COLOR, 0.29 if warn == 1 else 0.13)
		if z.has("sweep"):
			var f = clamp(1.0 - z.left / z.total, 0.0, 1.0)
			var r2 = lerp(z.sweep_r, 0.25, f * f)
			z.sweep.scale = Vector3(r2, 1.0, r2)
			z.spark_left -= delta
			if z.spark_left <= 0.0 and z.left > 0.0:
				z.spark_left = max(0.08, z.total / 5.0 * (1.0 - f * 0.6))
				fx.spark(z.root.translation + Vector3(0, 0.95, 0), ROD_COLOR, 0.6 + f)


# ------------------------------------------------------------------ telegraphs
## Enemy wind-up (enemy_base attack_flash / gutter lunge lane).
func tell(actor: Spatial, kind: String, duration: float, radius: float) -> void:
	var t = _tells[_tell_i]
	_tell_i = (_tell_i + 1) % TELLS
	var mi: MeshInstance = t[0]
	mi.mesh = _box if kind == "gutter" else _ring
	t[1] = max(0.15, duration)
	t[2] = t[1]
	t[3] = actor
	t[4] = kind
	mi.set_meta("r", radius)
	mi.visible = true
	_place_tell(t)


## A fixed ground ring (Cloudburst / spore landing spot) for `duration` s.
func ground_ring(at: Vector3, radius: float, duration: float, color := Color(0.72, 1.0, 0.34)) -> void:
	var t = _tells[_tell_i]
	_tell_i = (_tell_i + 1) % TELLS
	var mi: MeshInstance = t[0]
	mi.mesh = _ring
	mi.material_override = mat(color, 0.7)
	t[1] = max(0.15, duration)
	t[2] = t[1]
	t[3] = null
	t[4] = "ground"
	mi.translation = at + Vector3(0, 0.07, 0)
	mi.rotation = Vector3.ZERO
	mi.scale = Vector3(radius, 1.0, radius)
	mi.visible = true


func _place_tell(t: Array) -> void:
	var mi: MeshInstance = t[0]
	var a = t[3]
	if a == null:
		return
	if not is_instance_valid(a) or a.dying:
		mi.visible = false
		t[1] = 0.0
		return
	var f = clamp(1.0 - t[1] / t[2], 0.0, 1.0)
	var r = float(mi.get_meta("r"))
	if t[4] == "gutter":
		mi.material_override = mat(Color(1.0, 0.36, 0.16), 0.85)
		var seg_len = 2.2 * (0.55 + f * 0.95)
		mi.global_transform = Transform(Basis(Vector3.UP, a.rotation.y).scaled(Vector3(0.32, 0.03, seg_len)),
			a.translation + Basis(Vector3.UP, a.rotation.y).xform(Vector3(0, 0.08, -0.4 - seg_len * 0.5)))
	else:
		mi.material_override = mat(Color(1.0, 0.32, 0.12), 0.5 + 0.4 * f)
		var rr = r * lerp(1.15, 0.85, f)
		mi.global_transform = Transform(Basis().scaled(Vector3(rr, 1.0, rr)), a.translation + Vector3(0, 0.07, 0))


# ------------------------------------------------------------------ one-shots
func casing(at: Vector3, right: Vector3, heavy: bool) -> void:
	var c = _casings[_casing_i]
	_casing_i = (_casing_i + 1) % CASINGS
	var mi: MeshInstance = c[0]
	mi.scale = Vector3(0.012, 0.012, 0.03) * (1.6 if heavy else 1.0)
	mi.translation = at
	c[1] = right * rand_range(1.2, 1.8) + Vector3(0, rand_range(1.6, 2.4), 0)
	c[2] = 0.75
	mi.visible = true


func fragments(at: Vector3, throw_vec: Vector3, critical: bool) -> void:
	for i in 6:
		var f = _frags[_frag_i]
		_frag_i = (_frag_i + 1) % FRAGS
		var mi: MeshInstance = f[0]
		mi.translation = at + Vector3(0, 1.6 if critical else 1.0, 0)
		var s = rand_range(0.1, 0.22)
		mi.scale = Vector3(s, s, s)
		f[1] = (Vector3(rand_range(-1, 1), rand_range(0.3, 1.2), rand_range(-1, 1)) + throw_vec * rand_range(0.7, 1.3)) * 3.0
		f[2] = 0.55
		mi.visible = true


func splat(at: Vector3, radius := 0.7) -> void:
	var s = _splats[_splat_i]
	_splat_i = (_splat_i + 1) % SPLATS
	var mi: MeshInstance = s[0]
	mi.transform = Transform(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(radius, 1.0, radius * rand_range(0.6, 1.0))), at + Vector3(0, 0.05, 0))
	s[1] = 8.0
	mi.visible = true


func ping(at: Vector3, kind: String, life := 6.0) -> void:
	var p = _pings[_ping_i]
	_ping_i = (_ping_i + 1) % PINGS
	var mi: MeshInstance = p[0]
	mi.material_override = mat(PING_COLORS.get(kind, Color("#ffbf68")), 0.55, true)
	mi.transform = Transform(Basis().scaled(Vector3(1, 3.0, 1)), at + Vector3(0, 1.5, 0))
	p[1] = life
	mi.visible = true


## Harpoon: bolt flies to the contact point, holds, then reels back on the cable.
func harpoon(bolt: Spatial, muzzle: Vector3, contact: Vector3, color: Color) -> void:
	var cable = MeshInstance.new()
	cable.mesh = _box
	cable.material_override = mat(color.linear_interpolate(Color("#ffd184"), 0.55), 1.0)
	add_child(cable)
	if bolt:
		add_child(bolt)
	_harpoons.append({"bolt": bolt, "cable": cable, "muzzle": muzzle, "contact": contact, "age": 0.0, "ticked": false})


func _tick_harpoons(delta: float) -> void:
	var total = HARPOON_FLIGHT + HARPOON_HOLD + HARPOON_REEL
	for i in range(_harpoons.size() - 1, -1, -1):
		var h = _harpoons[i]
		h.age += delta
		if h.age >= total:
			if h.bolt and is_instance_valid(h.bolt):
				h.bolt.queue_free()
			h.cable.queue_free()
			_harpoons.remove(i)
			continue
		var reel = HARPOON_FLIGHT + HARPOON_HOLD
		if not h.ticked and h.age >= reel:
			h.ticked = true
			Sound.play_at("reel_tick", h.muzzle, -12.0)
		var head: Vector3 = h.muzzle.linear_interpolate(h.contact, min(h.age / HARPOON_FLIGHT, 1.0))
		if h.age > reel:
			head = h.contact.linear_interpolate(h.muzzle, smoothstep(reel, total, h.age))
		var d: Vector3 = h.contact - h.muzzle
		if d.length() < 0.05:
			continue
		var up = Vector3.UP if abs(d.normalized().y) < 0.99 else Vector3.RIGHT
		var basis = Transform().looking_at(d, up).basis
		if h.bolt and is_instance_valid(h.bolt):
			h.bolt.global_transform = Transform(basis, head)
		var seg_len = h.muzzle.distance_to(head)
		h.cable.visible = seg_len > 0.02
		if h.cable.visible:
			h.cable.global_transform = Transform(basis.scaled(Vector3(0.027, 0.027, seg_len)), (h.muzzle + head) * 0.5)


# ------------------------------------------------------------------ airdrop beacon
func beacon(at, airborne: bool) -> void:
	if at == null:
		if _beacon:
			_beacon.visible = false
		return
	if _beacon == null:
		_beacon = Spatial.new()
		add_child(_beacon)
		_beacon_mat = SpatialMaterial.new()
		_beacon_mat.flags_unshaded = true
		_beacon_mat.flags_transparent = true
		_beacon_mat.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
		_beacon_mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
		_beacon_mat.albedo_color = Color(1.0, 0.75, 0.41, 0.22)
		_beacon_beam = MeshInstance.new()
		_beacon_beam.mesh = _beam
		_beacon_beam.material_override = _beacon_mat
		_beacon_beam.translation.y = 14.0
		_beacon.add_child(_beacon_beam)
		_beacon_ring = MeshInstance.new()
		_beacon_ring.mesh = _ring
		_beacon_ring.material_override = mat(Color("#ffbf68"), 0.8)
		_beacon_ring.scale = Vector3(1.6, 1.0, 1.6)
		_beacon_ring.translation.y = 0.07
		_beacon.add_child(_beacon_ring)
	_beacon.visible = true
	_beacon.translation = at
	var pulse = 0.5 if Settings.reduced_flash else 0.5 + 0.5 * sin(_clock * 4.5)
	_beacon_mat.albedo_color.a = lerp(0.16, 0.30, pulse) if airborne else lerp(0.09, 0.17, pulse)


# ------------------------------------------------------------------ frame
func tick(delta: float, fx) -> void:
	_clock += delta
	for c in _casings:
		if c[2] <= 0.0:
			continue
		c[2] -= delta
		var mi: MeshInstance = c[0]
		c[1].y -= 9.8 * delta
		mi.translation += c[1] * delta
		mi.rotate_x(14.0 * delta)
		if c[2] <= 0.0:
			mi.visible = false
			if randf() < 0.5:
				Sound.play_at("casing_%d" % (randi() % 3), mi.translation, -20.0)
	for f in _frags:
		if f[2] <= 0.0:
			continue
		f[2] -= delta
		var fm: MeshInstance = f[0]
		f[1] *= 0.9
		fm.translation += f[1] * delta
		if f[2] < 0.3:
			fm.scale *= 0.85
		if f[2] <= 0.0:
			fm.visible = false
	for s in _splats:
		if s[1] > 0.0:
			s[1] -= delta
			if s[1] <= 0.0:
				s[0].visible = false
	for p in _pings:
		if p[1] > 0.0:
			p[1] -= delta
			if p[1] <= 0.0:
				p[0].visible = false
	for t in _tells:
		if t[1] <= 0.0:
			continue
		t[1] -= delta
		if t[1] <= 0.0:
			t[0].visible = false
		else:
			_place_tell(t)
	_tick_zones(delta, fx)
	if not _harpoons.empty():
		_tick_harpoons(delta)
