extends Control
## Touch layer for the run. Each finger keeps the role it started with until
## lift (move stick, look, or a button), like the game's touch_controls.gd.
## Left: floating move stick (push past the rim = sprint). Right half: drag
## to look. Buttons: FIRE (hold, also drags look), AIM, JUMP, CROUCH, RELOAD,
## USE (when there is a prompt), ITEM, MENU, READY; hotbar cells select slots
## and pouches. Everything feeds the Controls autoload (touch_hold /
## touch_press / touch_move / touch_look); keyboard, mouse and gamepad come in
## through Controls directly. The layer only shows while Controls.device is
## "touch" (a real touchscreen, or --touch on desktop).
##
## Run-wide input glue also lives here because this node has both the world
## and the HUD: pause toggles the menu, draft_1..3 pick a mutation card, and
## the mouse is captured for mouse look while playing with keyboard + mouse.

const STICK_R = 78.0
const SPRINT_EDGE = 1.18
const LOOK_DEADZONE = 4.0

var world: Node
var hud: Node
var hotbar: Control

var _contacts = {}            # index -> role (String) or {"slot": n}
var _last = {}
var _start = {}
var _look_live = {}
var _stick_home = Vector2.ZERO
var _stick_center = Vector2.ZERO
var _stick_tip = Vector2.ZERO
var _buttons = {}
var _held = {}


func _ready() -> void:
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	connect("resized", self, "_layout")
	_layout()


func _layout() -> void:
	var W = rect_size.x if rect_size.x > 0 else 1240.0
	var H = rect_size.y if rect_size.y > 0 else 606.0
	var k = Settings.button_size
	_stick_home = Vector2(150, H - 150)
	if not ("move" in _contacts.values()):
		_stick_center = _stick_home
		_stick_tip = _stick_home
	_buttons = {
		"fire": Rect2(W - 20 - 150 * k, H - 85 - 130 * k, 150 * k, 130 * k),
		"jump": Rect2(W - 20 - 150 * k, H - 14 - 64 * k, 150 * k, 64 * k),
		"aim": Rect2(W - 30 - 270 * k, H - 85 - 85 * k, 120 * k, 85 * k),
		"crouch": Rect2(W - 30 - 270 * k, H - 14 - 64 * k, 120 * k, 64 * k),
		"reload": Rect2(W - 20 - 150 * k, H - 95 - 205 * k, 150 * k, 68 * k),
		"use_item": Rect2(W - 30 - 270 * k, H - 95 - 205 * k, 120 * k, 68 * k),
		"interact": Rect2(W - 40 - 390 * k, H - 85 - 85 * k, 120 * k, 85 * k),
		"menu": Rect2(W - 16 - 92, 12, 92, 50),
		"ready_up": Rect2(W - 30 - 92 - 130, 12, 130, 50),
	}
	update()


func button_rect(action: String) -> Rect2:
	return _buttons.get(action, Rect2())


func _visible(action: String) -> bool:
	var state = str(world.you.get("state", "ok")) if world else "ok"
	match action:
		"menu":
			return true
		"ready_up":
			return state == "ok" and world and str(world.weather_state.get("phase", "")) == "calm" \
				and float(world.weather_state.get("phase_time_left", 0.0)) > 6.0
		"interact":
			return state in ["ok", "downed"] and world and not str(world.you.get("prompt", "")).empty()
		"fire", "jump":
			return state in ["ok", "turned"]
		_:
			return state == "ok"


func _target(at: Vector2):
	for action in _buttons:
		if _visible(action) and (_buttons[action] as Rect2).grow(6).has_point(at):
			return action
	if hotbar and str(world.you.get("state", "ok")) == "ok":
		var cell: int = hotbar.cell_at(at)
		if cell >= 0:
			return {"slot": cell}
	return null


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or world == null or not Controls.accepts_touch():
		return
	if event is InputEventScreenTouch:
		if hud and hud.blocks_touch(event.position):
			return
		Controls.set_device("touch")
		if event.pressed:
			_begin(event.index, event.position)
		else:
			_end(event.index)
		get_tree().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if not _contacts.has(event.index):
			return
		var role = _contacts[event.index]
		if role is String and role == "move":
			_move_stick(event.position)
		elif role is String and (role == "look" or (role == "fire" and not ("look" in _contacts.values()))):
			_drag_look(event.index, event.position)
		get_tree().set_input_as_handled()


