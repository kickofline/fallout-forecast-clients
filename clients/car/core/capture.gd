extends Node
## Test harness: `--capture=<dir>` drives the app through title -> lobby ->
## run -> results, including draft/tape when offered, saving PNGs and FPS.
## Not used in normal play.

var dir = ""
var _t = 0.0
var _phase = "title"
var _phase_t = 0.0
var _shots = {}
var _fps_log = []
var _fps_acc = 0.0
var _frames = 0
var _quit_after = -1.0
var _last_frame_us = 0
var _spawn_frames = 0
var _spawn_peak_ms = 0.0
var _initial_enemies = []
var _move_until = 0.0
var _start_pos = null
var _move_distance = 0.0
var _start_ammo = -1
var _min_ammo = -1
var _server_shots = 0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	for a in Settings.args():
		var s = str(a)
		if s.begins_with("--capture="):
			dir = s.substr(10)
	if dir.empty():
		dir = OS.get_user_data_dir() + "/captures"
	var d = Directory.new()
	d.make_dir_recursive(dir)
	Net.connect("draft", self, "_on_draft")
	Net.connect("tape", self, "_on_tape")
	Net.connect("events", self, "_on_events")
	print("CAPTURE dir=", dir)


func _process(delta: float) -> void:
	_t += delta
	_phase_t += delta
	var now = OS.get_ticks_usec()
	var frame_seconds = (now - _last_frame_us) / 1000000.0 if _last_frame_us > 0 else delta
	_last_frame_us = now
	_fps_acc += frame_seconds
	_frames += 1
	if _fps_acc >= 1.0:
		_fps_log.append([_phase, _frames / _fps_acc])
		_fps_acc = 0.0
		_frames = 0
	var main = get_parent()
	if _phase in ["run", "draft", "tape"] and main._screen_kind == "results":
		_go("results")
	match _phase:
		"title":
			if _phase_t > 2.0 and _shot("01-title"):
				Net.connect_to(Settings.server_url, Settings.player_name)
				_go("connecting")
		"connecting":
			if Net.state == "lobby":
				_go("lobby")
		"lobby":
			if _phase_t > 2.0 and _shot("02-lobby"):
				Net.lobby_action("vote", {"map": _arg("map", "pinecrest")})
				Net.lobby_action("ready", {"v": true})
				_go("waiting")
		"waiting":
			if Net.state == "loading" or main._load_wait > 0:
				_go("loading")
		"loading":
			if _phase_t > 0.15:
				_shot("03-loading")
			if main.world and main.world.ready_to_play and Net.state == "run":
				_move_until = _t + 1.25
				_initial_enemies = main.world.enemies.keys()
				_go("run")
		"run":
			_autopilot(main)
			_sample_run(main.world, frame_seconds)
			if "--probe" in Settings.args():
				_probe(main)
			var limit = float(_arg("run-seconds", "0"))
			if limit > 0.0 and _phase_t > limit:
				_report_run()
				Net.leave()
				_quit_after = 1.0
				_go("done")
				return
			if _phase_t > 5.0:
				_shot("04-run")
			if _phase_t > 9.0:
				_shot("05-run-combat")
			var w = main.world
			if w and str(w.weather_state.get("phase", "")) in ["downpour", "acid_storm"] and not _shots.has("06-downpour"):
				if _phase_t > 2.0:
					_shot("06-downpour")
		"draft":
			_autopilot(main)
			if _phase_t > 1.2 and _shot("07-draft"):
				pass
			if _phase_t > 2.5 and not _shots.has("draft-picked"):
				_shots["draft-picked"] = true
				Net.choose("mutation", 1)
				_go("run")
		"tape":
			if main.world:
				main.world.auto_bits = 0
				main.world.auto_move = Vector2.ZERO
			if _shots.has("tape-picked"):
				_go("run")
				return
			if _phase_t > 1.2 and _shot("08-tape"):
				pass
			if _phase_t > 2.0 and not _shots.has("tape-picked"):
				_shots["tape-picked"] = true
				Net.choose("tape", 1)
				_go("run")
		"results":
			if _phase_t > 1.5 and _shot("09-results"):
				_write_fps()
				print("CAPTURE run distance=%.2fm ammo=%d->%d server_shot_events=%d" % [
					_move_distance, _start_ammo, _min_ammo, _server_shots])
				_quit_after = 1.0
				_go("done")
	if _quit_after > 0.0:
		_quit_after -= delta
		if _quit_after <= 0.0 and "--exit-when-done" in Settings.args():
			get_tree().quit()


var _run_fps = []
var _probe_i = -1
var _probe_frames = 0
var _probe_t0 = 0
const PROBES = ["base", "no_post", "no_weather", "no_hud", "no_3d", "no_world_proc", "no_hud_proc", "base2"]


