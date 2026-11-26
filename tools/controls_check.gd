extends SceneTree
## Headless check of core/controls.gd and ui/focus_nav.gd with synthetic
## keyboard, mouse, gamepad and touch input.
##   godot --path clients/car --no-window -s ../../tools/controls_check.gd

## Loaded at runtime: preloading would compile it before the autoloads exist.

var fails = 0
var C
var menu_events = []


func _init():
	call_deferred("_run")


func _check(name: String, ok: bool, extra = "") -> void:
	print("%s %s %s" % ["ok  " if ok else "FAIL", name, str(extra)])
	if not ok:
		fails += 1


func _key(code: int, down: bool) -> void:
	var e = InputEventKey.new()
	e.scancode = code
	e.pressed = down
	Input.parse_input_event(e)


func _btn(b: int, down: bool) -> void:
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


## Synthetic events flush at the start of the next frame, and Controls
## updates triggers / latches in its _process, so analog checks wait 2 frames.
func _frames(n := 1):
	for _i in n:
		yield(self, "idle_frame")


func _run():
	yield(self, "idle_frame")
	C = root.get_node("Controls")
	C.connect("menu_action", self, "_on_menu")
	var devs = []
	C.connect("device_changed", self, "_on_dev", [devs])

	# --- keyboard
	_key(KEY_W, true)
	_key(KEY_SPACE, true)
	yield(_frames(), "completed")
	_check("kbm device", C.device == "kbm", C.device)
	_check("W forward", C.move_vector().is_equal_approx(Vector2(0, 1)), C.move_vector())
	_check("space pressed+held jump", C.pressed("jump") and C.held("jump"))
	yield(_frames(2), "completed")
	_check("press expires without consume_frame", not C.pressed("jump") and C.held("jump"))
	_key(KEY_W, false)
	_key(KEY_SPACE, false)
	_key(KEY_D, true)
	_key(KEY_W, true)
	yield(_frames(), "completed")
	_check("diagonal normalised", abs(C.move_vector().length() - 1.0) < 0.01, C.move_vector())
	_key(KEY_D, false)
	_key(KEY_W, false)
	_key(KEY_1, true)
	yield(_frames(), "completed")
	_check("1 -> slot_1 and draft_1", C.pressed("slot_1") and C.pressed("draft_1"))
	_key(KEY_1, false)
	_key(KEY_DOWN, true)
	yield(_frames(), "completed")
	_check("arrow -> menu_down signal", "menu_down" in menu_events, menu_events)
	_key(KEY_DOWN, false)
	_check("hint kbm reload", C.hint("reload") == "R", C.hint("reload"))
	_check("mouse fire needs capture", not C.held("fire"))

	# --- gamepad
	menu_events.clear()
	_btn(JOY_XBOX_A, true)
	yield(_frames(), "completed")
	_check("pad device", C.device == "pad", C.device)
	_check("A -> jump", C.pressed("jump") and C.held("jump"))
	_check("hint pad jump", C.hint("jump") == "A", C.hint("jump"))
	_btn(JOY_XBOX_A, false)
	_axis(JOY_AXIS_0, 0.15)
	_axis(JOY_AXIS_1, 0.1)
	yield(_frames(), "completed")
	_check("radial deadzone", C.move_vector() == Vector2.ZERO, C.move_vector())
	_axis(JOY_AXIS_0, 0.0)
	_axis(JOY_AXIS_1, -1.0)
	yield(_frames(), "completed")
	_check("left stick forward", C.move_vector().is_equal_approx(Vector2(0, 1)), C.move_vector())
	_btn(JOY_L3, true)
	yield(_frames(), "completed")
	_btn(JOY_L3, false)
	yield(_frames(), "completed")
	_check("L3 latches sprint", C.held("sprint"))
	_axis(JOY_AXIS_1, 0.0)
	yield(_frames(2), "completed")
	_check("sprint latch ends with stick", not C.held("sprint"))
	C.take_look()
	_axis(JOY_AXIS_2, 1.0)
	var t0 = OS.get_ticks_usec()
	yield(_frames(10), "completed")
	var dt = (OS.get_ticks_usec() - t0) / 1000000.0
	var look = C.take_look()
	_check("right stick look ~3 rad/s", look.x > 0.0 and abs(look.x / dt - 3.0) < 1.2 and abs(look.y) < 0.001, "%.2f rad/s" % (look.x / dt))
	_axis(JOY_AXIS_2, 0.0)
	_axis(JOY_AXIS_3, -1.0)
	yield(_frames(3), "completed")
	look = C.take_look()
	_check("stick up = pitch up", look.y > 0.0, look)
	root.get_node("Settings").invert_y = true
	yield(_frames(3), "completed")
	look = C.take_look()
	_check("invert Y", look.y < 0.0, look)
	root.get_node("Settings").invert_y = false
	_axis(JOY_AXIS_3, 0.0)
	_axis(JOY_ANALOG_R2, 1.0)
	yield(_frames(2), "completed")
	_check("RT -> fire", C.pressed("fire") and C.held("fire"))
	_axis(JOY_ANALOG_R2, 0.3)
	yield(_frames(2), "completed")
	_check("RT hysteresis holds at 0.3", C.held("fire"))
	_axis(JOY_ANALOG_R2, 0.0)
	yield(_frames(2), "completed")
	_check("RT released", not C.held("fire"))
	menu_events.clear()
	_axis(JOY_AXIS_1, 1.0)
	yield(_frames(40), "completed")
	_axis(JOY_AXIS_1, 0.0)
	var downs = menu_events.count("menu_down")
	_check("left stick menu repeat", downs >= 2, menu_events)
	_btn(JOY_DPAD_RIGHT, true)
	yield(_frames(), "completed")
	_check("d-pad right -> throw_dome + menu_right", C.pressed("throw_dome") and "menu_right" in menu_events)
	_btn(JOY_DPAD_RIGHT, false)

	# --- touch feed
	C.set_device("touch")
	C.touch_move(Vector2(0.5, 0.5))
	C.touch_hold("fire", true)
	yield(_frames(), "completed")
	_check("touch move", C.move_vector().is_equal_approx(Vector2(0.5, 0.5)), C.move_vector())
	_check("touch hold fire", C.held("fire"))
	C.touch_look(Vector2(100, 0))
	look = C.take_look()
	_check("touch look right = yaw +", look.x > 0.0, look)
	C.touch_hold("fire", false)
	C.touch_move(Vector2.ZERO)
	_check("devices seen", "kbm" in devs and "pad" in devs and "touch" in devs, devs)

	# --- focus nav
	var screen = Control.new()
	screen.rect_size = Vector2(800, 600)
	root.add_child(screen)
	var buttons = []
	var hits = []
	for i in 3:
		var b = Button.new()
		b.text = "B%d" % i
		b.rect_position = Vector2(100, 100 + i * 80)
		b.rect_size = Vector2(200, 60)
		b.connect("pressed", self, "_on_hit", [hits, i])
		screen.add_child(b)
		buttons.append(b)
	var slider = HSlider.new()
	slider.rect_position = Vector2(400, 260)
	slider.rect_size = Vector2(200, 40)
	slider.min_value = 0
	slider.max_value = 10
	slider.step = 1
	slider.value = 5
	screen.add_child(slider)
	var nav = load("res://ui/focus_nav.gd").new().attach(screen)
	var backs = []
	nav.connect("back", self, "_on_back", [backs])
	yield(_frames(2), "completed")
	_key(KEY_DOWN, true)
	yield(_frames(), "completed")
	_key(KEY_DOWN, false)
	var f = screen.get_focus_owner()
	_check("focus_nav initial focus", f == buttons[0] or f == buttons[1], f)
	buttons[0].grab_focus()
	_key(KEY_DOWN, true)
	yield(_frames(), "completed")
	_key(KEY_DOWN, false)
	_check("focus_nav down", screen.get_focus_owner() == buttons[1], screen.get_focus_owner())
	_key(KEY_ENTER, true)
	yield(_frames(), "completed")
	_key(KEY_ENTER, false)
	_check("focus_nav accept once", hits == [1], hits)
	_btn(JOY_DPAD_RIGHT, true)
	yield(_frames(), "completed")
	_btn(JOY_DPAD_RIGHT, false)
	_check("focus_nav right -> slider", screen.get_focus_owner() == slider, screen.get_focus_owner())
	_btn(JOY_DPAD_RIGHT, true)
	yield(_frames(), "completed")
	_btn(JOY_DPAD_RIGHT, false)
	_check("focus_nav slider step", slider.value == 6, slider.value)
	_btn(JOY_XBOX_B, true)
	yield(_frames(), "completed")
	_btn(JOY_XBOX_B, false)
	_check("focus_nav back", backs.size() == 1, backs)
	print("CONTROLS_CHECK done fails=%d" % fails)
	quit(1 if fails else 0)


func _on_menu(a):
	menu_events.append(a)


func _on_dev(d, list):
	list.append(d)


func _on_hit(list, i):
	list.append(i)


func _on_back(list):
	list.append(1)
