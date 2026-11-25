extends Node
## The run: a low-resolution 3D Viewport (PS1 pixels + cheap GLES2 fill),
## shown through a TextureRect whose canvas shader does the VHS post pass.
## Snapshots are interpolated ~100 ms behind the bridge clock; the car's own
## camera uses the newest position with light velocity extrapolation and
## locally owned yaw/pitch. Touch input is sent as `in` at 30 Hz.

signal hit_marker(kill, head)
signal hurt(dir, amount)
signal banner(text)
signal picked(item)
signal killed(type)

const Actor = preload("res://world/actor.gd")
const Fx = preload("res://world/fx.gd")
const Weather = preload("res://world/weather.gd")
const Viewmodel = preload("res://world/viewmodel.gd")
const RETRO_POST = preload("res://shaders/retro_post.shader")
const CLEAN_POST = preload("res://shaders/clean_post.shader")
const EYE = 1.65
const EYE_CROUCH = 0.95
const HIP_FOV = 75.0
const MAX_PITCH = 1.5359  # 88 degrees
const SEND_HZ = 30.0
const BITS = {"fire": 1, "aim": 2, "jump": 4, "crouch": 8, "sprint": 16, "reload": 32, "interact": 64,
	"use_item": 128, "drop_item": 256, "ping": 512, "ready_up": 1024, "throw_grenade": 2048, "throw_dome": 4096}
const PICKUP_PROPS = {"ammo": "pickup_ammo", "health": "pickup_health", "suit": "pickup_suit",
	"scrap": "pickup_scrap", "airdrop": "airdrop", "station": "vending_station"}

var ready_to_play = false
var map_id = ""
var viewport = Viewport.new()
var scene = Spatial.new()
var camera = Camera.new()
var viewmodel: Spatial
var fx: Spatial
var weather: Spatial
var display = TextureRect.new()
# The VHS/clean post pass runs in its own viewport at the 3D resolution (its
# result only varies per virtual pixel anyway); `display` just upscales it.
# Running it per screen pixel at 1240x686 capped the head unit at ~14 fps.
var post_vp = Viewport.new()
var post_rect = TextureRect.new()
var level: Spatial
var latest = {}
var you = {}
var run = {}
var weather_state = {}
var enemies = {}
var players = {}
var pickup_nodes = {}
var projectile_nodes = {}
var others = []                 # interpolated teammates for the HUD
var enemy_points = []           # interpolated enemy positions for the compass
var pickups_list = []
var glitch = 0.0
var shake = 0.0

# Look + input (written by the touch layer).
var yaw = 0.0
var pitch = 0.0
var look_ready = false
var move = Vector2.ZERO
var held_bits = 0
var auto_bits = 0                # test harness (core/capture.gd) only
var auto_move = Vector2.ZERO
var _latched_bits = 0
var _slot_pulse = 0
var _slot_frames = 0
var _wheel = 0
var _seq = 0
var _send_left = 0.0

var _layer = CanvasLayer.new()
var _post_retro = ShaderMaterial.new()
var _post_clean = ShaderMaterial.new()
var _buf = []
var _cam_pos = Vector3.ZERO
var _cam_init = false
var _snap_local_ms = 0
var _last_local_shot = -10000
var _shot_cue = ""
var _shot_cue_ms = -10000
var _prev_fire = false
var _decon_cells = []
var _fov = HIP_FOV
var _world_env = WorldEnvironment.new()
var _anim_time = 0.0
var _warm: Spatial
var _warm_frames = 0
var _initial_snapshot_frames = 2

# Incremental map load (ResourceInteractiveLoader stepped each frame).
var loading = false
var load_progress = 0.0
var _loader: ResourceInteractiveLoader
var _load_path = ""
var _load_variant = ""
var _load_t0 = 0
var _load_ms = {}
var _fixed_cam = []


