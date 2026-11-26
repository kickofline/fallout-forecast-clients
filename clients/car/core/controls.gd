extends Node
## Unified input (autoload `Controls`): keyboard + mouse, gamepad, and the
## on-screen touch controls feed one set of actions. Gameplay code (Thin and
## Full) reads ONLY this API, never Input/InputEvent directly.
##
## OWNER: the input worker. This is a minimal working stub (keyboard only).
##
## API (stable contract):
##   move_vector() -> Vector2   x = strafe right (+), y = forward (+), length <= 1
##   take_look() -> Vector2     yaw (+ = turn right), pitch (+ = look up) in RADIANS
##                              accumulated since the last call; call once per frame
##   held(action) -> bool       action currently down
##   pressed(action) -> bool    went down since the last consume_frame()
##   consume_frame()            called once per frame by main.gd after gameplay reads
##   device -> String           "touch" | "kbm" | "pad" (last device used; HUD hints)
##   capture_mouse(on: bool)    pointer lock for mouse look (desktop)
## Actions: fire, aim, reload, jump, crouch, sprint, interact, use_item,
##   tarp, next_weapon, prev_weapon, slot_1, slot_2, slot_3, slot_4, ping,
##   pause, scoreboard, draft_1, draft_2, draft_3, menu_up, menu_down,
##   menu_left, menu_right, menu_accept, menu_back
## signal device_changed(device)

signal device_changed(device)

var device = "touch"
var _pressed = {}
var _look = Vector2.ZERO

const _KEYS = {
	"fire": KEY_SPACE, "reload": KEY_R, "jump": KEY_SPACE, "interact": KEY_E,
	"sprint": KEY_SHIFT, "crouch": KEY_CONTROL, "pause": KEY_ESCAPE,
}


func move_vector() -> Vector2:
	var v = Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)))
	return v.clamped(1.0)


func take_look() -> Vector2:
	var l = _look
	_look = Vector2.ZERO
	return l


func held(action: String) -> bool:
	return _KEYS.has(action) and Input.is_key_pressed(_KEYS[action])


func pressed(action: String) -> bool:
	return _pressed.has(action)


func consume_frame() -> void:
	_pressed.clear()


func capture_mouse(on: bool) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		for a in _KEYS:
			if _KEYS[a] == event.scancode:
				_pressed[a] = true
