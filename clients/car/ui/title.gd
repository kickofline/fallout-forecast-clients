extends Control
## Title: the original's playback-menu look (OSD corners, big two-tone
## FALLOUT / FORECAST, left-accent menu) plus callsign and a mode choice:
## CLOUD (Thin tier), CLOUD FULL (Open Protocol Full tier) and SOLO (the
## in-process solo authority, solo/local_link.gd). Gamepad / keyboard go
## through ui/menu_nav.gd.

const SettingsPanel = preload("res://ui/settings_panel.gd")
const Glyph = preload("res://ui/glyph.gd")
const MODES = [["thin", "CLOUD"], ["full", "CLOUD FULL"], ["solo", "SOLO"]]
const SOLO_MAPS = [["pinecrest", "PINECREST"], ["harbor", "HARBOR POINT"], ["maple_hollow", "MAPLE HOLLOW"]]

var _name_edit = LineEdit.new()
var _url_edit = LineEdit.new()
var _url_cap: Label
var _maps_row = HBoxContainer.new()
var _mode_row = HBoxContainer.new()
var _connect: Button
var _status: Label
var _menu = VBoxContainer.new()
var _settings: Control
var _counter: Label
var _sub: Label
var _t = 0.0
var _mode = "thin"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_mode = Settings.play_mode if Settings.play_mode in ["thin", "full", "solo"] else "thin"
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
	_sub = UI.label("", 26, UI.ACID)
	title.add_child(_sub)

	_menu.rect_position = Vector2(720, 40)
	_menu.rect_min_size = Vector2(450, 0)
	_menu.add_constant_override("separation", 8)
	add_child(_menu)
	_field("CALLSIGN", _name_edit, Settings.player_name, 16)
	_menu.add_child(UI.label("MODE", 18, UI.MUTED))
	_mode_row.add_constant_override("separation", 6)
	_menu.add_child(_mode_row)
	for m in MODES:
		var b = UI.button(m[1], self, "_on_mode", [m[0]])
		b.rect_min_size = Vector2(146, 50)
		b.toggle_mode = false
		b.set_meta("mode", m[0])
		_mode_row.add_child(b)
	_url_cap = UI.label("SERVER (WSS)", 18, UI.MUTED)
	_menu.add_child(_url_cap)
	_url_edit.max_length = 200
	_url_edit.rect_min_size = Vector2(450, 44)
	_url_edit.virtual_keyboard_enabled = true
	_url_edit.connect("text_entered", self, "_on_entered")
	_menu.add_child(_url_edit)
	_maps_row.add_constant_override("separation", 6)
	_menu.add_child(_maps_row)
	for m in SOLO_MAPS:
		var mb = UI.button(m[1], self, "_on_solo_map", [m[0]])
		mb.rect_min_size = Vector2(146, 44)
		mb.add_font_override("font", UI.font(20))
		mb.set_meta("map", m[0])
		_maps_row.add_child(mb)
	_connect = UI.button("CLOUD PLAY", self, "_on_connect")
	_connect.rect_min_size = Vector2(450, 58)
	_connect.align = Button.ALIGN_LEFT
	UI.primary(_connect)
	_menu.add_child(_connect)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	_menu.add_child(row)
	var settings = UI.button("SETTINGS", self, "_on_settings")
	settings.rect_min_size = Vector2(221, 52)
	settings.align = Button.ALIGN_LEFT
	row.add_child(settings)
	var quit = UI.button("QUIT", self, "_on_quit")
	quit.rect_min_size = Vector2(221, 52)
	quit.align = Button.ALIGN_LEFT
	row.add_child(quit)
	_status = UI.label("", 22, UI.PINK)
	_status.autowrap = true
	_status.rect_min_size = Vector2(450, 0)
	_menu.add_child(_status)
	_apply_mode()
	refresh()


func _field(caption: String, edit: LineEdit, value: String, max_len: int) -> void:
	var cap = UI.label(caption, 18, UI.MUTED)
	_menu.add_child(cap)
	edit.text = value
	edit.max_length = max_len
	edit.rect_min_size = Vector2(450, 44)
	edit.virtual_keyboard_enabled = true
	edit.connect("text_entered", self, "_on_entered")
	_menu.add_child(edit)


func _on_mode(m: String) -> void:
	_store_url()
	_mode = m
	_apply_mode()
	refresh()


func _on_solo_map(id: String) -> void:
	Settings.solo_map = id
	_apply_mode()


func _apply_mode() -> void:
	for b in _mode_row.get_children():
		var on = b.get_meta("mode") == _mode
		UI.accent(b, UI.ACID if on else UI.MUTED.darkened(0.2))
		b.modulate = Color(1, 1, 1, 1.0 if on else 0.7)
	var solo = _mode == "solo"
	_url_cap.text = "SOLO DISTRICT" if solo else ("SERVER (WSS, FULL TIER)" if _mode == "full" else "SERVER (WSS)")
	_url_edit.visible = not solo
	_maps_row.visible = solo
	for b in _maps_row.get_children():
		var on2 = b.get_meta("map") == Settings.solo_map
		UI.accent(b, UI.CYAN if on2 else UI.MUTED.darkened(0.2))
		b.modulate = Color(1, 1, 1, 1.0 if on2 else 0.7)
	_url_edit.text = Settings.full_url if _mode == "full" else Settings.server_url
	_sub.text = {"thin": "CAR RECEIVER  ·  CLOUD PLAY", "full": "CAR RECEIVER  ·  CLOUD FULL", "solo": "CAR RECEIVER  ·  SOLO TAPE"}[_mode]


func _store_url() -> void:
	if _mode == "solo":
		return
	var url = _clean_url(_url_edit.text)
	if _mode == "full":
		Settings.full_url = url
	else:
		Settings.server_url = url


func _clean_url(text: String) -> String:
	var url = text.strip_edges()
	if url.empty():
		url = Settings.DEFAULT_FULL_URL if _mode == "full" else Settings.DEFAULT_URL
	if not (url.begins_with("ws://") or url.begins_with("wss://")):
		url = "wss://" + url
	if not url.ends_with("/") and url.count("/") <= 2:
		url += "/"
	return url


func refresh() -> void:
	var net = FullNet.current()
	var connecting = net.phase == "connecting" or net.phase == "retuning"
	_connect.disabled = connecting
	var label = {"thin": "CLOUD PLAY", "full": "CLOUD FULL", "solo": "START SOLO"}[_mode]
	_connect.text = "CONNECTING..." if connecting else label
	if connecting:
		_status.text = "TUNING " + _url_edit.text.strip_edges().to_upper()
		_status.add_color_override("font_color", UI.CYAN)
	elif not net.last_error.empty():
		_status.text = "NO SIGNAL: " + net.last_error.to_upper()
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
	_store_url()
	Settings.play_mode = _mode
	Settings.save()
	OS.hide_virtual_keyboard()
	match _mode:
		"thin":
			FullNet.active = false
			_url_edit.text = Settings.server_url
			Net.connect_to(Settings.server_url, Settings.player_name)
		"full":
			if Net.phase != "offline":
				Net.leave()
			_url_edit.text = Settings.full_url
			FullNet.connect_full(Settings.full_url, Settings.player_name)
		"solo":
			if Net.phase != "offline":
				Net.leave()
			FullNet.start_solo(Settings.solo_map, Settings.player_name)
	refresh()


func _on_settings() -> void:
	if _settings and is_instance_valid(_settings):
		return
	_settings = SettingsPanel.new()
	add_child(_settings)


func _on_quit() -> void:
	get_tree().quit()
