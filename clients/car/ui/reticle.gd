extends Control
## ui/reticle.gd port: dynamic spread crosshair (cross / shotgun brackets),
## hit / crit / kill markers, reload ring, hold-to-interact arc, downed
## bleed-out ring + seconds, jam tint and the Disruptor charge ring. Rings are
## quads (UI.ring), not antialiased arcs, so they batch on the car's GPU.

var progress = 0.0
var targeted = false
var reload = false
var downed = false
var style = "cross"
var bleed = -1.0            # downed: bleed-out fraction left (Full); <0 = pulse
var bleed_seconds = 0
var jammed = false
var charging = false
var charge = 0.0
var reload_frac = -1.0      # real reload progress (Full); <0 = looping ring
var target_spread = 8.0
var ads = false
var ads_tight = false       # ADS with near-zero spread (native: brighter, shorter ticks)
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
	var _pt = OS.get_ticks_usec()
	_process_body(delta)
	Settings.prof_add("reticle", OS.get_ticks_usec() - _pt)


func _process_body(delta: float) -> void:
	_clock += delta
	_hit_left = max(0.0, _hit_left - delta)
	var speed = 26.0 if target_spread > _spread else 16.0
	_spread = lerp(_spread, target_spread, 1.0 - exp(-speed * delta))
	_reload_t = _reload_t + delta if reload else 0.0
	update()


func _draw() -> void:
	var c = rect_size * 0.5
	if downed:
		UI.ring(self, c, 30, 0, TAU, Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.65), 6, 32)
		var k = bleed if bleed >= 0.0 else 0.6 + 0.4 * sin(_clock * 5.0)
		UI.ring(self, c, 30, -PI / 2, -PI / 2 + TAU * clamp(k, 0.0, 1.0), UI.PINK, 4, 32)
		var txt = str(bleed_seconds) if bleed >= 0.0 else "DOWN"
		UI.draw_text_centered(self, c.x, c.y + 9, txt, 26 if bleed >= 0.0 else 22, UI.PINK)
	else:
		var color = UI.CYAN if targeted else Color(1, 1, 1, 0.92 if ads_tight else 0.80)
		if jammed:
			color = UI.PINK
		elif charging:
			color = UI.AMBER if charge >= 1.0 else UI.CYAN.linear_interpolate(UI.PINK, charge)
		_draw_reticle(c, color)
	if progress > 0.0:
		UI.ring(self, c, 22, -PI / 2, -PI / 2 + TAU * clamp(progress, 0.0, 1.0), UI.CYAN, 4, 28)
	elif charging:
		UI.ring(self, c, 18, 0, TAU, Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.55), 4, 24)
		UI.ring(self, c, 18, -PI / 2, -PI / 2 + TAU * clamp(charge, 0.0, 1.0), UI.AMBER if charge >= 1.0 else UI.CYAN, 3, 24)
	elif reload:
		var r: float = reload_frac if reload_frac >= 0.0 else fmod(_reload_t, 1.2) / 1.2
		UI.ring(self, c, 16, 0, TAU, Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.6), 3, 24)
		UI.ring(self, c, 16, -PI / 2, -PI / 2 + TAU * clamp(r, 0.0, 1.0), UI.PAPER, 2, 24)
	if jammed and not downed:
		UI.draw_text_centered(self, c.x, c.y + 40, "JAMMED", 18, UI.PINK)
	if _hit_left > 0.0:
		var hit_color = Color("#ffd56a") if _critical else (UI.PINK if _killed else Color.white)
		var duration = 0.28 if _killed else 0.13
		var pulse2 = 0.0 if Settings.reduced_flash else (_hit_left / duration) * (6.0 if _critical or _killed else 3.0)
		var inner = (13.0 if _killed else 10.0) + pulse2
		var outer = inner + (9.0 if _critical or _killed else 6.0)
		for i in 4:
			var d = Vector2(cos(PI / 4 + i * PI / 2), sin(PI / 4 + i * PI / 2))
			var tip = c + d * outer
			UI.seg(self, c + d * inner, tip, Color.black, 5)
			if _killed:
				var cap = d.tangent() * 4.0
				UI.seg(self, tip - cap, tip + cap, Color.black, 5)
				UI.seg(self, tip - cap, tip + cap, hit_color, 3)
			UI.seg(self, c + d * inner, tip, hit_color, 3)


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
				UI.seg(self, h_end, corner, outline, 4.4)
				UI.seg(self, corner, v_end, outline, 4.4)
				UI.seg(self, h_end, corner, color, 2.2)
				UI.seg(self, corner, v_end, color, 2.2)
	elif style == "launcher":
		var r2: float = clamp(_spread, 13.0, 32.0)
		UI.ring(self, c, r2, PI * 0.16, PI * 0.84, outline, 4.0, 10)
		UI.ring(self, c, r2, PI * 0.16, PI * 0.84, color, 2.0, 10)
	else:
		var gap: float = clamp(_spread, 4.5, 76.0)
		var tick = 6.0 if ads_tight else 7.5
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			UI.seg(self, c + d * gap, c + d * (gap + tick), outline, 4.0)
			UI.seg(self, c + d * gap, c + d * (gap + tick), color, 2.0)
