extends Node
## Unified input (autoload `Controls`): keyboard + mouse, gamepad, and the
## on-screen touch controls feed one set of actions. Gameplay code (Thin and
## Full) reads ONLY this API, never Input/InputEvent directly.
##
## API (stable contract):
##   move_vector() -> Vector2   x = strafe right (+), y = forward (+), length <= 1
##   take_look() -> Vector2     yaw (+ = turn right), pitch (+ = look up) in RADIANS
##                              accumulated since the last call; call once per frame.
##                              Sensitivity per device and invert Y are applied.
##   held(action) -> bool       action currently down
##   pressed(action) -> bool    went down since the last consume_frame()
##   consume_frame()            called once per frame by main.gd after gameplay reads.
##                              Until something calls it, presses expire on their own
##                              after the frame they arrived in.
##   device -> String           "touch" | "kbm" | "pad" (last device used; HUD hints)
##   capture_mouse(on: bool)    pointer lock for mouse look (desktop; no-op on touch)
## signal device_changed(device)
##
## Additions:
##   signal menu_action(action)  menu_* presses incl. stick / held d-pad repeats
##                               (ui/focus_nav.gd listens to it)
##   menu_action_for(event) -> String   menu_* action an InputEvent maps to, or ""
##   eat(action)                 drop a press so later readers don't see it
##   hint(action) -> String      key / button label for the current device
##   accepts_touch() -> bool     the screen is a real touchscreen (or --touch)
##   observe(event)              device detection for an event a node handled first
##   sensitivity(device) -> float  look multiplier from Settings for that device
##   set_device(d)               switch device (touch layer calls this)
##   touch_hold(action, down) / touch_press(action) / touch_move(v) / touch_look(px, k)
##                               on-screen controls (ui/touch.gd) feed these
##
## Actions: fire, aim, reload, jump, crouch, sprint, interact, use_item (tarp
##   toggle, the native game's use_item), tarp (alias of use_item), throw_grenade,
##   throw_dome, drop_item, next_weapon, prev_weapon, slot_1..slot_5, ping,
##   ready_up, pause, scoreboard, inventory, draft_1, draft_2, draft_3,
##   menu_up, menu_down, menu_left, menu_right, menu_accept, menu_back

signal device_changed(device)
signal menu_action(action)

const ACTIONS = ["fire", "aim", "reload", "jump", "crouch", "sprint", "interact", "use_item", "tarp",
	"throw_grenade", "throw_dome", "drop_item", "next_weapon", "prev_weapon",
	"slot_1", "slot_2", "slot_3", "slot_4", "slot_5", "ping", "ready_up", "pause", "scoreboard",
	"inventory", "draft_1", "draft_2", "draft_3",
	"menu_up", "menu_down", "menu_left", "menu_right", "menu_accept", "menu_back"]
const MENU = ["menu_up", "menu_down", "menu_left", "menu_right", "menu_accept", "menu_back"]

# Keyboard + mouse, mirroring the native game's project.godot input map.
const KEYS = {
	"reload": [KEY_R], "jump": [KEY_SPACE], "crouch": [KEY_CONTROL, KEY_C], "sprint": [KEY_SHIFT],
	"interact": [KEY_E], "use_item": [KEY_T], "tarp": [KEY_T], "throw_grenade": [KEY_Q],
	"throw_dome": [KEY_F], "drop_item": [KEY_G], "ping": [KEY_Z], "ready_up": [KEY_H],
	"slot_1": [KEY_1], "slot_2": [KEY_2], "slot_3": [KEY_3], "slot_4": [KEY_4], "slot_5": [KEY_5],
	"draft_1": [KEY_1, KEY_KP_1], "draft_2": [KEY_2, KEY_KP_2], "draft_3": [KEY_3, KEY_KP_3],
	"pause": [KEY_ESCAPE], "scoreboard": [KEY_TAB], "inventory": [KEY_I],
	"menu_up": [KEY_UP], "menu_down": [KEY_DOWN], "menu_left": [KEY_LEFT], "menu_right": [KEY_RIGHT],
	"menu_accept": [KEY_ENTER, KEY_KP_ENTER], "menu_back": [KEY_ESCAPE],
}
const MOVE_KEYS = {"fwd": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT]}
const MOUSE = {"fire": [BUTTON_LEFT], "aim": [BUTTON_RIGHT], "ping": [BUTTON_MIDDLE],
	"next_weapon": [BUTTON_WHEEL_DOWN], "prev_weapon": [BUTTON_WHEEL_UP]}
