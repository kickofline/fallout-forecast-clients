extends Control
## VT323 has no ▶ ● ■ ❚❚, so the VHS OSD glyphs are drawn.

var kind = "play"   # play | rec | stop | pause | ff
var color = Color("#ccEADB")
var blink = false


func _init(k = "play", c = Color("#ccEADB"), side = 18.0) -> void:
	kind = k
	color = c
	rect_min_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s = rect_size
	var m: float = min(s.x, s.y)
	var c = s * 0.5
	var col = color
	if blink:
		return
	var ink = Color(0.047, 0.078, 0.133, 0.9)
	match kind:
		"play":
			var pts = PoolVector2Array([c + Vector2(-m * 0.35, -m * 0.4), c + Vector2(m * 0.42, 0), c + Vector2(-m * 0.35, m * 0.4)])
			draw_colored_polygon(pts, col)
		"ff":
			for dx in [-0.3, 0.12]:
				draw_colored_polygon(PoolVector2Array([c + Vector2(m * (dx - 0.2), -m * 0.35), c + Vector2(m * (dx + 0.25), 0), c + Vector2(m * (dx - 0.2), m * 0.35)]), col)
		"rec":
			draw_circle(c, m * 0.36 + 1.0, ink)
			draw_circle(c, m * 0.36, col)
		"stop":
			draw_rect(Rect2(c - Vector2(m, m) * 0.33, Vector2(m, m) * 0.66), col)
		"pause":
			draw_rect(Rect2(c + Vector2(-m * 0.35, -m * 0.35), Vector2(m * 0.24, m * 0.7)), col)
			draw_rect(Rect2(c + Vector2(m * 0.11, -m * 0.35), Vector2(m * 0.24, m * 0.7)), col)
