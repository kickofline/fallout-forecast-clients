extends Control
## ui/reticle.gd port: dynamic spread crosshair (cross / shotgun brackets),
## hit / crit / kill markers, reload ring, hold-to-interact arc, downed bleed.

var progress = 0.0
var targeted = false
var reload = false
var downed = false
var style = "cross"
var target_spread = 8.0
var ads = false
var _spread = 8.0
var _hit_left = 0.0
var _critical = false
var _killed = false
var _reload_t = 0.0
var _clock = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func hit(is_kill: bool, is_critical: bool) -> void:
	if _hit_left > 0.0 and _killed and not is_kill:
		return
	_hit_left = 0.28 if is_kill else 0.13
	_critical = is_critical
	_killed = is_kill


func _process(delta: float) -> void:
	_clock += delta
	_hit_left = max(0.0, _hit_left - delta)
	var speed = 26.0 if target_spread > _spread else 16.0
	_spread = lerp(_spread, target_spread, 1.0 - exp(-speed * delta))
	_reload_t = _reload_t + delta if reload else 0.0
	update()


func _draw() -> void:
	var c = rect_size * 0.5
	if downed:
		draw_arc(c, 30, 0, TAU, 48, Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.65), 6, true)
		var pulse = 0.6 + 0.4 * sin(_clock * 5.0)
		draw_arc(c, 30, -PI / 2, -PI / 2 + TAU * pulse, 48, UI.PINK, 4, true)
		UI.draw_text_centered(self, c.x, c.y + 9, "DOWN", 22, UI.PINK)
	else:
		var color = UI.CYAN if targeted else Color(1, 1, 1, 0.92 if ads else 0.80)
		_draw_reticle(c, color)
	if progress > 0.0:
		draw_arc(c, 22, -PI / 2, -PI / 2 + TAU * clamp(progress, 0.0, 1.0), 40, UI.CYAN, 4, true)
	elif reload:
		var r: float = fmod(_reload_t, 1.2) / 1.2
		draw_arc(c, 16, 0, TAU, 32, Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.6), 3, true)
		draw_arc(c, 16, -PI / 2, -PI / 2 + TAU * r, 32, UI.PAPER, 2, true)
	if _hit_left > 0.0:
		var hit_color = Color("#ffd56a") if _critical else (UI.PINK if _killed else Color.white)
		var duration = 0.28 if _killed else 0.13
		var pulse2 = 0.0 if Settings.reduced_flash else (_hit_left / duration) * (6.0 if _critical or _killed else 3.0)
		var inner = (13.0 if _killed else 10.0) + pulse2
		var outer = inner + (9.0 if _critical or _killed else 6.0)
		for i in 4:
			var d = Vector2(cos(PI / 4 + i * PI / 2), sin(PI / 4 + i * PI / 2))
			var tip = c + d * outer
			draw_line(c + d * inner, tip, Color.black, 5, true)
			if _killed:
				var cap = d.tangent() * 4.0
				draw_line(tip - cap, tip + cap, Color.black, 5, true)
				draw_line(tip - cap, tip + cap, hit_color, 3, true)
			draw_line(c + d * inner, tip, hit_color, 3, true)


func _draw_reticle(c: Vector2, color: Color) -> void:
	var outline = Color(0, 0, 0, 0.82)
	draw_circle(c, 2.7, outline)
	draw_circle(c, 1.6, color)
	if style == "shotgun":
		var r: float = clamp(_spread, 14.0, 92.0)
		var arm: float = clamp(r * 0.38, 7.0, 16.0)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner = c + Vector2(sx * r, sy * r)
				var h_end = corner + Vector2(-sx * arm, 0.0)
				var v_end = corner + Vector2(0.0, -sy * arm)
				draw_line(h_end, corner, outline, 4.4, true)
				draw_line(corner, v_end, outline, 4.4, true)
				draw_line(h_end, corner, color, 2.2, true)
				draw_line(corner, v_end, color, 2.2, true)
	elif style == "launcher":
		var r2: float = clamp(_spread, 13.0, 32.0)
		draw_arc(c, r2, PI * 0.16, PI * 0.84, 20, outline, 4.0, true)
		draw_arc(c, r2, PI * 0.16, PI * 0.84, 20, color, 2.0, true)
	else:
		var gap: float = clamp(_spread, 4.5, 76.0)
		var tick = 6.0 if ads else 7.5
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * gap, c + d * (gap + tick), outline, 4.0, true)
			draw_line(c + d * gap, c + d * (gap + tick), color, 2.0, true)
