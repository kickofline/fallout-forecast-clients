extends Control
## One batched canvas for the HUD pieces that come and go: boss / miniboss
## bar, wave progress, Calm countdown, wave intro card, reticle popups
## (scrap, multikills, feats), teammate cards, the ping + chat feed, the
## mutation row and the health damage trail.
##
## Car budget: everything is filled rects (batch) plus UI.draw_text stamps
## (one glyph texture per size), deferred so rects and text each batch. It
## redraws only when its signature changes or something is animating.

const CARD_W = 168.0
const FEED_LIFE = 7.0
const POP_LIFE = 1.4
const CARD_LIFE = 2.6
const BOSS_W = 400.0
const PROGRESS_W = 160.0
const GREEN = Color(0.55, 1.0, 0.3)

var world: Node
var net: Node
var hud: Node
var boss_top = 106.0          # y of the boss strip (hud keeps the banner below it)
var trail_rect = Rect2()      # global rect of the health bar (hud sets it)

var _pops = []                # [text, color, life]
var _feed = []                # [text, color, life]
var _card_title = ""
var _card_sub = ""
var _card_color = UI.PAPER
var _card_left = 0.0
var _countdown = 0
var _trail = 1.0              # damage trail fraction of the health bar
var _trail_hold = 0.0
var _hp_frac = 1.0
var _sig = ""
var _clock = 0.0
var _mut_flash = 0.0
var _mut_key = ""


func _ready() -> void:
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ------------------------------------------------------------------ inputs
func popup(text: String, color := UI.PAPER) -> void:
	for p in _pops:
		if p[0] == text:
			p[2] = POP_LIFE
			return
	_pops.append([text, color, POP_LIFE])
	if _pops.size() > 3:
		_pops.pop_front()


func feed(text: String, color := UI.PAPER) -> void:
	_feed.append([text, color, FEED_LIFE])
	if _feed.size() > 4:
		_feed.pop_front()


func card(title: String, sub: String, color := UI.PAPER) -> void:
	_card_title = title
	_card_sub = sub
	_card_color = color
	_card_left = CARD_LIFE


func set_countdown(n: int) -> void:
	_countdown = n


## Health fraction each frame; a drop leaves a white chunk that drains after 0.35 s.
func set_health(frac: float) -> void:
	if frac < _hp_frac - 0.001:
		_trail = max(_trail, _hp_frac)
		_trail_hold = 0.35
	_hp_frac = frac
	if _trail < frac:
		_trail = frac


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	var _pt = OS.get_ticks_usec()
	_process_body(delta)
	Settings.prof_add("hud_panels", OS.get_ticks_usec() - _pt)


func _process_body(delta: float) -> void:
	if world == null:
		return
	_clock += delta
	var anim = false
	for list in [_pops, _feed]:
		for p in list:
			p[2] -= delta
		while not list.empty() and list[0][2] <= 0.0:
			list.pop_front()
		anim = anim or not list.empty()
	if _card_left > 0.0:
		_card_left = max(0.0, _card_left - delta)
		anim = true
	if _trail > _hp_frac:
		_trail_hold -= delta
		if _trail_hold <= 0.0:
			_trail = max(_hp_frac, _trail - delta * 0.6)
		anim = true
	var mk = _mutation_key()
	if mk != _mut_key:
		if not _mut_key.empty() or not mk.empty():
			_mut_flash = 2.0
		_mut_key = mk
	if _mut_flash > 0.0:
		_mut_flash = max(0.0, _mut_flash - delta)
		anim = true
	var b = _boss()
	var sig = "%s|%d|%s|%s|%d" % [str(b), _countdown, _progress_key(), _team_key(), int(_clock * 2.0) if _pulsing() else 0]
	if anim or sig != _sig:
		_sig = sig
		update()



func _pulsing() -> bool:
	for o in world.others:
		if o.state == "downed":
			return true
	return false


func _progress_key() -> String:
	var p = world.get("progress")
	if not (p is Dictionary):
		return ""
	return "%d/%d" % [int(p.get("left", 0)), int(p.get("total", 0))] if _fighting() else ""


func _fighting() -> bool:
	return str(world.weather_state.get("phase", "calm")) in ["drizzle", "downpour", "acid_storm"]


func _team_key() -> String:
	var parts = []
	for o in world.others:
		parts.append("%s%s%d/%d" % [o.name, o.state, int(o.get("hp", 0.0)), int(o.get("suit", 0.0))])
	return ",".join(parts)


