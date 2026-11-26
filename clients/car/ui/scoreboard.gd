extends Control
## Squad scoreboard (hold Tab / pad Back, and inside the pause menu): run
## line (district, wave, time, infected left, tape counter), one row per
## player (state, health, suit, held item), active squad and enemy
## mutations and feat progress this run. Per-player kills only exist in the
## host's results, so they appear on the results tape. One canvas, drawn
## only while shown and redrawn at 4 Hz.

const ROW_H = 34.0
const W = 640.0

var world: Node
var net: Node
var run_seconds = 0.0
var _left = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect_min_size = Vector2(W, 300)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_left -= delta
	if _left <= 0.0:
		_left = 0.25
		update()


func _map_name() -> String:
	var id = str(net.get("current_map")) if net.get("current_map") != null else ""
	for m in net.maps:
		if m is Dictionary and str(m.get("id", "")) == id:
			return str(m.get("name", id))
	return id.replace("_", " ")


func _rows() -> Array:
	var out = []
	var me = {"name": Settings.player_name, "state": str(world.you.get("state", "ok")), "hp": float(world.you.get("hp", 100.0)),
		"max_hp": float(world.you.get("hp_max", 100.0)), "suit": float(world.you.get("suit", 100.0)), "item": "", "me": true}
	var cur = world.current_slot() if world.has_method("current_slot") else {}
	me.item = str(cur.get("item", ""))
	out.append(me)
	for o in world.others:
		out.append({"name": str(o.name), "state": str(o.state), "hp": float(o.get("hp", 100.0)), "max_hp": float(o.get("max_hp", 100.0)),
			"suit": float(o.get("suit", 100.0)), "item": str(o.get("item", "")), "me": false})
	return out


func _draw() -> void:
	if world == null or not is_instance_valid(world):
		return
	UI.defer_text(self)
	var rows = _rows()
	var h = 96.0 + rows.size() * ROW_H + 70.0
	rect_size = Vector2(W, h)
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.025, 0.045, 0.075, 0.9))
	draw_rect(Rect2(Vector2.ZERO, Vector2(3, h)), UI.CYAN)
	var wave = int(world.run.get("wave", world.weather_state.get("wave", 1)))
	var endless = bool(world.run.get("endless", false))
	var secs = int(run_seconds)
	var line = "%s   ·   %s   ·   %d:%02d" % [_map_name().to_upper(), ("ENDLESS %d" % max(1, wave - 5)) if endless else "WAVE %d/5" % wave, secs / 60, secs % 60]
	UI.draw_text(self, Vector2(18, 32), "SQUAD", 30, UI.PAPER)
	UI.draw_text(self, Vector2(120, 30), line, 22, UI.MUTED)
	var info = "%d INFECTED LEFT" % int(world.run.get("alive_enemies", 0))
	if endless:
		info += "   ·   CNT %08d" % int(world.run.get("score", 0))
	UI.draw_text(self, Vector2(18, 58), info, 20, UI.PINK)
	var y = 92.0
	for h2 in [["CALLSIGN", 18], ["STATE", 250], ["HEALTH", 350], ["SUIT", 450], ["HOLDING", 530]]:
		UI.draw_text(self, Vector2(h2[1], y - 6), h2[0], 18, UI.CYAN)
	for r in rows:
		y += ROW_H
		var col: Color = UI.CYAN if r.me else UI.PAPER
		if r.state == "out":
			col = UI.MUTED
		UI.draw_text(self, Vector2(18, y - 8), str(r.name).to_upper().left(16), 24, col)
		var sc = {"ok": UI.ACID, "downed": UI.PINK, "turned": Color(0.55, 1.0, 0.3), "out": UI.MUTED}.get(r.state, UI.PAPER)
		UI.draw_text(self, Vector2(250, y - 8), str(r.state).to_upper(), 22, sc)
		var hk = clamp(r.hp / max(1.0, r.max_hp), 0.0, 1.0)
		draw_rect(Rect2(350, y - 20, 80, 6), Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.7))
		draw_rect(Rect2(350, y - 20, 80 * hk, 6), UI.PINK)
		draw_rect(Rect2(450, y - 20, 60, 6), Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.7))
		draw_rect(Rect2(450, y - 20, 60 * clamp(r.suit / 100.0, 0.0, 1.0), 6), UI.CYAN)
		var nm = str(net.item(r.item).get("name", r.item)) if not str(r.item).empty() and net.has_method("item") else str(r.item)
		UI.draw_text(self, Vector2(530, y - 8), nm.to_upper().left(12), 20, UI.MUTED)
	y += 34.0
	var muts = []
	var pm = world.get("player_mutations")
	if pm is Array:
		for id in pm:
			muts.append(str(net.player_mutations.get(str(id), {}).get("name", id)).to_upper() if "player_mutations" in net else str(id))
	var em = []
	var emut = world.get("enemy_mutations")
	if emut is Array:
		for id in emut:
			em.append(str(net.enemy_mutations.get(str(id), {}).get("name", id)).to_upper() if "enemy_mutations" in net else str(id))
	UI.draw_text(self, Vector2(18, y), "SQUAD  " + (", ".join(muts) if not muts.empty() else "-"), 20, UI.ACID)
	UI.draw_text(self, Vector2(330, y), "ENEMY  " + (", ".join(em) if not em.empty() else "-"), 20, UI.PINK)
	var feats = world.get("feat_log")
	if feats is Array and not feats.empty():
		UI.draw_text(self, Vector2(18, y + 24), "FEAT PROGRESS THIS RUN  %d" % feats.size(), 18, UI.AMBER)
	UI.flush_text(self)
