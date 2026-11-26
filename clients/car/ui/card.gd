extends Control
## Centered "TUNING IN" style broadcast card used for loading/joining states.

var _kicker = ""
var _title = ""
var _detail = ""
var _t = 0.0
var _dots: Label
var provider: Object                 # optional: provider.load_text() replaces the dots


func setup(kicker: String, title: String, detail := "") -> void:
	_kicker = kicker
	_title = title
	_detail = detail


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box = VBoxContainer.new()
	box.set_anchors_and_margins_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGN_CENTER
	box.add_constant_override("separation", 6)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(box)
	var k = UI.label(_kicker, 26, UI.CYAN)
	k.align = Label.ALIGN_CENTER
	box.add_child(k)
	var t = UI.label(_title, 72, UI.PAPER, 2)
	t.align = Label.ALIGN_CENTER
	box.add_child(t)
	_dots = UI.label("", 26, UI.MUTED)
	_dots.align = Label.ALIGN_CENTER
	box.add_child(_dots)
	if not _detail.empty():
		var d = UI.label(_detail.to_upper(), 22, UI.AMBER)
		d.align = Label.ALIGN_CENTER
		box.add_child(d)
	var leave = UI.button("CANCEL", self, "_on_cancel")
	leave.rect_min_size = Vector2(220, 56)
	leave.size_flags_horizontal = SIZE_SHRINK_CENTER
	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, 24)
	box.add_child(spacer)
	box.add_child(leave)


func _process(delta: float) -> void:
	_t += delta
	var n = int(_t * 3.0) % 4
	var text = ""
	if provider and is_instance_valid(provider) and provider.has_method("load_text"):
		text = provider.load_text()
	_dots.text = text if not text.empty() else ["SEARCHING   ", "SEARCHING.  ", "SEARCHING.. ", "SEARCHING..."][n]


func _on_cancel() -> void:
	FullNet.current().leave()


func nav_back() -> void:
	_on_cancel()
