extends Node
## Port of the game's BroadcastUI (ui/broadcast_ui.gd): VT323 type, ink/paper
## palette, thin left-accent buttons, outlined panel-free HUD text.

const INK = Color("#0c1422")
const PAPER = Color("#e8e9d5")
const CYAN = Color("#66dfda")
const PINK = Color("#ff5689")
const AMBER = Color("#ffbf68")
const ACID = Color("#b8e56d")
const MUTED = Color("#aabac7")
const PANEL = Color("#14232d")
const OSD = Color("#ccEADB")
const OVERLAY = Color(0.025, 0.045, 0.075, 0.94)
const TIER_COLORS = [Color("#fff0d9"), Color("#66dfda"), Color("#ffc365")]
const T_META = 16
const T_BODY = 22
const T_NUM = 34
const T_HEAD = 56

var _fonts = {}
var _font_data: DynamicFontData
var _theme: Theme


func _ready() -> void:
	_font_data = load(Assets.font_path()) as DynamicFontData
	if _font_data == null:
		_font_data = load("res://fonts/VT323-Regular.ttf")


## VT323 at a pixel size, optional outline (cached per size/outline).
func font(size: int, outline := 0) -> DynamicFont:
	var key = size * 100 + outline
	if _fonts.has(key):
		return _fonts[key]
	var f = DynamicFont.new()
	f.font_data = _font_data
	f.size = size
	f.use_filter = false
	f.use_mipmaps = false
	if outline > 0:
		f.outline_size = outline
		f.outline_color = Color(INK.r, INK.g, INK.b, 0.9)
	_fonts[key] = f
	return f


func theme() -> Theme:
	if _theme:
		return _theme
	var t = Theme.new()
	t.default_font = font(24)
	t.set_color("font_color", "Label", PAPER)
	for type in ["Button", "CheckButton", "OptionButton"]:
		var is_check: bool = type == "CheckButton"
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var bg = PANEL
			var accent: Color = CYAN if is_check else MUTED.darkened(0.2)
			if state == "hover":
				bg = Color("#24424f")
				accent = CYAN
			elif state == "pressed":
				bg = Color("#1d3844")
				accent = CYAN
			elif state == "disabled":
				bg = INK
				accent = MUTED.darkened(0.45)
			if state == "focus":
				t.set_stylebox(state, type, StyleBoxEmpty.new())
			else:
				t.set_stylebox(state, type, button_box(bg, accent, 3, 8, 16))
		t.set_color("font_color", type, PAPER)
		t.set_color("font_color_hover", type, CYAN)
		t.set_color("font_color_pressed", type, CYAN)
		t.set_color("font_color_disabled", type, MUTED.darkened(0.25))
		t.set_font("font", type, font(26))
	t.set_stylebox("normal", "LineEdit", edit_box(Color("#0e1a26"), MUTED.darkened(0.15), 1, 3))
	t.set_stylebox("focus", "LineEdit", edit_box(Color("#132331"), CYAN, 2, 3))
	t.set_stylebox("read_only", "LineEdit", edit_box(INK, MUTED.darkened(0.4), 1, 3))
	t.set_font("font", "LineEdit", font(26))
	t.set_color("font_color", "LineEdit", PAPER)
	t.set_color("cursor_color", "LineEdit", CYAN)
	t.set_color("font_color_uneditable", "LineEdit", MUTED)
	var track = StyleBoxFlat.new()
	track.bg_color = PANEL
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var area = StyleBoxFlat.new()
	area.bg_color = CYAN
	area.content_margin_top = 4
	area.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	var grab = _grabber_icon()
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)
	var scroll = StyleBoxFlat.new()
	scroll.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, 0.6)
	scroll.content_margin_left = 3
	scroll.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", scroll)
	var grabber = StyleBoxFlat.new()
	grabber.bg_color = MUTED.darkened(0.35)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	t.set_stylebox("panel", "PanelContainer", panel())
	_theme = t
	return t