func _begin(index: int, at: Vector2) -> void:
	var role = _target(at)
	if role == null:
		if at.x < rect_size.x * 0.36 and at.y > rect_size.y * 0.3:
			role = "move"
			_stick_center = at
			_stick_tip = at
		elif at.x >= rect_size.x * 0.36:
			role = "look"
		else:
			return
	if role is Dictionary:
		var cell: int = role.slot
		if cell < 5:
			Controls.touch_press("slot_%d" % (cell + 1))
		elif cell == 5:
			Controls.touch_press("throw_grenade")
		else:
			Controls.touch_press("throw_dome")
		Sound.play("ui_tick", -10.0)
		return
	if role == "menu":
		Controls.touch_press("pause")
		return
	if role == "ready_up":
		Controls.touch_press("ready_up")
		Sound.play("ui_click", -8.0)
		return
	_contacts[index] = role
	_start[index] = at
	_last[index] = at
	_look_live[index] = false
	if role != "move" and role != "look":
		_held[role] = true
		Controls.touch_hold(role, true)
	update()


func _end(index: int) -> void:
	if not _contacts.has(index):
		return
	var role = _contacts[index]
	_contacts.erase(index)
	_look_live.erase(index)
	if role is String:
		if role == "move":
			_stick_center = _stick_home
			_stick_tip = _stick_home
		elif role != "look":
			_held.erase(role)
			Controls.touch_hold(role, false)
	update()


func _move_stick(at: Vector2) -> void:
	_stick_tip = at
	update()


func _drag_look(index: int, at: Vector2) -> void:
	if not _look_live.get(index, false):
		if at.distance_to(_start.get(index, at)) < LOOK_DEADZONE:
			return
		_look_live[index] = true
		_last[index] = at
		return
	var d: Vector2 = at - _last.get(index, at)
	_last[index] = at
	d = d.limit_length(90.0)
	var aim_k = 0.6 if bool(world.you.get("aiming", false)) else 1.0
	Controls.touch_look(d, aim_k)


func cancel_all() -> void:
	for role in _held:
		Controls.touch_hold(role, false)
	Controls.touch_hold("sprint", false)
	Controls.touch_move(Vector2.ZERO)
	_contacts.clear()
	_held.clear()
	_stick_center = _stick_home
	_stick_tip = _stick_home
	update()


func _process(_delta: float) -> void:
	var _pt = OS.get_ticks_usec()
	_process_body(_delta)
	Settings.prof_add("touch", OS.get_ticks_usec() - _pt)


func _process_body(_delta: float) -> void:
	if world == null:
		return
	_run_glue()
	# Move stick -> Controls (x right, y forward).
	if "move" in _contacts.values():
		var off = (_stick_tip - _stick_center) / STICK_R
		var sprint = off.length() >= SPRINT_EDGE and off.y < 0.3
		var mv = off.limit_length(1.0)
		if mv.length() < 0.12:
			mv = Vector2.ZERO
		Controls.touch_move(Vector2(mv.x, -mv.y))
		Controls.touch_hold("sprint", sprint)
	else:
		Controls.touch_move(Vector2.ZERO)
		Controls.touch_hold("sprint", false)


func _menu_open() -> bool:
	var m = hud.get("_menu") if hud else null
	return m != null and is_instance_valid(m)


## Pause / draft keys and mouse capture for the Thin run.
func _run_glue() -> void:
	var in_run = Net.state == "run"
	if in_run and Controls.pressed("pause") and hud:
		Controls.eat("pause")
		cancel_all()
		hud.toggle_menu()
	if hud and str(hud.get("_overlay_kind")) == "draft":
		for n in 3:
			if Controls.pressed("draft_%d" % (n + 1)):
				Controls.eat("draft_%d" % (n + 1))
				hud._choose("mutation", n)
	var capture = in_run and world.look_ready and not _menu_open() and Controls.device == "kbm" and OS.is_window_focused()
	if capture != _captured:
		_captured = capture
		Controls.capture_mouse(capture)


