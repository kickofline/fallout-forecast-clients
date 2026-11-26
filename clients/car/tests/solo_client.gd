extends SceneTree
## Drives the production title, menus, world and results using the solo link.
## godot --path clients/car --no-window --fixed-fps 60 -s res://tests/solo_client.gd

const MAPS = ["pinecrest", "harbor", "maple_hollow"]
const SIM_SPEED = 3.0
var _main
var _net
var _settings
var _maps = MAPS.duplicate()
var _map = ""
var _index = -1
var _stage = "title"
var _clock = 0.0
var _phase_when_paused = 0.0
var _paused_at = 0
var _vitals_when_paused = 0
var _origin = Vector3.ZERO
var _max_move = 0.0
var _shot = false
var _hit = false
var _hurt = false
var _paused = false
var _resumed = false
var _errors = []
var _results = {}


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	# START SOLO persists the selection, so keep the test profile isolated.
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Fallout Forecast Car Solo Test")
	if not OS.get_user_data_dir().ends_with("Fallout Forecast Car Solo Test"):
		_fail("could not isolate user settings")
		quit(1)
		return
	Engine.time_scale = SIM_SPEED
	_net = root.get_node("FullNet")
	_settings = root.get_node("Settings")
	_settings.starter_index = 2
	_settings.render_scale = 0.35
	_settings.retro_enabled = false
	_settings.particle_density = 0.0
	_settings.fog_quality = 0
	_net.connect("results", self, "_on_results")
	_net.connect("failed", self, "_fail")
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--solo-map=") and arg.substr(11) in MAPS:
			_maps = [arg.substr(11)]
	_main = load("res://main.tscn").instance()
	root.add_child(_main)
	_next()


func _next() -> void:
	_index += 1
	if _index == _maps.size():
		print("SOLO CLIENT errors=", _errors)
		quit(0 if _errors.empty() else 1)
		return
	_map = _maps[_index]
	_clock = 0.0
	_stage = "title"
	_max_move = 0.0
	_shot = false
	_hit = false
	_hurt = false
	_paused = false
	_resumed = false
	_results = {}


func _idle(dt: float) -> bool:
	if not is_instance_valid(_main) or _index >= _maps.size():
		return false
	_clock += dt
	if not _results.empty() and _main._screen_kind == "results":
		_finish_map()
		return false
	if _clock > 135.0:
		_fail("timed out in " + _stage)
		_finish_map()
		return false
	match _stage:
		"title":
			_start_from_title()
		"loading":
			var world = _main.world
			if is_instance_valid(world) and world.ready_to_play and world.starter_state == 2:
				_origin = world.me.feet()
				_stage = "pause"
				_main.hud.toggle_menu()
				_paused_at = OS.get_ticks_msec()
				_vitals_when_paused = -1
				_phase_when_paused = world.phase_left
		"pause":
			_check_pause()
		"run":
			_walk_and_fight()
	return false


func _start_from_title() -> void:
	if _main._screen_kind != "title":
		return
	var title = _main._screen
	for button in title._mode_row.get_children():
		if button.get_meta("mode") == "solo":
			button.emit_signal("pressed")
	for button in title._maps_row.get_children():
		if button.get_meta("map") == _map:
			button.emit_signal("pressed")
	title._connect.emit_signal("pressed")
	_stage = "loading"


func _check_pause() -> void:
	var world = _main.world
	var vitals = int(_net.rpc_in.get("_apply_vitals", 0))
	var echoes = int(_net.rpc_in.get("_sync_pause", 0))
	if echoes == 1 and _vitals_when_paused == -1:
		_vitals_when_paused = vitals
	if OS.get_ticks_msec() - _paused_at < 200 or echoes == 0:
		return
	if echoes == 1:
		_paused = vitals == _vitals_when_paused and world.phase_left == _phase_when_paused and not world.is_processing()
		_main.hud.toggle_menu()
		return
	_resumed = world.is_processing() and echoes == 2
	_stage = "run"
	_clock = 0.0


func _walk_and_fight() -> void:
	var world = _main.world
	if not is_instance_valid(world) or not world.ready_to_play:
		return
	if _clock > 1.0 and world.phase_id == 0 and world.phase_left > 3.1:
		world.press_bits(world.BITS.ready_up)
	var point = world.me.feet()
	_max_move = max(_max_move, point.distance_to(_origin))
	_hurt = _hurt or world.vit.hp < 99.0 or world.vit.suit < 99.0
	_shot = _shot or world.accepted_shots > 0
	_hit = _hit or int(_net.rpc_in.get("_receive_hits", 0)) > 0
	world.auto_move = Vector2(0, -1) if _clock < 2.1 else Vector2.ZERO
	world.auto_bits = 0
	if _clock < 20.0 and world.my_state == "ok":
		var closest = 35.0
		var eye = world._eye()
		for actor in world.enemies.values():
			if not is_instance_valid(actor) or actor.dying:
				continue
			var distance = point.distance_to(actor.translation)
			var head = 1.28 if actor.type == "gutter" else 1.54
			var target = actor.translation + Vector3.UP * head
			if distance < closest and world.space.intersect_ray(eye, target, [], 1).empty():
				closest = distance
				var aim = target - eye
				world.yaw = atan2(-aim.x, -aim.z)
				world.pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
		if (closest < 35.0 or _clock < 3.0) and int(_clock * 12.0) % 6 < 2:
			world.auto_bits = world.BITS.fire | world.BITS.aim



func _on_results(data: Dictionary) -> void:
	_results = data


func _finish_map() -> void:
	if _results.get("map") != _map or _main._screen_kind != "results":
		_fail("results screen or map id missing")
	if _max_move <= 1.0 or not _shot or not _hurt:
		_fail("expected movement, authoritative shot and damage")
	if not _paused or not _resumed:
		_fail("pause menu did not stop and resume the solo world")
	if _net.errors > 0:
		_fail("unexpected protocol errors")
	print("SOLO CLIENT ", _map, " results=", not _results.empty(), " waves=", _results.get("waves"),
		" kills=", _results.get("kills"), " moved=", "%.1f" % _max_move, " shot=", _shot, " hit=", _hit,
		" damage=", _hurt, " pause=", _paused and _resumed, " errors=", _net.errors)
	_net.leave()
	_main.back_to_lobby()
	_next()


func _fail(reason: String) -> void:
	_errors.append(_map + " " + reason)
	printerr("SOLO CLIENT ERROR ", _errors.back())
