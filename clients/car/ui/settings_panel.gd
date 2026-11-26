extends Control
## Full-screen settings sheet (title screen and in-run menu).

var _box = VBoxContainer.new()
var _values = {}


func _ready() -> void:
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade = ColorRect.new()
	shade.color = UI.OVERLAY
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(shade)
	var head = UI.label("SETTINGS", 48, UI.PAPER)
	head.rect_position = Vector2(60, 20)
	add_child(head)
	var back = UI.button("BACK", self, "_on_back")
	UI.place(back, 1.0, 0.0, -220, 24)
	back.rect_min_size = Vector2(160, 56)
	add_child(back)
	var scroll = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.margin_left = 60
	scroll.margin_top = 92
	scroll.margin_right = -60
	scroll.margin_bottom = -16
	scroll.scroll_horizontal_enabled = false
	add_child(scroll)
	_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_box.add_constant_override("separation", 10)
	scroll.add_child(_box)
	call_deferred("_attach_nav", back)
	_choice("CLOUD FULL CONNECTION", "full_wire", [["ws/json", "WS JSON"], ["ws/bin", "WS BIN"],
		["tcp/json", "TCP JSON"], ["tcp/bin", "TCP BIN"]])
	_slider("TOUCH LOOK SENSITIVITY", "look_sensitivity", 0.3, 3.0, 0.05, "%.2fx")
	_slider("MOUSE SENSITIVITY", "mouse_sensitivity", 0.2, 4.0, 0.05, "%.2fx")
	_slider("PAD LOOK SENSITIVITY", "pad_sensitivity", 0.3, 3.0, 0.05, "%.2fx")
	_toggle("INVERT LOOK Y", "invert_y")
	_choice("STARTER KIT (FULL / SOLO)", "starter_index", [[0, "PUMP SHOTGUN"], [1, "NAIL DRIVER"], [2, "REVOLVER"]])
	_slider("BUTTON SIZE", "button_size", 0.8, 1.4, 0.05, "%.2fx")
	_toggle("RETRO VHS / PS1 LOOK", "retro_enabled")
	_choice("RETRO LINES", "retro_lines", [[180, "180"], [240, "240 (ORIGINAL)"], [300, "300"], [360, "360"]])
	_slider("RENDER SCALE (RETRO OFF)", "render_scale", 0.35, 1.0, 0.05, "%.2f")
	_choice("MAP DETAIL", "map_detail", [[2, "AUTO"], [0, "LOW"], [1, "FULL"]])
	_choice("FOG", "fog_quality", [[0, "LIGHT"], [1, "NORMAL"], [2, "DENSE (ORIGINAL)"]])
	_slider("PARTICLE DENSITY", "particle_density", 0.0, 1.0, 0.05, "%.2f")
	_toggle("FPS / PING OVERLAY", "fps_overlay")
	_toggle("REDUCED FLASHING", "reduced_flash")
	_slider("VOLUME", "volume", 0.0, 1.0, 0.05, "%.2f")
	_choice("INTERPOLATION DELAY", "interp_ms", [[70, "70 MS"], [100, "100 MS"], [150, "150 MS"], [200, "200 MS"]])


func _row(caption: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 16)
	row.rect_min_size = Vector2(0, 52)
	var cap = UI.label(caption, 26, UI.PAPER)
	cap.rect_min_size = Vector2(420, 0)
	cap.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(cap)
	_box.add_child(row)
	return row


func _slider(caption: String, key: String, lo: float, hi: float, step: float, fmt: String) -> void:
	var row = _row(caption)
	var s = HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = Settings.get(key)
	s.rect_min_size = Vector2(420, 40)
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var v = UI.label(fmt % s.value, 26, UI.CYAN)
	row.add_child(v)
	s.connect("value_changed", self, "_on_slider", [key, v, fmt])


func _on_slider(value: float, key: String, label: Label, fmt: String) -> void:
	Settings.set(key, value)
	label.text = fmt % value
	Settings.save()


func _toggle(caption: String, key: String) -> void:
	var row = _row(caption)
	var b = Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed = bool(Settings.get(key))
	b.text = "ON" if b.pressed else "OFF"
	b.rect_min_size = Vector2(140, 48)
	row.add_child(b)
	b.connect("toggled", self, "_on_toggle", [key, b])


func _on_toggle(on: bool, key: String, b: Button) -> void:
	Settings.set(key, on)
	b.text = "ON" if on else "OFF"
	Settings.save()


func _choice(caption: String, key: String, options: Array) -> void:
	var row = _row(caption)
	var current = Settings.get(key)
	for opt in options:
		var b = Button.new()
		b.text = opt[1]
		b.focus_mode = Control.FOCUS_NONE
		b.rect_min_size = Vector2(0, 48)
		b.set_meta("value", opt[0])
		if opt[0] == current:
			UI.primary(b)
		row.add_child(b)
		b.connect("pressed", self, "_on_choice", [key, opt[0], row])


func _on_choice(key: String, value, row: HBoxContainer) -> void:
	Settings.set(key, value)
	Settings.save()
	for b in row.get_children():
		if b is Button:
			for st in ["normal", "hover", "pressed"]:
				b.add_stylebox_override(st, null)
			if b.get_meta("value") == value:
				UI.primary(b)


func _on_back() -> void:
	Settings.save()
	queue_free()


func _attach_nav(back: Button) -> void:
	UI.focusable(self)
	var nav = preload("res://ui/focus_nav.gd").new().attach(self)
	nav.first = back
	nav.back_button = back