func _ready() -> void:
	viewport.usage = Viewport.USAGE_3D_NO_EFFECTS
	viewport.hdr = false
	viewport.msaa = Viewport.MSAA_DISABLED
	viewport.own_world = true
	viewport.render_target_v_flip = true
	viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	viewport.audio_listener_enable_3d = true
	viewport.shadow_atlas_size = 0
	viewport.keep_3d_linear = false
	add_child(viewport)
	viewport.add_child(scene)
	scene.add_child(_world_env)
	camera.current = true
	camera.fov = HIP_FOV
	camera.near = 0.08  # was 0.05: more depth precision on the SGX (road decals)
	camera.far = 260.0
	scene.add_child(camera)
	viewmodel = Viewmodel.new()
	camera.add_child(viewmodel)
	fx = Fx.new()
	scene.add_child(fx)
	weather = Weather.new()
	weather.camera = camera
	scene.add_child(weather)
	_layer.layer = 0
	add_child(_layer)
	display.expand = true
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_vp.usage = Viewport.USAGE_2D_NO_SAMPLING
	post_vp.hdr = false
	post_vp.msaa = Viewport.MSAA_DISABLED
	post_vp.transparent_bg = false
	post_vp.render_target_v_flip = true
	post_vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	post_vp.gui_disable_input = true
	add_child(post_vp)
	post_rect.expand = true
	post_rect.stretch_mode = TextureRect.STRETCH_SCALE
	post_rect.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_rect.texture = viewport.get_texture()
	post_vp.add_child(post_rect)
	display.texture = post_vp.get_texture()
	_layer.add_child(display)
	_post_retro.shader = RETRO_POST
	_post_clean.shader = CLEAN_POST
	Net.connect("snapshot", self, "_on_snapshot")
	Net.connect("events", self, "_on_events")
	Settings.connect("changed", self, "resize")
	resize()


func _exit_tree() -> void:
	Sound.ambience("rain", 0.0)
	Sound.ambience("storm_wind", 0.0)
	Sound.stop_music()


func resize() -> void:
	var win = OS.window_size
	if win.x < 2 or win.y < 2:
		win = Vector2(1240, 606)
	var aspect = win.x / win.y
	var size: Vector2
	if Settings.retro_enabled:
		var lines = float(Settings.retro_lines)
		size = Vector2(round(lines * aspect), lines)
		post_rect.material = _post_retro
		_post_retro.set_shader_param("res", size)
		viewport.get_texture().flags = 0
		post_vp.get_texture().flags = 0
	else:
		var s: float = clamp(Settings.render_scale, 0.25, 1.0)
		size = Vector2(round(win.x * s), round(win.y * s))
		post_rect.material = _post_clean
		viewport.get_texture().flags = 0
		post_vp.get_texture().flags = Texture.FLAG_FILTER
	viewport.size = size
	post_vp.size = size
	post_rect.rect_size = size
	RetroMat.snap = 120.0 if Settings.retro_enabled else 0.0


# ------------------------------------------------------------------ map
## Starts an incremental load: the scene resource is read a few stages per
## frame (so the loading card animates and Net keeps up); _finish_load()
## instances it once complete.
func load_map(id: String) -> void:
	map_id = id
	loading = true
	load_progress = 0.0
	_load_t0 = OS.get_ticks_msec()
	var pick = Assets.map_variant(id, Settings.map_detail)
	_load_variant = pick[0]
	_load_path = pick[1]
	if not _load_path.empty() and not Assets.is_cached(_load_path) and ResourceLoader.exists(_load_path):
		_loader = ResourceLoader.load_interactive(_load_path)
	print("LOAD start map=%s variant=%s path=%s cached=%s" % [id, _load_variant, _load_path, str(Assets.is_cached(_load_path))])


func _step_load() -> void:
	if _loader:
		var budget_end = OS.get_ticks_msec() + 35
		while OS.get_ticks_msec() < budget_end:
			var err = _loader.poll()
			if err == ERR_FILE_EOF:
				Assets.store_scene(_load_path, _loader.get_resource())
				_loader = null
				break
			elif err != OK:
				print("LOAD error %d reading %s" % [err, _load_path])
				_loader = null
				break
		if _loader:
			load_progress = float(_loader.get_stage()) / float(max(1, _loader.get_stage_count()))
			return
		_load_ms["read"] = OS.get_ticks_msec() - _load_t0
	load_progress = 1.0
	_finish_load()


func load_text() -> String:
	if loading:
		return "LOADING MAP  %d%%" % int(load_progress * 100.0)
	if not ready_to_play:
		return "WARMING UP" if _warm_frames > 0 or not look_ready else "TUNING"
	return ""


