extends Control
## Results tape: "<DISTRICT> IS SAFE / LOST", run stats, per-player table.

var data = {}
var main: Node
var net: Node = null


func _ready() -> void:
	net = FullNet.current()
	mouse_filter = Control.MOUSE_FILTER_PASS
	var won = bool(data.get("won", false))
	var district = _map_name(str(data.get("map", net.current_map))).to_upper()
	var box = VBoxContainer.new()
	box.rect_position = Vector2(80, 40)
	box.add_constant_override("separation", 6)
	add_child(box)
	var stop = HBoxContainer.new()
	stop.add_constant_override("separation", 8)
	stop.add_child(preload("res://ui/glyph.gd").new("stop", UI.MUTED, 16.0))
	stop.add_child(UI.label("STOP", 22, UI.MUTED))
	box.add_child(stop)
	var title = "ENDLESS TAPE COMPLETE" if int(data.get("score", 0)) > 0 and not won else district + (" IS SAFE" if won else " IS LOST")
	box.add_child(UI.label(title, 64, UI.ACID if won else UI.PINK))
	var secs = int(data.get("time_s", 0))
	var line = "WAVES %d   ·   TIME %d:%02d   ·   INFECTED %d" % [int(data.get("waves", 0)), secs / 60, secs % 60, int(data.get("kills", 0))]
	if int(data.get("score", 0)) > 0:
		line += "   ·   CNT %08d" % int(data.get("score", 0))
	box.add_child(UI.label(line, 28, UI.PAPER))
	var gap = Control.new()
	gap.rect_min_size = Vector2(0, 14)
	box.add_child(gap)
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_constant_override("hseparation", 40)
	grid.add_constant_override("vseparation", 4)
	box.add_child(grid)
	for h in ["CALLSIGN", "INFECTED", "DOWNS", "REVIVES"]:
		grid.add_child(UI.label(h, 22, UI.MUTED))
	var players: Array = data.get("players", []) if data.get("players") is Array else []
	for p in players:
		if not (p is Dictionary):
			continue
		var own: bool = str(p.get("name", "")).to_upper() == Settings.player_name.to_upper()
		var color: Color = UI.CYAN if own else UI.PAPER
		var nm = UI.label(str(p.get("name", "")).to_upper(), 30, color)
		nm.rect_min_size = Vector2(300, 0)
		grid.add_child(nm)
		for k in ["kills", "downs", "revives"]:
			var v = p.get(k)
			grid.add_child(UI.label("-" if v == null else str(int(v)), 30, color))
	var row = HBoxContainer.new()
	UI.place(row, 0.0, 1.0, 80, -110)
	row.add_constant_override("separation", 12)
	add_child(row)
	var back = UI.button("BACK TO LOBBY", self, "_on_back")
	back.rect_min_size = Vector2(320, 64)
	UI.primary(back)
	row.add_child(back)
	var leave = UI.button("LEAVE", self, "_on_leave")
	leave.rect_min_size = Vector2(180, 64)
	row.add_child(leave)
	Sound.play("results_win" if won else "results_loss")
	UI.focusable(self)
	var nav = preload("res://ui/focus_nav.gd").new().attach(self)
	nav.first = back
	nav.connect("back", self, "_on_back")


func _map_name(id: String) -> String:
	for m in net.maps:
		if m is Dictionary and str(m.get("id", "")) == id:
			return str(m.get("name", id))
	return id.replace("_", " ")


func _on_back() -> void:
	if main:
		main.back_to_lobby()


func _on_leave() -> void:
	if main:
		main.back_to_lobby()
	net.leave()
