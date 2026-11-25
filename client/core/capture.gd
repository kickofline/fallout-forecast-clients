extends Node
## Test harness: `--capture=<dir>` drives the app through title -> lobby ->
## run -> draft -> tape -> results against a (mock) bridge, saving PNGs and
## an FPS log. `--autopilot` alone just plays (turns to enemies, fires).
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
var _shot_index = 0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	for a in OS.get_cmdline_args():
		var s = str(a)
		if s.begins_with("--capture="):
			dir = s.substr(10)
	if dir.empty():
		dir = OS.get_user_data_dir() + "/captures"
	var d = Directory.new()
	d.make_dir_recursive(dir)
	Net.connect("draft", self, "_on_draft")
	Net.connect("tape", self, "_on_tape")
	print("CAPTURE dir=", dir)


func _process(delta: float) -> void:
	_t += delta
	_phase_t += delta
	_fps_acc += delta
	_frames += 1
	if _fps_acc >= 1.0:
		_fps_log.append([_phase, _frames / _fps_acc])
		_fps_acc = 0.0
		_frames = 0
	var main = get_parent()
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
				_go("run")
		"run":
			_autopilot(main)
			if _phase_t > 5.0:
				_shot("04-run")
			if _phase_t > 9.0:
				_shot("05-run-combat")
			var w = main.world
			if w and str(w.weather_state.get("phase", "")) in ["downpour", "acid_storm"] and not _shots.has("06-downpour"):
				if _phase_t > 2.0:
					_shot("06-downpour")
			if main._screen_kind == "results":
				_go("results")
		"draft":
			_autopilot(main)
			if _phase_t > 1.2 and _shot("07-draft"):
				pass
			if _phase_t > 2.5 and not _shots.has("draft-picked"):
				_shots["draft-picked"] = true
				Net.choose("mutation", 1)
				_go("run")
		"tape":
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
				_quit_after = 1.0
				_go("done")
	if _quit_after > 0.0:
		_quit_after -= delta
		if _quit_after <= 0.0 and "--exit-when-done" in OS.get_cmdline_args():
			get_tree().quit()


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_args():
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


func _autopilot(main: Node) -> void:
	var w = main.world
	if w == null or not w.ready_to_play:
		return
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
		if abs(wrapf(w.yaw - want_yaw, -PI, PI)) < 0.12:
			bits |= w.BITS.fire
		w.move = Vector2(0, 0)
	else:
		w.yaw += 0.004
		w.move = Vector2.ZERO
	var item: Dictionary = w.current_slot()
	if item.get("ammo") != null and int(item.ammo) == 0:
		bits |= w.BITS.reload
	w.held_bits = bits


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