func _finish_load() -> void:
	loading = false
	var t = OS.get_ticks_msec()
	var packed = Assets.load_scene(_load_path) if not _load_path.empty() else null
	if packed:
		level = packed.instance()
	else:
		level = _placeholder_level()
	scene.add_child(level)
	_load_ms["instance"] = OS.get_ticks_msec() - t
	t = OS.get_ticks_msec()
	RetroMat.prepare(level)
	_load_ms["prepare"] = OS.get_ticks_msec() - t
	t = OS.get_ticks_msec()
	_setup_culling()
	var id = map_id
	weather.setup(id, Assets.map_environment(id), _world_env)
	var side = Assets.map_sidecar(id)
	var cells = Assets.prop_scene("decon_shower_cells")
	if cells and side.get("decon_showers") is Array:
		for d in side.decon_showers:
			if d is Dictionary and d.get("pos") is Array:
				var c: Spatial = cells.instance()
				scene.add_child(c)
				c.translation = _v(d.pos) + Vector3(0, 1.0, 0)
				c.rotation.y = float(d.get("rot_y", 0.0))
				RetroMat.prepare(c)
				for i in 4:
					var cell = c.find_node("Cell%d" % i, true, false)
					if cell:
						_decon_cells.append([i, cell])
	Sound.attach_world(scene)
	Sound.music("forecast_theme")
	_warmup()
	_load_ms["extras"] = OS.get_ticks_msec() - t
	_load_ms["t_warm"] = OS.get_ticks_msec()
	VisualServer.connect("frame_post_draw", self, "_on_loading_frame")


## Chunked maps: cells are separate MeshInstances, so Godot's per-instance
## frustum culling works; clip them at the fog distance.
func _setup_culling() -> void:
	for a in Settings.args():
		if str(a).begins_with("--cam="):
			_fixed_cam = Array(str(a).substr(6).split_floats(","))
	# Test switches (user://test_args.txt) for on-car A/B runs.
	if Settings.has_arg("--hide-level"):
		level.visible = false
	if Settings.has_arg("--no-3d"):
		viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
	if Settings.has_arg("--no-post"):
		post_rect.material = null
	if Settings.has_arg("--no-rain"):
		weather.set_rain_enabled(false)


## Merge the enemy rigs and draw the warm-up instances behind the loading
## card, ahead of the first in-game GLES2 shader use.
func _warmup() -> void:
	_warm = Spatial.new()
	camera.add_child(_warm)
	for type in Assets.ids("enemies"):
		var a = Actor.new()
		_warm.add_child(a)
		a.setup_enemy(type)
		a.spawn_left = 0.0
	for kind in ["ammo", "health", "suit", "scrap", "airdrop", "station"]:
		_warm.add_child(_make_pickup({"kind": kind, "item": kind}))
	for kind in Assets.ids("projectiles"):
		_warm.add_child(_make_projectile(kind))
	for i in range(_warm.get_child_count()):
		_warm.get_child(i).translation = Vector3((i % 6) - 2.5, -1.6, -5.0 - floor(i / 6.0))
	fx.warmup(_warm)
	_warm_frames = 3


func _on_loading_frame() -> void:
	if _warm_frames > 0:
		_warm_frames -= 1
		if _warm_frames == 0:
			_warm.queue_free()
		return
	# The first snapshot can already have enemies, gear, and teammates.
	# Give the populated viewport a chance to render under the loading card.
	if not look_ready:
		return
	_initial_snapshot_frames -= 1
	if _initial_snapshot_frames == 0:
		VisualServer.disconnect("frame_post_draw", self, "_on_loading_frame")
		ready_to_play = true
		# Open Protocol (2026-11-25): full snapshot rate from here on.
		Net.send({"t": "loaded"})
		print("LOAD done map=%s variant=%s read=%dms instance=%dms prepare=%dms extras=%dms warm+first_draw=%dms total=%dms" % [
			map_id, _load_variant, int(_load_ms.get("read", 0)), int(_load_ms.get("instance", 0)),
			int(_load_ms.get("prepare", 0)), int(_load_ms.get("extras", 0)),
			OS.get_ticks_msec() - int(_load_ms.get("t_warm", OS.get_ticks_msec())), OS.get_ticks_msec() - _load_t0])
		get_parent().call_deferred("world_ready")