func _grabber_icon() -> ImageTexture:
	var img = Image.new()
	img.create(18, 30, false, Image.FORMAT_RGBA8)
	img.fill(PAPER)
	img.lock()
	for y in 30:
		img.set_pixel(0, y, INK)
		img.set_pixel(17, y, INK)
	img.unlock()
	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	return tex


func panel(color := INK, accent := CYAN) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = accent
	s.border_width_left = 3
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	return s


func button_box(bg: Color, accent: Color, left_width: int, pad_y: int, pad_x: int) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = accent
	s.border_width_left = left_width
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	return s


func edit_box(bg: Color, border: Color, border_all: int, border_left: int) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = border_left
	s.border_width_top = border_all
	s.border_width_right = border_all
	s.border_width_bottom = border_all
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func primary(b: Button) -> void:
	b.add_stylebox_override("normal", button_box(Color("#244d57"), CYAN, 4, 8, 16))
	b.add_stylebox_override("hover", button_box(Color("#2f626e"), CYAN, 4, 8, 16))
	b.add_stylebox_override("pressed", button_box(Color("#1c3e47"), CYAN, 4, 8, 16))


func accent(b: Button, color: Color) -> void:
	b.add_stylebox_override("normal", button_box(color.darkened(0.76), color, 3, 8, 16))
	b.add_stylebox_override("hover", button_box(color.darkened(0.66), color, 3, 8, 16))
	b.add_stylebox_override("pressed", button_box(color.darkened(0.82), color, 3, 8, 16))
	b.add_color_override("font_color_hover", color)


func label(text: String, size: int, color := PAPER, outline := 0) -> Label:
	var l = Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_font_override("font", font(size, outline))
	l.add_color_override("font_color", color)
	return l


## Outlined HUD text, no backing box.
func hud(text: String, size: int, color := PAPER) -> Label:
	return label(text, size, color, 2)


func button(text: String, target: Object, method: String, binds := []) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.connect("pressed", target, method, binds)
	b.connect("pressed", Sound, "play", ["ui_click", -6.0])
	return b


## Bar: dim track, solid fill.
func thin_bar(bar: ProgressBar, color: Color) -> void:
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(INK.r, INK.g, INK.b, 0.55)
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_stylebox_override("bg", bg)
	bar.add_stylebox_override("fg", fill)
	bar.percent_visible = false


func tier_color(tier: int) -> Color:
	return TIER_COLORS[clamp(tier, 0, 2)]


## Text width in a given font size.
func text_width(text: String, size: int) -> float:
	return font(size).get_string_size(text).x


## Outlined string drawn on a CanvasItem (Godot 3 has no draw_string_outline).
func draw_text(ci: CanvasItem, at: Vector2, text: String, size: int, color: Color, outline := true) -> void:
	var f = font(size, 2 if outline else 0)
	ci.draw_string(f, at, text, color)


func draw_text_centered(ci: CanvasItem, center_x: float, baseline: float, text: String, size: int, color: Color, outline := true) -> void:
	var w = text_width(text, size)
	draw_text(ci, Vector2(center_x - w * 0.5, baseline), text, size, color, outline)


## Anchor a control at (ax, ay) of its parent and offset it by (x, y) with a
## size (w, h). Explicit margins avoid Godot 3's rect_position-vs-anchor
## surprises when the parent isn't sized yet.
func place(c: Control, ax: float, ay: float, x: float, y: float, w := -1.0, h := -1.0) -> void:
	var size := c.rect_size
	if w >= 0.0:
		size.x = w
	if h >= 0.0:
		size.y = h
	size.x = max(size.x, c.rect_min_size.x)
	size.y = max(size.y, c.rect_min_size.y)
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.margin_left = x
	c.margin_top = y
	c.margin_right = x + size.x
	c.margin_bottom = y + size.y
