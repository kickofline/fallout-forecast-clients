extends Control
## Gamepad / keyboard navigation for any screen, driven only by the Controls
## menu_* actions. main.gd points `root` at the active screen (or HUD menu);
## this picks the nearest focusable control in the pressed direction, draws a
## frame around it and activates it on menu_accept. menu_back calls
## root.nav_back() when the screen defines it.
##
## Focusable: visible, enabled BaseButton, Range (left/right changes the
## value while focused) and LineEdit (accept opens it for typing).

var root: Control
var _target: Control
var _active = false
var _scan_left = 0.0
var _items = []


func _ready() -> void:
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_root(r: Control) -> void:
	if r == root:
		return
	root = r
	_target = null
	_items = []
	_scan_left = 0.0
	update()


func _process(delta: float) -> void:
	if root == null or not is_instance_valid(root) or not root.is_visible_in_tree():
		if _target:
			_target = null
			update()
		return
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = 0.4
		_items = []
		_collect(root)
		if _target and not (_target in _items):
			_target = null
	var dir = Vector2.ZERO
	if Controls.pressed("menu_up"):
		dir = Vector2.UP
	elif Controls.pressed("menu_down"):
		dir = Vector2.DOWN
	elif Controls.pressed("menu_left"):
		dir = Vector2.LEFT
	elif Controls.pressed("menu_right"):
		dir = Vector2.RIGHT
	if dir != Vector2.ZERO:
		_active = true
		if _target is Range and is_instance_valid(_target) and dir.x != 0.0:
			var r: Range = _target
			r.value = clamp(r.value + dir.x * max(r.step, (r.max_value - r.min_value) / 20.0), r.min_value, r.max_value)
		else:
			_move(dir)
		update()
	if Controls.pressed("menu_accept") and _active:
		_accept()
	if Controls.pressed("menu_back") and root.has_method("nav_back"):
		root.nav_back()
	if _target and is_instance_valid(_target):
		update()


func _collect(n: Node) -> void:
	for c in n.get_children():
		if not (c is Control) or not c.visible:
			continue
		if c is BaseButton and not c.disabled:
			_items.append(c)
		elif c is Range and not (c is ScrollBar) and not (c is ProgressBar):
			_items.append(c)
		elif c is LineEdit and c.editable:
			_items.append(c)
		_collect(c)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().position + c.get_global_rect().size * 0.5


func _move(dir: Vector2) -> void:
	if _items.empty():
		_items = []
		_collect(root)
	if _items.empty():
		return
	if _target == null or not is_instance_valid(_target):
		_target = _items[0]
		Sound.play("ui_focus", -10.0)
		return
	var from = _center(_target)
	var best = null
	var best_score = INF
	for c in _items:
		if c == _target or not c.is_visible_in_tree():
			continue
		var d: Vector2 = _center(c) - from
		var along = d.dot(dir)
		if along <= 4.0:
			continue
		var across = abs(d.dot(Vector2(-dir.y, dir.x)))
		var score = along + across * 2.5
		if score < best_score:
			best_score = score
			best = c
	if best:
		_target = best
		Sound.play("ui_focus", -10.0)


func _accept() -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree():
		return
	if _target is LineEdit:
		_target.grab_focus()
		OS.show_virtual_keyboard(_target.text)
	elif _target is BaseButton:
		var b: BaseButton = _target
		if b.toggle_mode:
			b.pressed = not b.pressed
		else:
			b.emit_signal("pressed")


func _draw() -> void:
	if _target == null or not is_instance_valid(_target) or not _active or not _target.is_visible_in_tree():
		return
	var r = _target.get_global_rect().grow(3)
	r.position -= get_global_rect().position
	UI.frame_rect(self, r, UI.AMBER, 3.0)
