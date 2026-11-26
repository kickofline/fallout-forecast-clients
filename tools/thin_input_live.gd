extends SceneTree
## Live Thin check of the Controls input path: joins a Thin server, force-starts
## a short solo run only when the lobby is otherwise empty, then drives the
## player with synthetic keyboard + mouse and gamepad events and checks the
## server's snapshots respond (movement, yaw, firing). Leaves cleanly.
##
##   godot --path clients/car --no-window -s ../../tools/thin_input_live.gd -- \
##     --url=wss://HOST/ --name=CarTest [--map=pinecrest]

var fails = 0
var main
var w
var url = ""
var callsign = "CarTest"
var map_id = "pinecrest"
var net
var controls


func _init():
	for a in OS.get_cmdline_args():
		if a.begins_with("--url="):
			url = a.substr(6)
		elif a.begins_with("--name="):
			callsign = a.substr(7)
		elif a.begins_with("--map="):
			map_id = a.substr(6)
	call_deferred("_run")


func _check(name: String, ok: bool, extra = "") -> void:
	print("LIVE %s %s %s" % ["ok  " if ok else "FAIL", name, str(extra)])
	if not ok:
		fails += 1


func _wait(sec: float):
	var t = OS.get_ticks_msec() + int(sec * 1000)
	while OS.get_ticks_msec() < t:
		yield(self, "idle_frame")


func _until(obj, cond: String, timeout: float):
	var t = OS.get_ticks_msec() + int(timeout * 1000)
	while OS.get_ticks_msec() < t:
		if obj.call(cond):
			return true
		yield(self, "idle_frame")
	return false


func _key(code: int, down: bool) -> void:
	var e = InputEventKey.new()
	e.scancode = code
	e.pressed = down
	Input.parse_input_event(e)


func _mouse_btn(b: int, down: bool) -> void:
	var e = InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)


func _mouse_move(rel: Vector2) -> void:
	var e = InputEventMouseMotion.new()
	e.relative = rel
	Input.parse_input_event(e)


func _pad_btn(b: int, down: bool) -> void:
	var e = InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)


func _axis(a: int, v: float) -> void:
	var e = InputEventJoypadMotion.new()
	e.device = 0
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)


func _in_lobby() -> bool:
	return net.state == "lobby"


func _in_run() -> bool:
	main = current_scene
	w = main.world if main else null
	return w != null and w.ready_to_play and net.state == "run" and w.look_ready


func _pos() -> Vector3:
	return w._v(w.you.get("pos"))


func _ammo() -> int:
	var s = w.current_slot()
	return int(s.get("ammo", -1)) if s.get("ammo") != null else -1


var _lobby = {}


func _on_lobby(d):
	_lobby = d


func _run():
	yield(self, "idle_frame")
	var Settings = root.get_node("Settings")
	controls = root.get_node("Controls")
	net = root.get_node("Net")
	var Controls = controls
	var Net = net
	Settings.player_name = callsign
	if not url.empty():
		Settings.server_url = url
	change_scene("res://main.tscn")
	yield(_wait(1.0), "completed")
	Net.connect("lobby_updated", self, "_on_lobby")
	Net.connect_to(Settings.server_url, callsign)
	var ok = yield(_until(self, "_in_lobby", 25.0), "completed")
	_check("joined lobby", ok, Net.state)
	if not ok:
		return _finish()
	yield(_wait(2.5), "completed")
	var players = _lobby.get("players", []) if _lobby.get("players") is Array else []
	print("LIVE lobby players=%d phase=%s" % [players.size(), str(_lobby.get("phase", ""))])
	if players.size() > 1:
		print("LIVE lobby not empty; not starting a run")
		return _finish()
	Net.lobby_action("vote", {"map": map_id})
	yield(_wait(0.5), "completed")
	Net.lobby_action("start")
	ok = yield(_until(self, "_in_run", 90.0), "completed")
	_check("run started", ok, Net.state)
	if not ok:
		return _finish()
	yield(_wait(2.0), "completed")
	Controls.assume_captured = true

	# --- keyboard + mouse
	var p0 = _pos()
	_key(KEY_W, true)
	yield(_wait(1.5), "completed")
	_key(KEY_W, false)
	yield(_wait(0.6), "completed")
	var moved = _pos().distance_to(p0)
	_check("kbm W moves (server)", moved > 3.0, "%.2f m" % moved)
	_check("device kbm", Controls.device == "kbm", Controls.device)
	var y0 = w.yaw
	for _i in 10:
		_mouse_move(Vector2(40, 0))
		yield(self, "idle_frame")
	yield(_wait(0.5), "completed")
	var dyaw = wrapf(w.yaw - y0, -PI, PI)
	_check("mouse right turns right (yaw -)", dyaw < -0.5, "%.3f rad (expect -1.0)" % dyaw)
	var srv_yaw = float(w.you.get("yaw", 0.0)) if w.you.get("yaw") != null else w.yaw
	_check("server yaw follows", abs(wrapf(srv_yaw - w.yaw, -PI, PI)) < 0.1, "srv=%.3f local=%.3f" % [srv_yaw, w.yaw])
	var a0 = _ammo()
	_mouse_btn(BUTTON_LEFT, true)
	yield(_wait(0.25), "completed")
	_mouse_btn(BUTTON_LEFT, false)
	yield(_wait(0.8), "completed")
	_check("LMB fires (server ammo)", a0 < 0 or _ammo() < a0, "%d -> %d" % [a0, _ammo()])
	_key(KEY_R, true)
	yield(_wait(0.2), "completed")
	_key(KEY_R, false)
	yield(_wait(0.3), "completed")
	_check("R reload (server)", bool(w.you.get("reloading", false)) or _ammo() >= a0, "reloading=%s ammo=%d" % [str(w.you.get("reloading")), _ammo()])
	yield(_wait(2.5), "completed")

	# --- gamepad
	p0 = _pos()
	_axis(JOY_AXIS_1, -1.0)
	yield(_wait(1.5), "completed")
	_axis(JOY_AXIS_1, 0.0)
	yield(_wait(0.6), "completed")
	moved = _pos().distance_to(p0)
	_check("pad stick moves (server)", moved > 3.0, "%.2f m" % moved)
	_check("device pad", Controls.device == "pad", Controls.device)
	y0 = w.yaw
	_axis(JOY_AXIS_2, -1.0)
	yield(_wait(0.5), "completed")
	_axis(JOY_AXIS_2, 0.0)
	yield(_wait(0.2), "completed")
	dyaw = wrapf(w.yaw - y0, -PI, PI)
	_check("right stick left turns left (yaw +)", dyaw > 0.5, "%.3f rad" % dyaw)
	a0 = _ammo()
	_axis(JOY_ANALOG_R2, 1.0)
	yield(_wait(0.25), "completed")
	_axis(JOY_ANALOG_R2, 0.0)
	yield(_wait(0.8), "completed")
	_check("RT fires (server ammo)", a0 < 0 or _ammo() < a0, "%d -> %d" % [a0, _ammo()])
	yield(_wait(0.5), "completed")
	var base = _pos().y
	_pad_btn(JOY_XBOX_A, true)
	yield(_wait(0.1), "completed")
	_pad_btn(JOY_XBOX_A, false)
	var top = base
	for _i in 60:
		yield(self, "idle_frame")
		top = max(top, _pos().y)
	_check("A jumps (server)", top - base > 0.3, "peak +%.2f m" % (top - base))
	_finish()


func _finish():
	controls.assume_captured = false
	net.leave()
	yield(_wait(1.5), "completed")
	print("LIVE done fails=%d state=%s" % [fails, net.state])
	quit(1 if fails else 0)