# Gamepad (Godot 3 SDL layout: 0 A, 1 B, 2 X, 3 Y, 4 LB, 5 RB, 6 L2, 7 R2,
# 8 L3, 9 R3, 10 Back, 11 Start, 12-15 d-pad up/down/left/right). Triggers
# are analog axes on most pads; some Android pads send them as buttons 6/7.
const PAD = {
	"jump": [JOY_XBOX_A], "crouch": [JOY_XBOX_B], "reload": [JOY_XBOX_X], "interact": [JOY_XBOX_Y],
	"prev_weapon": [JOY_L], "next_weapon": [JOY_R], "aim": [JOY_L2], "fire": [JOY_R2],
	"sprint": [JOY_L3], "drop_item": [JOY_R3], "ready_up": [JOY_SELECT], "scoreboard": [JOY_SELECT],
	"pause": [JOY_START], "use_item": [JOY_DPAD_UP], "tarp": [JOY_DPAD_UP], "ping": [JOY_DPAD_DOWN],
	"throw_grenade": [JOY_DPAD_LEFT], "throw_dome": [JOY_DPAD_RIGHT],
	"menu_up": [JOY_DPAD_UP], "menu_down": [JOY_DPAD_DOWN], "menu_left": [JOY_DPAD_LEFT],
	"menu_right": [JOY_DPAD_RIGHT], "menu_accept": [JOY_XBOX_A], "menu_back": [JOY_XBOX_B],
}
const TRIGGERS = {"aim": JOY_ANALOG_L2, "fire": JOY_ANALOG_R2}

const MOUSE_LOOK = 0.0025        # rad per mouse pixel at sensitivity 1 (native default)
const TOUCH_LOOK = 0.0042        # rad per UI pixel at sensitivity 1
const PAD_LOOK = 3.0             # rad/s at full right-stick deflection (native pad_look_speed)
const STICK_DEADZONE = 0.2       # radial, matches the native input map
const LOOK_CURVE = 1.6           # response exponent on the look stick (fine aim near centre)
const MOVE_CURVE = 1.0
const TRIGGER_ON = 0.45
const TRIGGER_OFF = 0.25
const MENU_REPEAT_DELAY = 0.38
const MENU_REPEAT = 0.11

var device = "kbm"

var _pressed = {}               # action -> idle frame it arrived on
var _manual = false             # someone calls consume_frame()
var _look = Vector2.ZERO
var _pads = []
var _trigger = {}
var _sprint_latch = false
var _touch_held = {}
var _touch_move = Vector2.ZERO
var _menu_dir = ""
var _menu_left = 0.0
var _force_touch = false
## Tests only: treat the mouse as captured (headless runs can't lock the pointer).
var assume_captured = false


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	_force_touch = "--touch" in OS.get_cmdline_args()
	device = "touch" if accepts_touch() else "kbm"
	_pads = Input.get_connected_joypads()
	Input.connect("joy_connection_changed", self, "_on_joy_connection")
	if not _pads.empty():
		print("CONTROLS pads=%s %s" % [str(_pads), Input.get_joy_name(_pads[0])])


# ------------------------------------------------------------------ queries

func move_vector() -> Vector2:
	var v = Vector2(
		float(_any_key(MOVE_KEYS.right)) - float(_any_key(MOVE_KEYS.left)),
		float(_any_key(MOVE_KEYS.fwd)) - float(_any_key(MOVE_KEYS.back)))
	v = v.normalized() if v.length() > 1.0 else v
	var s = _stick(JOY_AXIS_0, JOY_AXIS_1, MOVE_CURVE)
	v += Vector2(s.x, -s.y)
	v += _touch_move
	return v.limit_length(1.0)


func take_look() -> Vector2:
	var l = _look
	_look = Vector2.ZERO
	return l


func held(action: String) -> bool:
	if _touch_held.get(action, false):
		return true
	if action == "sprint" and _sprint_latch:
		return true
	if _mouse_ok():
		for b in MOUSE.get(action, []):
			if b < BUTTON_WHEEL_UP and Input.is_mouse_button_pressed(b):
				return true
	for k in KEYS.get(action, []):
		if Input.is_key_pressed(k):
			return true
	for p in _pads:
		for b in PAD.get(action, []):
			if Input.is_joy_button_pressed(p, b):
				return true
	return _trigger.get(action, false)


func pressed(action: String) -> bool:
	return _pressed.has(action)


func consume_frame() -> void:
	_manual = true
	_pressed.clear()


func eat(action: String) -> void:
	_pressed.erase(action)


