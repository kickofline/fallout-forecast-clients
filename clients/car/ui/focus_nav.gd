extends Node
## Keyboard / gamepad focus navigation for a menu screen, driven by the
## Controls menu actions (arrows / d-pad / left stick with repeat, Enter / A
## to accept, Esc / B to go back).
##
##   var nav = preload("res://ui/focus_nav.gd").new()
##   nav.attach(screen)                 # becomes a child of `screen`
##   nav.first = some_button            # optional: initial focus
##   nav.connect("back", self, "_on_back")   # or set nav.back_button
##
## Directions pick the nearest focusable control in that direction (no
## focus_neighbour setup needed). Left / right on a focused Range (slider)
## steps its value; accept presses a button (toggles check buttons, cycles an
## OptionButton). Focus is only shown once a keyboard or pad is used, so touch
## screens never get a stray highlight. Handled events are marked as handled
## so Godot's built-in ui_* focus moves don't double up.

signal back
signal moved(control)

var screen: Control
var first: Control
var back_button: BaseButton


func attach(target: Control) -> Node:
	screen = target
	target.add_child(self)
	return self


func _ready() -> void:
	Controls.connect("menu_action", self, "_on_repeat")
	Controls.connect("device_changed", self, "_on_device")
	call_deferred("_on_device", Controls.device)


func _exit_tree() -> void:
	if Controls.is_connected("menu_action", self, "_on_repeat"):
		Controls.disconnect("menu_action", self, "_on_repeat")
	if Controls.is_connected("device_changed", self, "_on_device"):
		Controls.disconnect("device_changed", self, "_on_device")


func _active() -> bool:
	return screen != null and is_instance_valid(screen) and screen.is_visible_in_tree()


func _input(event: InputEvent) -> void:
	if not _active():
		return
	var a = Controls.menu_action_for(event)
	if a.empty():
		return
	Controls.observe(event)
	if _do(a):
		get_tree().set_input_as_handled()


## Stick and held d-pad repeats (emitted by Controls._process).
func _on_repeat(action: String) -> void:
	if _active() and action in ["menu_up", "menu_down", "menu_left", "menu_right"]:
		_do(action)


func _on_device(d: String) -> void:
	if _active() and d != "touch" and _focused() == null:
		var c = _candidates()
		_focus(first if _usable(first) else (c.front() if not c.empty() else null))


## Performs a menu action; returns true when it was used.
func _do(action: String) -> bool:
	var f = _focused()
	match action:
		"menu_accept":
			if f == null:
				return false
			_accept(f)
			return true
		"menu_back":
			if back_button and is_instance_valid(back_button):
				back_button.emit_signal("pressed")
			emit_signal("back")
			return true
	var dir = {"menu_up": Vector2.UP, "menu_down": Vector2.DOWN,
		"menu_left": Vector2.LEFT, "menu_right": Vector2.RIGHT}.get(action, Vector2.ZERO)
	if f == null:
		var c = _candidates()
		_focus(first if _usable(first) else (c.front() if not c.empty() else null))
		return true
	if f is Range and not f is ScrollBar and dir.x != 0.0:
		f.value += f.step * dir.x if f.step > 0.0 else (f.max_value - f.min_value) * 0.05 * dir.x
		return true
	var nxt = _nearest(f, dir)
	if nxt:
		_focus(nxt)
	return true


func _accept(c: Control) -> void:
	if c is OptionButton:
		if c.get_item_count() > 0:
			var i = (c.selected + 1) % c.get_item_count()
			c.select(i)
			c.emit_signal("item_selected", i)
	elif c is BaseButton:
		if c.disabled:
			return
		if c.toggle_mode:
			c.pressed = not c.pressed
		c.emit_signal("pressed")
	elif c is LineEdit:
		c.emit_signal("text_entered", c.text)


func _focused() -> Control:
	var f = screen.get_focus_owner() if _active() else null
	return f if f != null and screen.is_a_parent_of(f) else null


func _focus(c) -> void:
	if c != null and is_instance_valid(c):
		c.grab_focus()
		_scroll_into_view(c)
		emit_signal("moved", c)


func _usable(c) -> bool:
	return c != null and is_instance_valid(c) and c is Control and c.is_visible_in_tree() \
		and c.focus_mode != Control.FOCUS_NONE and not (c is BaseButton and c.disabled)


func _candidates() -> Array:
	var out = []
	_collect(screen, out)
	return out


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control:
			if _usable(c):
				out.append(c)
			_collect(c, out)


## Closest focusable control whose centre lies in `dir` from `from`,
## weighting sideways offset double so rows and columns line up.
func _nearest(from: Control, dir: Vector2):
	var o = from.get_global_rect()
	var p = o.position + o.size * 0.5
	var best = null
	var best_score = INF
	for c in _candidates():
		if c == from:
			continue
		var r = c.get_global_rect()
		var q = r.position + r.size * 0.5
		var d = q - p
		var along = d.dot(dir)
		if along <= 1.0:
			continue
		var side = abs(d.dot(Vector2(-dir.y, dir.x)))
		var score = along + side * 2.0
		if score < best_score:
			best_score = score
			best = c
	return best


func _scroll_into_view(c: Control) -> void:
	var n = c.get_parent()
	while n and n != screen.get_parent():
		if n is ScrollContainer:
			var sr = n.get_global_rect()
			var cr = c.get_global_rect()
			if cr.position.y < sr.position.y:
				n.scroll_vertical -= int(sr.position.y - cr.position.y) + 8
			elif cr.end.y > sr.end.y:
				n.scroll_vertical += int(cr.end.y - sr.end.y) + 8
			return
		n = n.get_parent()
