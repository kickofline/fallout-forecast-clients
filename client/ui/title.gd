extends Control
## Title: the original's playback-menu look (OSD corners, big two-tone
## FALLOUT / FORECAST, left-accent menu) plus callsign + server fields.

const SettingsPanel = preload("res://ui/settings_panel.gd")
const Glyph = preload("res://ui/glyph.gd")

var _name_edit = LineEdit.new()
var _url_edit = LineEdit.new()
var _connect: Button
var _status: Label
var _menu = VBoxContainer.new()
var _settings: Control
var _counter: Label
var _t = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var top_left = HBoxContainer.new()
	top_left.rect_position = Vector2(56, 26)
	top_left.add_constant_override("separation", 10)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_left)
	var play = Glyph.new("play", UI.OSD, 18.0)
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_left.add_child(play)
	top_left.add_child(UI.label("PLAY", 24, UI.OSD))
	_counter = UI.label("SP   00:00:00", 24, UI.OSD)
	UI.place(_counter, 1.0, 0.0, -250, 26)
	add_child(_counter)
	var date = UI.label("OCT 31 1987", 22, UI.OSD)
	UI.place(date, 0.0, 1.0, 56, -46)
	add_child(date)

	var title = VBoxContainer.new()
	title.rect_position = Vector2(76, 110)
	title.add_constant_override("separation", -12)
	add_child(title)
	var first = UI.label("FALLOUT", 120, Color("E6EEE2"))
	first.add_color_override("font_color_shadow", Color("#1f5d5a"))
	first.add_constant_override("shadow_offset_x", 4)
	first.add_constant_override("shadow_offset_y", 4)
	title.add_child(first)
	var second = UI.label("FORECAST", 120, Color("A9E9D9"))
	second.add_color_override("font_color_shadow", Color("#1f5d5a"))
	second.add_constant_override("shadow_offset_x", 4)
	second.add_constant_override("shadow_offset_y", 4)
	title.add_child(second)
	var gap = Control.new()
	gap.rect_min_size = Vector2(0, 22)
	title.add_child(gap)
	var sub = UI.label("CAR RECEIVER  ·  CLOUD PLAY", 26, UI.ACID)
	title.add_child(sub)

	_menu.rect_position = Vector2(720, 96)
	_menu.rect_min_size = Vector2(430, 0)
	_menu.add_constant_override("separation", 8)
	add_child(_menu)
	_field("CALLSIGN", _name_edit, Settings.player_name, 16)
	_field("SERVER (WSS)", _url_edit, Settings.server_url, 200)
	_connect = UI.button("CLOUD PLAY", self, "_on_connect")
	_connect.rect_min_size = Vector2(430, 58)
	_connect.align = Button.ALIGN_LEFT
	UI.primary(_connect)
	_menu.add_child(_connect)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	_menu.add_child(row)
	var settings = UI.button("SETTINGS", self, "_on_settings")
	settings.rect_min_size = Vector2(211, 52)
	settings.align = Button.ALIGN_LEFT
	row.add_child(settings)
	var quit = UI.button("QUIT", self, "_on_quit")
	quit.rect_min_size = Vector2(211, 52)
	quit.align = Button.ALIGN_LEFT
	row.add_child(quit)
	_status = UI.label("", 22, UI.PINK)
	_status.autowrap = true
	_status.rect_min_size = Vector2(430, 0)
	_menu.add_child(_status)
	refresh()


func _field(caption: String, edit: LineEdit, value: String, max_len: int) -> void:
	var cap = UI.label(caption, 18, UI.MUTED)
	_menu.add_child(cap)
	edit.text = value
	edit.max_length = max_len
	edit.rect_min_size = Vector2(430, 44)
	edit.virtual_keyboard_enabled = true
	edit.connect("text_entered", self, "_on_entered")
	_menu.add_child(edit)


func refresh() -> void:
	var connecting = Net.phase == "connecting" or Net.phase == "retuning"
	_connect.disabled = connecting
	_connect.text = "CONNECTING..." if connecting else "CLOUD PLAY"
	if connecting:
		_status.text = "TUNING " + _url_edit.text.strip_edges().to_upper()
		_status.add_color_override("font_color", UI.CYAN)
	elif not Net.last_error.empty():
		_status.text = "NO SIGNAL: " + Net.last_error.to_upper()
		_status.add_color_override("font_color", UI.PINK)
	else:
		_status.text = ""


func _process(delta: float) -> void:
	_t += delta
	var s = int(_t)
	_counter.text = "SP   %02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func _on_entered(_text) -> void:
	_on_connect()


func _on_connect() -> void:
	Settings.player_name = _name_edit.text.strip_edges().substr(0, 16)
	if Settings.player_name.empty():
		Settings.player_name = "Honda"
	var url = _url_edit.text.strip_edges()
	if url.empty():
		url = Settings.DEFAULT_URL
	if not (url.begins_with("ws://") or url.begins_with("wss://")):
		url = "wss://" + url
	if not url.ends_with("/") and url.count("/") <= 2:
		url += "/"
	Settings.server_url = url
	_url_edit.text = url
	Settings.save()
	OS.hide_virtual_keyboard()
	Net.connect_to(url, Settings.player_name)
	refresh()


func _on_settings() -> void:
	if _settings and is_instance_valid(_settings):
		return
	_settings = SettingsPanel.new()
	add_child(_settings)


func _on_quit() -> void:
	get_tree().quit()
