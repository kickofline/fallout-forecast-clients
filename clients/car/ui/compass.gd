extends Control
## ui/compass.gd port. North is -Z, east is +X. No backing box: baseline,
## ticks, cardinals, infected / elite / boss / teammate markers, objectives.

const ARC = 90.0
const RANGE = 45.0
const INFECTED = Color("#ff554f")
const OBJECTIVE = Color("#ffd56a")
const CARDINALS = ["N", "E", "S", "W"]

var world: Node
var _heading = 0.0
var _cam = Vector3.ZERO
var _warn_left = 0.0
var _warn_at = Vector3.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect_size = Vector2(360, 50)


var _sig = []


func warn(at: Vector3) -> void:
	_warn_at = at
	_warn_left = 2.5


func _process(delta: float) -> void:
	var _pt = OS.get_ticks_usec()
	_process_body(delta)
	Settings.prof_add("compass", OS.get_ticks_usec() - _pt)


func _process_body(delta: float) -> void:
	if world == null:
		return
	_warn_left = max(0.0, _warn_left - delta)
	_heading = fposmod(rad2deg(-world.yaw), 360.0)
	_cam = world.camera.global_transform.origin
	var busy = _warn_left > 0.0 or not world.enemy_points.empty()
	modulate.a = move_toward(modulate.a, 1.0 if busy else 0.6, delta * 3.0)
	var sig = [int(_heading * 4.0), int(_cam.x * 2.0), int(_cam.z * 2.0), int(_warn_left * 10.0), world.enemy_points.size()]
	for e in world.enemy_points:
		sig.append(int(e[0].x * 2.0) + int(e[0].z * 2.0) * 1000)
	if sig != _sig:
		_sig = sig
		update()


func _offset(at: Vector3) -> float:
	var d = at - _cam
	return wrapf(rad2deg(atan2(d.x, -d.z)) - _heading, -180.0, 180.0)


func _x(angle: float) -> float:
	return rect_size.x * 0.5 + clamp(angle / ARC, -1.0, 1.0) * (rect_size.x * 0.5 - 10.0)


func _draw() -> void:
	var _pt = OS.get_ticks_usec()
	_draw_body()
	Settings.prof_add("compass_draw", OS.get_ticks_usec() - _pt)


func _draw_body() -> void:
	if world == null:
		return
	draw_rect(Rect2(0, 22.5, rect_size.x, 1.0), Color(UI.MUTED.r, UI.MUTED.g, UI.MUTED.b, 0.25))
	var first = int(floor((_heading - ARC) / 15.0))
	for i in range(first, first + 14):
		var bearing = i * 15
		var off = float(bearing) - _heading
		if abs(off) > ARC:
			continue
		var x = _x(off)
		var major = posmod(bearing, 45) == 0
		var deg = posmod(bearing, 360)
		var fade = 1.0 - abs(off) / ARC * 0.7
		var top = 17.0 if major else 20.0
		draw_rect(Rect2(x - 0.5, top, 1.0, 23.0 - top), Color(UI.MUTED.r, UI.MUTED.g, UI.MUTED.b, 0.7 * fade))
		if deg % 90 == 0:
			UI.draw_text_centered(self, clamp(x, 12.0, rect_size.x - 12.0), 14, CARDINALS[deg / 90], 20, Color(UI.PAPER.r, UI.PAPER.g, UI.PAPER.b, fade))
	if _warn_left > 0.0:
		var wx = _x(_offset(_warn_at))
		var pulse = 0.76 if Settings.reduced_flash else 0.58 + 0.30 * sin(_warn_left * TAU * 2.0)
		draw_colored_polygon(PoolVector2Array([Vector2(max(0.0, wx - 12), 0), Vector2(min(rect_size.x, wx + 12), 0), Vector2(wx, 18)]),
			Color(INFECTED.r, INFECTED.g, INFECTED.b, pulse * min(1.0, _warn_left * 3.0)))
	for e in world.enemy_points:
		var at: Vector3 = e[0]
		var dist = _cam.distance_to(at)
		if dist > RANGE:
			continue
		var kind = "boss" if e[1] == "cumulus" else ("elite" if e[2] != null or e[1] in ["hailstone", "thunderhead", "cloudburst"] else "infected")
		_marker(at, kind, dist)
	for o in world.others:
		if o.state in ["ok", "downed"]:
			_marker(o.pos, "teammate", _cam.distance_to(o.pos))
	var nearest = null
	var best = 10.0
	for p in world.pickups_list:
		if p is Dictionary and str(p.get("kind", "")) in ["airdrop", "station"]:
			var pos: Vector3 = world._v(p.get("pos"))
			var ang = _offset(pos)
			var pt = Vector2(_x(ang), 24.0)
			if abs(ang) > ARC:
				_edge(pt, ang, OBJECTIVE)
			elif p.kind == "airdrop":
				UI.ring(self, pt + Vector2(0, -1), 6.0, PI, TAU, OBJECTIVE, 1.5, 8)
				draw_rect(Rect2(pt + Vector2(-2, 3), Vector2(4, 4)), OBJECTIVE)
			else:
				UI.frame_rect(self, Rect2(pt - Vector2(5, 5), Vector2(10, 10)), OBJECTIVE, 1.5)
			if abs(ang) <= best:
				best = abs(ang)
				nearest = pos
	if nearest != null:
		UI.draw_text_centered(self, clamp(_x(_offset(nearest)), 16.0, rect_size.x - 16.0), 44, "%dm" % int(round(_cam.distance_to(nearest))), 18, OBJECTIVE)
	var cx = rect_size.x * 0.5
	draw_colored_polygon(PoolVector2Array([Vector2(cx - 4, 30), Vector2(cx, 25), Vector2(cx + 4, 30)]), UI.CYAN)


func _marker(at: Vector3, kind: String, dist: float) -> void:
	var ang = _offset(at)
	var prox = 1.0 - clamp(dist / RANGE, 0.0, 1.0)
	var color = INFECTED
	if kind in ["elite", "boss"]:
		color = UI.PINK
	elif kind == "teammate":
		color = UI.CYAN
	color.a = lerp(0.56, 1.0, prox)
	var pt = Vector2(_x(ang), 25.0)
	if abs(ang) > ARC:
		_edge(pt, ang, color)
		return
	var r: float = lerp(2.5, 4.4, prox)
	match kind:
		"teammate":
			draw_circle(pt, r * 0.68, color)
		"infected":
			draw_circle(pt, r, color)
		"elite":
			_diamond(pt, r + 1.5, color)
		"boss":
			_diamond(pt, r + 4, color)
			draw_circle(pt, 2.0, UI.PAPER)


func _edge(at: Vector2, angle: float, color: Color) -> void:
	var inward = -sign(angle)
	UI.seg(self, at + Vector2(inward * 4, -3), at, color, 1.8)
	UI.seg(self, at, at + Vector2(inward * 4, 3), color, 1.8)


func _diamond(at: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PoolVector2Array([at + Vector2.UP * r, at + Vector2.RIGHT * r, at + Vector2.DOWN * r, at + Vector2.LEFT * r]), color)