func _placeholder_level() -> Spatial:
	var root = Spatial.new()
	var ground = MeshInstance.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(140, 140)
	ground.mesh = plane
	var gm = SpatialMaterial.new()
	gm.albedo_color = Color("#2b2a33")
	ground.material_override = gm
	root.add_child(ground)
	var road = MeshInstance.new()
	var rp = PlaneMesh.new()
	rp.size = Vector2(10, 140)
	road.mesh = rp
	var rm = SpatialMaterial.new()
	rm.albedo_color = Color("#1c1b22")
	road.material_override = rm
	road.translation.y = 0.01
	root.add_child(road)
	var colors = [Color("#e8d8c8"), Color("#6fb7b0"), Color("#d98fa6"), Color("#c9b27c")]
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(map_id)
	for i in 18:
		var b = MeshInstance.new()
		var cube = CubeMesh.new()
		cube.size = Vector3(rng.randf_range(6, 10), rng.randf_range(4, 9), rng.randf_range(6, 10))
		b.mesh = cube
		var bm = SpatialMaterial.new()
		bm.albedo_color = colors[i % colors.size()]
		b.material_override = bm
		var side = -1.0 if i % 2 == 0 else 1.0
		b.translation = Vector3(side * rng.randf_range(12, 26), cube.size.y * 0.5, -60 + (i / 2) * 14)
		root.add_child(b)
	return root