func _mutation_key() -> String:
	var a = world.get("player_mutations")
	var b = world.get("enemy_mutations")
	return "%s|%s" % [str(a) if a is Array else "", str(b) if b is Array else ""]


## {name, frac, sacs: [fractions] or [], burn} or {}.
func _boss() -> Dictionary:
	var bd = world.get("boss")
	for e in world.enemy_points:
		if e[1] == "cumulus":
			var out = {"name": "CUMULUS", "frac": float(e[2]) if e[2] != null else 1.0, "sacs": [], "burn": false}
			if bd is Dictionary and not bd.empty():
				var parts: Array = bd.parts
				var mx: Array = bd.max
				if int(bd.sacs) > 0:
					for i in 3:
						out.sacs.append(clamp(float(parts[i]) / max(1.0, float(mx[i])), 0.0, 1.0) if i < parts.size() else 0.0)
				elif parts.size() > 3:
					out.frac = clamp(float(parts[3]) / max(1.0, float(mx[3])), 0.0, 1.0)
				out.burn = float(bd.burn) > 0.0
			return out
	for e in world.enemy_points:
		if e[1] == "cloudburst":
			return {"name": "CLOUDBURST", "frac": clamp(float(e[2]) if e[2] != null else 1.0, 0.0, 1.0), "sacs": [], "burn": false}
	return {}


# ------------------------------------------------------------------ draw
func _draw() -> void:
	var _pt = OS.get_ticks_usec()
	if world != null:
		UI.defer_text(self)
		_draw_body()
		UI.flush_text(self)
	Settings.prof_add("hud_panels_draw", OS.get_ticks_usec() - _pt)


func _draw_body() -> void:
	var size = rect_size
	var cx = size.x * 0.5
	var c = size * 0.5
	var ink = Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.6)
	# Health damage trail (white chunk behind the health bar).
	if _trail > _hp_frac + 0.002 and trail_rect.size.x > 0.0:
		var r = Rect2(trail_rect.position - rect_global_position, trail_rect.size)
		draw_rect(Rect2(r.position + Vector2(r.size.x * _hp_frac, 0), Vector2(r.size.x * (_trail - _hp_frac), r.size.y)), Color(1, 1, 1, 0.85))
	# Wave progress (pink, under the infected count), count only at <= 5.
	var p = world.get("progress")
	if _fighting() and p is Dictionary and int(p.get("total", 0)) > 0:
		var k = clamp(1.0 - float(p.left) / float(p.total), 0.0, 1.0)
		var at = Vector2(cx - PROGRESS_W * 0.5, 101)
		draw_rect(Rect2(at, Vector2(PROGRESS_W, 3)), ink)
		draw_rect(Rect2(at, Vector2(PROGRESS_W * k, 3)), UI.PINK)
	# Boss / miniboss strip.
	var b = _boss()
	if not b.empty():
		var y = boss_top
		UI.draw_text_centered(self, cx, y + 16, b.name, 20, UI.ACID)
		var bar_y = y + 22
		if b.sacs.empty():
			var col = UI.ACID
			if b.burn:
				col = Color(1.0, 0.6 + 0.2 * sin(_clock * 18.0), 0.35)
			draw_rect(Rect2(cx - BOSS_W * 0.5, bar_y, BOSS_W, 5), ink)
			draw_rect(Rect2(cx - BOSS_W * 0.5, bar_y, BOSS_W * b.frac, 5), col)
		else:
			var w = (BOSS_W - 12.0) / 3.0
			for i in 3:
				var x = cx - BOSS_W * 0.5 + i * (w + 6.0)
				draw_rect(Rect2(x, bar_y, w, 5), ink)
				draw_rect(Rect2(x, bar_y, w * float(b.sacs[i]), 5), UI.ACID)
	# Calm countdown (last 5 s).
	if _countdown > 0:
		UI.draw_text_centered(self, cx, 190, str(_countdown), 56, UI.AMBER)
	# Wave intro card.
	if _card_left > 0.0:
		var a = clamp(min(_card_left * 2.0, (CARD_LIFE - _card_left) * 6.0), 0.0, 1.0)
		var tc = _card_color
		tc.a = a
		UI.draw_text_centered(self, cx, size.y * 0.32, _card_title, 56, tc)
		if not _card_sub.empty():
			UI.draw_text_centered(self, cx, size.y * 0.32 + 30, _card_sub, 22, Color(UI.PAPER.r, UI.PAPER.g, UI.PAPER.b, a))
	# Popups right of the reticle, newest at the bottom.
	var py = c.y - 8.0
	for i in range(_pops.size() - 1, -1, -1):
		var pp = _pops[i]
		var pc: Color = pp[1]
		pc.a = clamp(pp[2] * 3.0, 0.0, 1.0)
		var rise = (POP_LIFE - pp[2]) * 6.0
		UI.draw_text(self, Vector2(c.x + 34, py - rise), pp[0], 22, pc)
		py -= 22.0
	# Teammate cards (left, below the vitals).
	var ty = 196.0
	for o in world.others:
		_teammate(Vector2(20, ty), o)
		ty += 44.0
	# Mutation row (enemy | squad), under the vitals.
	_draw_mutations(Vector2(20, 172))
	# Ping + chat feed.
	var fy = max(ty + 8.0, 300.0)
	for f in _feed:
		var fc: Color = f[1]
		fc.a = clamp(f[2], 0.0, 1.0)
		UI.draw_text(self, Vector2(20, fy + 14), f[0], 18, fc)
		fy += 20.0