func capture_mouse(on: bool) -> void:
	if on and (device == "touch" or OS.has_feature("mobile")):
		return
	var want = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	if Input.get_mouse_mode() != want:
		Input.set_mouse_mode(want)


func accepts_touch() -> bool:
	return _force_touch or OS.has_touchscreen_ui_hint() or OS.has_feature("mobile")


func set_device(d: String) -> void:
	if d == device:
		return
	device = d
	if d != "touch":
		_touch_held.clear()
		_touch_move = Vector2.ZERO
	emit_signal("device_changed", d)


## Look sensitivity multiplier for a device ("kbm", "pad", "touch").
func sensitivity(d: String) -> float:
	match d:
		"kbm":
			return float(Settings.mouse_sensitivity)
		"pad":
			return float(Settings.pad_sensitivity)
	return float(Settings.look_sensitivity)


## Key / button label for `action` on the current device (HUD prompts).
func hint(action: String) -> String:
	if device == "pad":
		var names = {JOY_XBOX_A: "A", JOY_XBOX_B: "B", JOY_XBOX_X: "X", JOY_XBOX_Y: "Y", JOY_L: "LB", JOY_R: "RB",
			JOY_L2: "LT", JOY_R2: "RT", JOY_L3: "L3", JOY_R3: "R3", JOY_SELECT: "BACK", JOY_START: "START",
			JOY_DPAD_UP: "D-UP", JOY_DPAD_DOWN: "D-DOWN", JOY_DPAD_LEFT: "D-LEFT", JOY_DPAD_RIGHT: "D-RIGHT"}
		var b = PAD.get(action, [])
		return names.get(b[0], "") if not b.empty() else ""
	if device == "kbm":
		var m = MOUSE.get(action, [])
		if not m.empty():
			return {BUTTON_LEFT: "LMB", BUTTON_RIGHT: "RMB", BUTTON_MIDDLE: "MMB", BUTTON_WHEEL_UP: "WHEEL",
				BUTTON_WHEEL_DOWN: "WHEEL"}.get(m[0], "")
		var k = KEYS.get(action, [])
		return OS.get_scancode_string(k[0]).to_upper() if not k.empty() else ""
	return ""


## menu_* action an event maps to ("" if none). Key echoes count (repeat).
func menu_action_for(event: InputEvent) -> String:
	if event is InputEventKey and event.pressed:
		for a in MENU:
			if event.scancode in KEYS.get(a, []):
				return a
	elif event is InputEventJoypadButton and event.pressed:
		for a in MENU:
			if event.button_index in PAD.get(a, []):
				return a
	return ""


# ------------------------------------------------------------------ touch feed

func touch_hold(action: String, down: bool) -> void:
	if down:
		if not _touch_held.get(action, false):
			_press(action)
		_touch_held[action] = true
	else:
		_touch_held.erase(action)


func touch_press(action: String) -> void:
	_press(action)


## v: x = strafe right, y = forward (+), length <= 1.
func touch_move(v: Vector2) -> void:
	_touch_move = v.limit_length(1.0)


## A look drag of `delta_px` UI pixels; `k` scales it (e.g. 0.6 while aiming).
func touch_look(delta_px: Vector2, k := 1.0) -> void:
	_add_look(delta_px * TOUCH_LOOK * sensitivity("touch") * k)


# ------------------------------------------------------------------ events