## --probe: toggle one subsystem at a time for 5 s and log the frame rate.
func _probe(main: Node) -> void:
	var w = main.world
	if w == null or not w.ready_to_play:
		return
	var slot = int(floor((_phase_t - 3.0) / 5.0))
	if slot < 0:
		return
	_probe_frames += 1
	if slot != _probe_i:
		if _probe_i >= 0 and _probe_i < PROBES.size():
			var dt = (OS.get_ticks_msec() - _probe_t0) / 1000.0
			print("PROBE %s fps=%.1f" % [PROBES[_probe_i], (_probe_frames - 1) / max(dt, 0.001)])
			_probe_set(main, PROBES[_probe_i], false)
		_probe_i = slot
		_probe_frames = 0
		_probe_t0 = OS.get_ticks_msec() + 1000  # 1 s settle, frames counted after
		if slot < PROBES.size():
			_probe_set(main, PROBES[slot], true)
	if OS.get_ticks_msec() < _probe_t0:
		_probe_frames = 0


func _probe_set(main: Node, name: String, on: bool) -> void:
	var w = main.world
	match name:
		"no_post":
			w.display.material = null if on else (w._post_retro if Settings.retro_enabled else w._post_clean)
		"no_weather":
			w.weather.visible = not on
		"no_hud":
			main.hud.visible = not on
		"no_3d":
			w.viewport.render_target_update_mode = Viewport.UPDATE_DISABLED if on else Viewport.UPDATE_ALWAYS
		"no_world_proc":
			w.set_process(not on)
		"no_hud_proc":
			main.hud.set_process(not on)


## Per-second run frame rates (after a 3 s settle) for car perf comparisons.
func _report_run() -> void:
	var xs = []
	for row in _fps_log:
		if row[0] == "run":
			xs.append(row[1])
	if xs.size() > 3:
		xs = xs.slice(3, xs.size() - 1)
	if xs.empty():
		return
	var lo = 999.0
	var sum = 0.0
	for x in xs:
		lo = min(lo, x)
		sum += x
	print("CAPTURE run_fps map=%s avg=%.1f min=%.1f samples=%d" % [_arg("map", "pinecrest"), sum / xs.size(), lo, xs.size()])


func _arg(name: String, fallback: String) -> String:
	for a in Settings.args():
		if str(a).begins_with("--%s=" % name):
			return str(a).substr(name.length() + 3)
	return fallback


func _go(p: String) -> void:
	print("CAPTURE phase ", p, " t=", _t)
	_phase = p
	_phase_t = 0.0


func _on_draft(_d) -> void:
	_go("draft")


func _on_tape(_d) -> void:
	_go("tape")


func _on_events(events: Array) -> void:
	for ev in events:
		if ev is Dictionary and ev.get("e") == "shot" and ev.get("by") == Net.you:
			_server_shots += 1


func _sample_run(w: Node, frame_seconds: float) -> void:
	if w == null:
		return
	var pos: Vector3 = w._v(w.you.get("pos"))
	if _start_pos == null:
		_start_pos = pos
	_move_distance = max(_move_distance, pos.distance_to(_start_pos))
	var ammo = w.current_slot().get("ammo")
	if ammo != null:
		if _start_ammo < 0:
			_start_ammo = int(ammo)
			_min_ammo = _start_ammo
		_min_ammo = min(_min_ammo, int(ammo))
	if _spawn_frames == 0:
		for id in w.enemies:
			if not _initial_enemies.has(id):
				_spawn_frames = 5
				break
	if _spawn_frames > 0:
		_spawn_peak_ms = max(_spawn_peak_ms, frame_seconds * 1000.0)
		_spawn_frames -= 1
		if _spawn_frames == 0:
			print("CAPTURE first_live_spawn_peak_frame_ms=%.1f" % _spawn_peak_ms)
			_spawn_frames = -1


func _autopilot(main: Node) -> void:
	var w = main.world
	if w == null or not w.ready_to_play:
		return
	w.auto_move = Vector2(0, -0.75) if _t < _move_until else Vector2.ZERO
	var me: Vector3 = w._v(w.you.get("pos"))
	var best = null
	var bd = 1e9
	for e in w.enemy_points:
		var d: float = me.distance_squared_to(e[0])
		if d < bd:
			bd = d
			best = e[0]
	var bits = 0
	if best != null and bd < 30.0 * 30.0:
		var to: Vector3 = best + Vector3(0, 1.0, 0) - (me + Vector3(0, 1.65, 0))
		var want_yaw = atan2(-to.x, -to.z)
		var want_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		w.yaw = lerp_angle(w.yaw, want_yaw, 0.12)
		w.pitch = lerp(w.pitch, want_pitch, 0.12)
		# Hold a few input ticks and release between attempts for semi-auto guns.
		if abs(wrapf(w.yaw - want_yaw, -PI, PI)) < 0.2 and fmod(_t, 1.0) < 0.25:
			bits |= w.BITS.fire
	else:
		w.yaw += 0.004
	var item: Dictionary = w.current_slot()
	if item.get("ammo") != null and int(item.ammo) == 0:
		bits |= w.BITS.reload
	w.auto_bits = bits


func _shot(name: String) -> bool:
	if _shots.has(name):
		return true
	_shots[name] = true
	call_deferred("_save", name)
	return true


func _save(name: String) -> void:
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	var path = "%s/%s.png" % [dir, name]
	img.save_png(path)
	print("CAPTURE saved ", path, " fps=", Engine.get_frames_per_second())


func _write_fps() -> void:
	var f = File.new()
	if f.open(dir + "/fps.txt", File.WRITE) == OK:
		for row in _fps_log:
			f.store_line("%s %.1f" % [row[0], row[1]])
		f.close()