func _teammate(at: Vector2, o: Dictionary) -> void:
	var st = str(o.state)
	var alpha = 0.45 if st == "out" else 1.0
	var name_col: Color = o.get("color", UI.CYAN) if o.get("color") is Color else UI.CYAN
	name_col.a = alpha
	var tag = ""
	var tag_col = UI.PINK
	match st:
		"downed":
			tag = "DOWN"
			tag_col.a = 1.0 if Settings.reduced_flash else 0.55 + 0.45 * sin(_clock * 8.0)
		"turned":
			tag = "TURNED"
			tag_col = GREEN
		"out":
			tag = "OUT"
			tag_col = UI.MUTED
	UI.draw_text(self, at + Vector2(0, 14), str(o.name).to_upper(), 18, name_col)
	if not tag.empty():
		UI.draw_text(self, at + Vector2(CARD_W - UI.text_width(tag, 18), 14), tag, 18, tag_col)
	var ink = Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.55 * alpha)
	var hp = clamp(float(o.get("hp", 100.0)) / max(1.0, float(o.get("max_hp", 100.0))), 0.0, 1.0)
	var suit = clamp(float(o.get("suit", 100.0)) / 100.0, 0.0, 1.0)
	draw_rect(Rect2(at + Vector2(0, 20), Vector2(CARD_W, 4)), ink)
	draw_rect(Rect2(at + Vector2(0, 20), Vector2(CARD_W * hp, 4)), Color(UI.PINK.r, UI.PINK.g, UI.PINK.b, alpha))
	draw_rect(Rect2(at + Vector2(0, 27), Vector2(CARD_W, 3)), ink)
	draw_rect(Rect2(at + Vector2(0, 27), Vector2(CARD_W * suit, 3)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, alpha))


func _draw_mutations(at: Vector2) -> void:
	var enemy = world.get("enemy_mutations")
	var squad = world.get("player_mutations")
	if not (enemy is Array) or not (squad is Array) or (enemy.empty() and squad.empty()):
		return
	var a = 1.0 if _mut_flash > 0.0 else 0.6
	var x = at.x
	for id in enemy:
		var m = net.enemy_mutations.get(str(id), {}) if "enemy_mutations" in net else {}
		x = _chip(Vector2(x, at.y), str(m.get("name", id)), UI.PINK, a)
	if not enemy.empty() and not squad.empty():
		draw_rect(Rect2(x, at.y + 2, 1, 14), Color(UI.MUTED.r, UI.MUTED.g, UI.MUTED.b, 0.5 * a))
		x += 6.0
	for id in squad:
		var m2 = net.player_mutations.get(str(id), {}) if "player_mutations" in net else {}
		var col = UI.ACID
		if m2.get("color") is String:
			col = Color(m2.color)
		x = _chip(Vector2(x, at.y), str(m2.get("name", id)), col, a)


## Two-letter chip for a mutation; returns the next x.
func _chip(at: Vector2, name: String, color: Color, a: float) -> float:
	var words = name.replace("_", " ").to_upper().split(" ", false)
	var txt = ""
	for w in words:
		txt += w.left(1)
	txt = txt.left(2) if txt.length() >= 2 else name.to_upper().left(2)
	var w2 = 24.0
	draw_rect(Rect2(at, Vector2(w2, 18)), Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.55 * a))
	draw_rect(Rect2(at + Vector2(0, 16), Vector2(w2, 2)), Color(color.r, color.g, color.b, a))
	UI.draw_text_centered(self, at.x + w2 * 0.5, at.y + 14, txt, 18, Color(color.r, color.g, color.b, a), false)
	return at.x + w2 + 4.0