## Device detection only (for nodes that handle an event before Controls sees it).
func observe(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		set_device("kbm")
	elif event is InputEventJoypadButton and event.pressed:
		set_device("pad")
	elif event is InputEventJoypadMotion and abs(event.axis_value) > 0.5:
		set_device("pad")
	elif (event is InputEventScreenTouch or event is InputEventScreenDrag) and accepts_touch():
		set_device("touch")


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo:
			set_device("kbm")
			for a in KEYS:
				if event.scancode in KEYS[a]:
					_press(a)
		var m = menu_action_for(event)
		if not m.empty():
			emit_signal("menu_action", m)
	elif event is InputEventMouseMotion:
		if event.device >= 0 and _mouse_ok():
			set_device("kbm")
			_add_look(event.relative * MOUSE_LOOK * sensitivity("kbm"))
	elif event is InputEventMouseButton:
		if event.device < 0 or not event.pressed:
			return  # -1 = emulated from a touch
		if _mouse_ok():
			set_device("kbm")
			for a in MOUSE:
				if event.button_index in MOUSE[a]:
					_press(a)
	elif event is InputEventJoypadButton:
		if not event.device in _pads:
			_pads.append(event.device)
		if event.pressed:
			set_device("pad")
			for a in PAD:
				if event.button_index in PAD[a]:
					_press(a)
			if event.button_index == JOY_L3:
				_sprint_latch = not _sprint_latch
			var m = menu_action_for(event)
			if not m.empty():
				emit_signal("menu_action", m)
				_menu_dir = m if m in ["menu_up", "menu_down", "menu_left", "menu_right"] else ""
				_menu_left = MENU_REPEAT_DELAY
	elif event is InputEventJoypadMotion:
		if abs(event.axis_value) > 0.5:
			if not event.device in _pads:
				_pads.append(event.device)
			set_device("pad")
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		if accepts_touch() and event.device >= 0:
			set_device("touch")


func _process(delta: float) -> void:
	var frame = Engine.get_idle_frames()
	if not _manual:
		for a in _pressed.keys():
			if _pressed[a] < frame:
				_pressed.erase(a)
	if _pads.empty():
		return
	# Right stick -> look (radial deadzone + response curve).
	var r = _stick(JOY_AXIS_2, JOY_AXIS_3, LOOK_CURVE)
	if r != Vector2.ZERO:
		_add_look(r * PAD_LOOK * sensitivity("pad") * delta)
	# Analog triggers -> fire / aim with hysteresis.
	for a in TRIGGERS:
		var v = 0.0
		for p in _pads:
			v = max(v, Input.get_joy_axis(p, TRIGGERS[a]))
		var was = _trigger.get(a, false)
		var now = v > (TRIGGER_OFF if was else TRIGGER_ON)
		if now and not was:
			_press(a)
			set_device("pad")
		_trigger[a] = now
	# Sprint latch ends when the stick drops or points backwards.
	if _sprint_latch:
		var m = _stick(JOY_AXIS_0, JOY_AXIS_1, 1.0)
		if m.length() < 0.3 or m.y > 0.3:
			_sprint_latch = false
	# Left stick / held d-pad -> repeating menu directions.
	var dir = ""
	var l = _stick(JOY_AXIS_0, JOY_AXIS_1, 1.0)
	if l.length() > 0.6:
		if abs(l.x) > abs(l.y):
			dir = "menu_right" if l.x > 0 else "menu_left"
		else:
			dir = "menu_down" if l.y > 0 else "menu_up"
	else:
		for a in ["menu_up", "menu_down", "menu_left", "menu_right"]:
			if held(a) and not _any_key(KEYS[a]):
				dir = a
	if dir.empty():
		_menu_dir = ""
	elif dir != _menu_dir:
		_menu_dir = dir
		_menu_left = MENU_REPEAT_DELAY
		if l.length() > 0.6:  # d-pad already emitted its first press as an event
			_press(dir)
			emit_signal("menu_action", dir)
	else:
		_menu_left -= delta
		if _menu_left <= 0.0:
			_menu_left = MENU_REPEAT
			_press(dir)
			emit_signal("menu_action", dir)


# ------------------------------------------------------------------ helpers

func _press(action: String) -> void:
	_pressed[action] = Engine.get_idle_frames()


func _add_look(rad: Vector2) -> void:
	# Screen-space delta (x right, y down) -> yaw right +, pitch up +.
	var pitch = -rad.y
	if Settings.invert_y:
		pitch = -pitch
	_look += Vector2(rad.x, pitch)


func _mouse_ok() -> bool:
	return assume_captured or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


func _any_key(keys: Array) -> bool:
	for k in keys:
		if Input.is_key_pressed(k):
			return true
	return false


## Strongest stick of all pads, radial deadzone rescaled to 0..1, then curved.
func _stick(ax: int, ay: int, curve: float) -> Vector2:
	var best = Vector2.ZERO
	for p in _pads:
		var v = Vector2(Input.get_joy_axis(p, ax), Input.get_joy_axis(p, ay))
		if v.length() > best.length():
			best = v
	var n = best.length()
	if n <= STICK_DEADZONE:
		return Vector2.ZERO
	var k = pow(min(1.0, (n - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)), curve)
	return best / n * k


func _on_joy_connection(id: int, connected: bool) -> void:
	if connected and not id in _pads:
		_pads.append(id)
	elif not connected:
		_pads.erase(id)
		_trigger.clear()
		_sprint_latch = false
		if device == "pad" and _pads.empty():
			set_device("touch" if accepts_touch() else "kbm")
	print("CONTROLS pad %d %s (%s)" % [id, "connected" if connected else "removed", Input.get_joy_name(id)])