static func _v(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


# ------------------------------------------------------------------ snapshots
func _on_snapshot(s: Dictionary) -> void:
	var _t = OS.get_ticks_usec()
	_on_snapshot_body(s)
	Settings.prof_add("w_snap", OS.get_ticks_usec() - _t)


func _on_snapshot_body(s: Dictionary) -> void:
	latest = s
	_snap_local_ms = OS.get_ticks_msec()
	if s.get("you") is Dictionary:
		you = s.you
	if s.get("run") is Dictionary:
		run = s.run
	if s.get("weather") is Dictionary:
		weather_state = s.weather
	if s.get("pickups") is Array:
		pickups_list = s.pickups
		_sync_pickups()
	var entry = {"t": float(s.get("t_ms", OS.get_ticks_msec())), "players": {}, "enemies": {}, "projectiles": {}}
	for key in ["players", "enemies", "projectiles"]:
		var arr = s.get(key)
		if arr is Array:
			var d: Dictionary = entry[key]
			for row in arr:
				if row is Dictionary and row.has("id"):
					d[row.id] = row
	_buf.append(entry)
	while _buf.size() > 40:
		_buf.pop_front()
	if not look_ready and not you.empty():
		yaw = float(you.get("yaw", 0.0))
		pitch = float(you.get("pitch", 0.0))
		look_ready = true


func _bracket() -> Array:
	if _buf.empty():
		return []
	var rt = Net.bridge_now_ms() - Settings.interp_ms
	var n = _buf.size()
	if rt >= _buf[n - 1].t or n == 1:
		return [_buf[n - 1], _buf[n - 1], 0.0]
	if rt <= _buf[0].t:
		return [_buf[0], _buf[0], 0.0]
	for i in range(n - 1, 0, -1):
		var a: Dictionary = _buf[i - 1]
		if a.t <= rt:
			var b: Dictionary = _buf[i]
			var span: float = max(1.0, b.t - a.t)
			return [a, b, clamp((rt - a.t) / span, 0.0, 1.0)]
	return [_buf[0], _buf[0], 0.0]


func _lerp_pos(ra, rb, f: float) -> Vector3:
	var pb = _v(rb.get("pos"))
	if ra is Dictionary:
		return _v(ra.get("pos")).linear_interpolate(pb, f)
	return pb


func _lerp_yaw(ra, rb, f: float) -> float:
	var yb = float(rb.get("yaw", 0.0))
	if ra is Dictionary:
		return lerp_angle(float(ra.get("yaw", yb)), yb, f)
	return yb


func _sync_entities() -> void:
	var br = _bracket()
	if br.empty():
		return
	var a: Dictionary = br[0]
	var b: Dictionary = br[1]
	var f: float = br[2]
	# Enemies (incl. turned players and the boss).
	enemy_points.clear()
	for id in b.enemies:
		var row: Dictionary = b.enemies[id]
		var actor = enemies.get(id)
		if actor == null or not is_instance_valid(actor):
			actor = Actor.new()
			actor.id = id
			scene.add_child(actor)
			actor.setup_enemy(str(row.get("type", "gutter")))
			Settings.spike_ctx.append("spawn:" + str(row.get("type", "")))
			enemies[id] = actor
		var pos = _lerp_pos(a.enemies.get(id), row, f)
		actor.translation = pos
		actor.rotation.y = _lerp_yaw(a.enemies.get(id), row, f)
		actor.set_anim(str(row.get("anim", "walk")))
		if row.get("hp") != null:
			actor.hp = float(row.hp)
		if str(row.get("anim", "")) == "die" and not actor.dying:
			actor.kill()
		enemy_points.append([pos, str(row.get("type", "")), row.get("hp")])
	for id in enemies.keys():
		if not b.enemies.has(id):
			var gone = enemies[id]
			enemies.erase(id)
			if is_instance_valid(gone) and not gone.dying:
				gone.kill()
				fx.spark(gone.translation + Vector3(0, 1.0, 0), Color(0.55, 1.0, 0.3), 1.4)
	# Teammates.
	others.clear()
	for id in b.players:
		var row: Dictionary = b.players[id]
		var actor = players.get(id)
		var model_id = Assets.player_model_id(row.get("skin"), row.get("suit_color"))
		if actor == null or not is_instance_valid(actor) or actor.get_meta("model") != model_id:
			if actor and is_instance_valid(actor):
				actor.queue_free()
			actor = Actor.new()
			actor.id = id
			actor.set_meta("model", model_id)
			scene.add_child(actor)
			actor.setup_player(model_id, Weather.hex(row.get("suit_color"), Color("#2ec9c9")))
			players[id] = actor
		var pos = _lerp_pos(a.players.get(id), row, f)
		actor.translation = pos
		actor.rotation.y = _lerp_yaw(a.players.get(id), row, f)
		actor.state = str(row.get("state", "ok"))
		actor.pitch = float(row.get("pitch", 0.0))
		actor.visible = actor.state != "out"
		actor.set_item(row.get("item"))
		others.append({"id": id, "name": str(row.get("name", "")), "pos": pos, "state": actor.state,
			"color": Weather.hex(row.get("suit_color"), Color("#66dfda"))})
	for id in players.keys():
		if not b.players.has(id):
			if is_instance_valid(players[id]):
				players[id].queue_free()
			players.erase(id)
	# Projectiles: interpolated, fall back to extrapolation for new ones.
	for id in b.projectiles:
		var row: Dictionary = b.projectiles[id]
		var node = projectile_nodes.get(id)
		if node == null or not is_instance_valid(node):
			node = _make_projectile(str(row.get("kind", "")))
			scene.add_child(node)
			projectile_nodes[id] = node
		var pos = _lerp_pos(a.projectiles.get(id), row, f)
		node.translation = pos
		var vel = _v(row.get("vel"))
		if vel.length_squared() > 0.01:
			node.look_at(pos + vel, Vector3.UP if abs(vel.normalized().y) < 0.95 else Vector3.RIGHT)
	for id in projectile_nodes.keys():
		if not b.projectiles.has(id):
			if is_instance_valid(projectile_nodes[id]):
				projectile_nodes[id].queue_free()
			projectile_nodes.erase(id)


func _make_projectile(kind: String) -> Spatial:
	var packed = Assets.projectile_scene(kind)
	if packed:
		var n: Spatial = packed.instance()
		RetroMat.prepare(n)
		return n
	var mi = MeshInstance.new()
	var s = SphereMesh.new()
	s.radius = 0.14
	s.height = 0.28
	s.radial_segments = 8
	s.rings = 4
	mi.mesh = s
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_color = Color(0.6, 1.0, 0.3) if ("acid" in kind or "spore" in kind or "spit" in kind) else Color(1.0, 0.7, 0.3)
	mi.material_override = m
	return mi


func _sync_pickups() -> void:
	var seen = {}
	for row in pickups_list:
		if not (row is Dictionary):
			continue
		var id = row.get("id")
		seen[id] = true
		var node = pickup_nodes.get(id)
		if node == null or not is_instance_valid(node):
			node = _make_pickup(row)
			scene.add_child(node)
			pickup_nodes[id] = node
		node.translation = _v(row.get("pos"))
	for id in pickup_nodes.keys():
		if not seen.has(id):
			if is_instance_valid(pickup_nodes[id]):
				pickup_nodes[id].queue_free()
			pickup_nodes.erase(id)


func _make_pickup(row: Dictionary) -> Spatial:
	var kind = str(row.get("kind", "item"))
	var item = str(row.get("item", ""))
	var packed: PackedScene = null
	var spin = false
	if kind in ["weapon", "item"]:
		packed = Assets.weapon_pickup(item)
		spin = true
	if packed == null and PICKUP_PROPS.has(kind):
		var prop: String = PICKUP_PROPS[kind]
		if kind == "scrap" and item == "scrap_large":
			prop = "pickup_scrap_large"
		packed = Assets.prop_scene(prop)
	if packed == null and kind in ["weapon", "item"]:
		packed = Assets.prop_scene("pickup_supply")
	var holder = Spatial.new()
	holder.set_meta("spin", spin)
	holder.set_meta("kind", kind)
	var n: Spatial
	if packed:
		n = packed.instance()
	else:
		var mi = MeshInstance.new()
		var c = CubeMesh.new()
		c.size = Vector3(0.5, 0.35, 0.5) if kind != "station" else Vector3(2.1, 2.1, 0.9)
		mi.mesh = c
		var m = SpatialMaterial.new()
		m.albedo_color = {"ammo": Color("#c9b27c"), "health": Color("#ff5689"), "suit": Color("#66dfda"),
			"scrap": Color("#ffc365"), "airdrop": Color("#6a7f5a"), "station": Color("#2e5f6a")}.get(kind, Color("#e8e9d5"))
		mi.material_override = m
		mi.translation.y = c.size.y * 0.5
		n = mi
	holder.add_child(n)
	RetroMat.prepare(n)
	return holder


# ------------------------------------------------------------------ events
func _on_events(list: Array) -> void:
	var _t = OS.get_ticks_usec()
	_on_events_body(list)
	Settings.prof_add("w_events", OS.get_ticks_usec() - _t)


func _on_events_body(list: Array) -> void:
	for ev in list:
		if not (ev is Dictionary):
			continue
		Settings.spike_ctx.append(str(ev.get("e", "")) + (":" + str(ev.get("name", ev.get("text", ""))) if ev.has("name") or ev.has("text") else ""))
		match str(ev.get("e", "")):
			"shot":
				_on_shot(ev)
			"hit":
				var at = _v(ev.get("at"))
				fx.spark(at, Color(0.62, 1.0, 0.35) if not bool(ev.get("head", false)) else Color(1.0, 0.85, 0.4))
				emit_signal("hit_marker", false, bool(ev.get("head", false)))
				var near = _nearest_enemy(at, 2.0)
				if near:
					near.hurt(bool(ev.get("head", false)))
				Sound.play("headshot" if bool(ev.get("head", false)) else "hit_enemy", -6.0)
			"kill":
				emit_signal("hit_marker", true, false)
				emit_signal("killed", str(ev.get("type", "")))
				var actor = enemies.get(ev.get("enemy"))
				if actor and is_instance_valid(actor):
					actor.kill()
					fx.spark(actor.translation + Vector3(0, 1.0, 0), Color(0.55, 1.0, 0.3), 1.4)
					enemies.erase(ev.get("enemy"))
			"hurt":
				var d = ev.get("dir")
				emit_signal("hurt", _v(d) if d is Array else null, float(ev.get("amt", 0.0)))
				shake = min(1.0, shake + float(ev.get("amt", 5.0)) / 25.0)
			"lightning":
				weather.strike(_v(ev.get("at")))
				glitch = max(glitch, Settings.flash_scale())
			"sound":
				_on_sound(ev)
			"banner":
				emit_signal("banner", str(ev.get("text", "")))
			"puddle":
				weather.puddle(ev)
			"pickup":
				emit_signal("picked", str(ev.get("item", "")))


func _on_shot(ev: Dictionary) -> void:
	var from = _v(ev.get("from"))
	var to = _v(ev.get("to"))
	var meta = Assets.weapon(str(ev.get("weapon", "")))
	var color: Color = Color(meta.get("tracer_color")) if meta.get("tracer_color") is String else Color(1.0, 0.85, 0.5)
	if ev.get("by") == Net.you or (ev.get("by") == you.get("id") and you.has("id")):
		# Local feedback already played when FIRE went down; draw the tracer
		# from the viewmodel muzzle so it lines up on screen.
		var muzzle: Vector3 = viewmodel.muzzle_position()
		fx.tracer(muzzle, to, color)
		if OS.get_ticks_msec() - _last_local_shot > 250:
			viewmodel.fire()
			fx.flash(muzzle, 0.35, color.lightened(0.3))
	else:
		fx.tracer(from, to, color)
		fx.flash(from, 0.45, color.lightened(0.3))


func _on_sound(ev: Dictionary) -> void:
	var name = str(ev.get("name", ""))
	# Our own gunshot was already played locally on the button press.
	if name == _shot_cue and OS.get_ticks_msec() - _shot_cue_ms < 450:
		_shot_cue = ""
		return
	if ev.get("at") is Array:
		Sound.play_at(name, _v(ev.at))
	else:
		Sound.play(name)


func _nearest_enemy(at: Vector3, radius: float):
	var best = null
	var bd = radius * radius
	for a in enemies.values():
		if is_instance_valid(a):
			var d: float = (a.translation + Vector3(0, 1, 0)).distance_squared_to(at)
			if d < bd:
				bd = d
				best = a
	return best


# ------------------------------------------------------------------ frame
func current_slot() -> Dictionary:
	var slots = you.get("slots")
	var i = int(you.get("slot", 1)) - 1
	if slots is Array and i >= 0 and i < slots.size() and slots[i] is Dictionary:
		return slots[i]
	return {}


func _process(delta: float) -> void:
	var _pt = OS.get_ticks_usec()
	_process_body(delta)
	Settings.prof_add("world", OS.get_ticks_usec() - _pt)


func _process_body(delta: float) -> void:
	_anim_time += delta
	if loading:
		_step_load()
		return
	if level == null:
		return
	var _t = OS.get_ticks_usec()
	_sync_entities()
	Settings.prof_add("w_sync", OS.get_ticks_usec() - _t)
	for id in pickup_nodes:
		var n = pickup_nodes[id]
		if is_instance_valid(n) and n.get_meta("spin"):
			n.rotation.y = _anim_time * 1.6 + float(hash(id) % 10)
			n.get_child(0).translation.y = 0.25 + sin(_anim_time * 2.0 + float(hash(id) % 7)) * 0.06
	_update_camera(delta)
	_t = OS.get_ticks_usec()
	weather.update(delta, weather_state)
	Settings.prof_add("w_weather", OS.get_ticks_usec() - _t)
	_update_decon()
	var downed = str(you.get("state", "ok")) == "downed"
	glitch = max(move_toward(glitch, 0.0, delta * 1.6), 0.45 * Settings.flash_scale() if downed else 0.0)
	var mat = post_rect.material as ShaderMaterial
	if mat:
		mat.set_shader_param("glitch", glitch)
	_local_fire()
	_send_left -= delta
	if _send_left <= 0.0:
		_send_left += 1.0 / SEND_HZ
		if _send_left < 0.0:
			_send_left = 1.0 / SEND_HZ
		_send_input()


func _update_camera(delta: float) -> void:
	var state = str(you.get("state", "ok"))
	var pos = _v(you.get("pos"))
	var vel = _v(you.get("vel"))
	var age: float = clamp((OS.get_ticks_msec() - _snap_local_ms) / 1000.0, 0.0, 0.1)
	var target = pos + vel * age
	if not _cam_init:
		_cam_pos = target
		_cam_init = true
	elif _cam_pos.distance_to(target) > 4.0:
		_cam_pos = target
	else:
		_cam_pos = _cam_pos.linear_interpolate(target, 1.0 - exp(-18.0 * delta))
	var eye = EYE_CROUCH if bool(you.get("crouch", false)) else EYE
	if state == "downed":
		eye = 0.55
	var basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var origin = _cam_pos + Vector3(0, eye, 0)
	if state == "out" and not others.empty():
		# Spectate the first teammate still in the fight.
		for o in others:
			if o.state in ["ok", "downed"]:
				var look = Basis(Vector3.UP, yaw)
				origin = o.pos + Vector3(0, 2.6, 0) + look.z * 4.0
				basis = look * Basis(Vector3.RIGHT, -0.3)
				break
	shake = max(0.0, shake - delta * 3.0)
	if shake > 0.0 and not Settings.reduced_flash:
		origin += Vector3(rand_range(-1, 1), rand_range(-1, 1), 0) * shake * 0.03
	if _fixed_cam.size() == 5:  # test switch --cam=x,y,z,yaw,pitch (A/B screenshots)
		basis = Basis(Vector3.UP, _fixed_cam[3]) * Basis(Vector3.RIGHT, _fixed_cam[4])
		origin = Vector3(_fixed_cam[0], _fixed_cam[1], _fixed_cam[2])
	camera.global_transform = Transform(basis, origin)
	# FOV: hip, sprint +6, ADS from weapons.json.
	var item = current_slot()
	var meta = Assets.weapon(str(item.get("item", "")))
	var aiming = bool(you.get("aiming", false)) or (held_bits & BITS.aim) != 0
	var sprinting = (held_bits & BITS.sprint) != 0 and vel.length() > 5.5
	var want = HIP_FOV + (6.0 if sprinting else 0.0)
	if aiming and meta.get("ads_fov") != null:
		want = float(meta.ads_fov)
	_fov = lerp(_fov, want, 1.0 - exp(-12.0 * delta))
	camera.fov = _fov
	viewmodel.visible = state == "ok" and not item.empty()
	viewmodel.set_item(item.get("item"))
	viewmodel.aim = lerp(viewmodel.aim, 1.0 if aiming else 0.0, 1.0 - exp(-14.0 * delta))
	viewmodel.reloading = bool(you.get("reloading", false))
	viewmodel.speed = Vector2(vel.x, vel.z).length()


func _update_decon() -> void:
	var count = int(run.get("shared_decon", 4))
	for pair in _decon_cells:
		if is_instance_valid(pair[1]):
			pair[1].visible = pair[0] < count


## Immediate fire feedback (the original's owning-client muzzle + recoil).
func _local_fire() -> void:
	var down = ((held_bits | auto_bits) & BITS.fire) != 0
	var pressed = down and not _prev_fire
	_prev_fire = down
	if not down or str(you.get("state", "ok")) != "ok":
		return
	var item = current_slot()
	if item.empty() or item.get("ammo") == null or int(item.get("ammo", 0)) <= 0 or bool(you.get("reloading", false)):
		return
	var meta = Assets.weapon(str(item.get("item", "")))
	var auto = bool(meta.get("automatic", false))
	var interval = int(float(meta.get("fire_interval", 0.3)) * 1000.0)
	var now = OS.get_ticks_msec()
	if (pressed or auto) and now - _last_local_shot >= interval:
		_last_local_shot = now
		viewmodel.fire()
		fx.flash(viewmodel.muzzle_position(), 0.35, viewmodel.tracer_color().lightened(0.3))
		var cue = str(meta.get("shot_sound", ""))
		if not cue.empty():
			Sound.play(cue)
			_shot_cue = cue
			_shot_cue_ms = now


# ------------------------------------------------------------------ input
func look(delta_px: Vector2, scale: float) -> void:
	yaw -= delta_px.x * scale
	pitch = clamp(pitch - delta_px.y * scale * (-1.0 if Settings.invert_y else 1.0), -MAX_PITCH, MAX_PITCH)
	yaw = wrapf(yaw, -PI, PI)


func press_bits(bits: int) -> void:
	_latched_bits |= bits


func select_slot(n: int) -> void:
	_slot_pulse = n
	_slot_frames = 3


func wheel(d: int) -> void:
	_wheel = d


func _send_input() -> void:
	if Net.state != "run" or not look_ready:
		return
	_seq += 1
	var bits = held_bits | auto_bits | _latched_bits
	_latched_bits = 0
	var slot = 0
	if _slot_frames > 0:
		slot = _slot_pulse
		_slot_frames -= 1
	var mv = (move + auto_move).limit_length(1.0)
	Net.send({"t": "in", "seq": _seq, "mv": [stepify(mv.x, 0.01), stepify(mv.y, 0.01)],
		"yaw": stepify(yaw, 0.001), "pitch": stepify(pitch, 0.001), "b": bits, "slot": slot, "wheel": _wheel})
	_wheel = 0


## Damage / acid edge tints, drawn by the post pass (low resolution).
func set_edge_tints(hurt: float, acid: float) -> void:
	for m in [_post_retro, _post_clean]:
		m.set_shader_param("hurt", hurt)
		m.set_shader_param("acid", acid)


## Screen position (UI space) of a world point, or null when behind.
func to_screen(p: Vector3, ui_size: Vector2):
	if camera.is_position_behind(p):
		return null
	var v = camera.unproject_position(p)
	return v / viewport.size * ui_size