var _captured = false


func _exit_tree() -> void:
	if _captured:
		Controls.capture_mouse(false)
	cancel_all()


var _draw_sig = ""


## Redraw only when something the controls show changed.
func update() -> void:
	if world == null:
		.update()
		return
	var sig = "%s|%s|%s|%d|%s|%s|%s" % [str(_held), str(_contacts.values()), str(_stick_tip.round()), world.held_bits,
		str(world.you.get("interact_progress", world.you.get("revive", 0.0))), str(world.you.get("reloading", false)),
		str(Net.state) + str(world.you.get("state", "")) + str(world.you.get("prompt", "")) + str(world.weather_state.get("phase", "")) 		+ str(float(world.weather_state.get("phase_time_left", 0.0)) > 6.0)]
	if sig != _draw_sig:
		_draw_sig = sig
		.update()


func _draw() -> void:
	var _pt = OS.get_ticks_usec()
	_draw_body()
	Settings.prof_add("touch_draw", OS.get_ticks_usec() - _pt)


func _draw_body() -> void:
	if world == null:
		return
	var font = UI.font(24)
	UI.defer_text(self)
	# Stick.
	var moving = "move" in _contacts.values()
	var ring = Color(UI.PAPER.r, UI.PAPER.g, UI.PAPER.b, 0.35 if moving else 0.18)
	UI.ring(self, _stick_center, STICK_R, 0, TAU, ring, 2.0, 28)
	UI.ring(self, _stick_center, STICK_R * SPRINT_EDGE, -PI * 0.85, -PI * 0.15, Color(UI.AMBER.r, UI.AMBER.g, UI.AMBER.b, 0.35 if moving else 0.15), 2.0, 12)
	var tip = _stick_center + (_stick_tip - _stick_center).limit_length(STICK_R * SPRINT_EDGE)
	var sprinting = (world.held_bits & world.BITS.sprint) != 0
	draw_circle(tip, 30.0, Color(UI.AMBER.r, UI.AMBER.g, UI.AMBER.b, 0.55) if sprinting else Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.32 if moving else 0.18))
	if sprinting:
		UI.draw_text_centered(self, tip.x, tip.y - 40, "SPRINT", 20, UI.AMBER)
	# Buttons.
	var captions = {"fire": "FIRE", "jump": "JUMP", "aim": "AIM", "crouch": "CROUCH", "reload": "RELOAD",
		"use_item": "ITEM", "interact": "USE", "menu": "MENU", "ready_up": "READY"}
	for action in _buttons:
		if not _visible(action):
			continue
		var r: Rect2 = _buttons[action]
		var held = bool(_held.get(action, false))
		var accent = UI.CYAN
		if action == "fire":
			accent = UI.PINK
		elif action == "interact" or action == "ready_up":
			accent = UI.ACID
		elif action == "menu":
			accent = UI.MUTED
		var bg = Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.62 if not held else 0.85)
		if held:
			bg = Color(accent.r, accent.g, accent.b, 0.35)
		draw_rect(r, bg)
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), accent)
		UI.frame_rect(self, r, Color(accent.r, accent.g, accent.b, 0.55), 1.0)
		var cap: String = captions.get(action, action.to_upper())
		var size = 30 if action == "fire" else 24
		var w = UI.text_width(cap, size)
		UI.draw_text(self, r.position + Vector2((r.size.x - w) * 0.5, r.size.y * 0.5 + size * 0.35), cap, size, UI.PAPER)
		if action == "interact":
			var p = float(world.you.get("interact_progress", world.you.get("revive", 0.0)))
			if p > 0.0:
				draw_rect(Rect2(r.position + Vector2(0, r.size.y - 5), Vector2(r.size.x * clamp(p, 0, 1), 5)), UI.ACID)
		if action == "reload" and bool(world.you.get("reloading", false)):
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x, 4)), UI.PAPER)
	UI.flush_text(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel_all()
