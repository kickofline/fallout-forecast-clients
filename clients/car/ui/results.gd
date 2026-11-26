extends Control
## Results tape (native ui/results.gd): "<DISTRICT> IS SAFE / LOST", lit
## wave segments, TIME / WAVES / KILLS / SCORE tallies that count up (any
## key, button or tap skips), the per-player table (kills, revives, turned,
## last weapon) with the MVP in amber, squad mutations and this run's feat
## progress.

const COUNT_TIME = 1.4
const TICK = 0.06

var data = {}
var main: Node
var net: Node = null
var _tallies = []        # [label, value, format]
var _segments = []
var _waves = 0
var _t = 0.0
var _tick_left = 0.0
var _counting = true


func _ready() -> void:
	net = FullNet.current()
	mouse_filter = Control.MOUSE_FILTER_PASS
	var won = bool(data.get("won", false))
	var score = int(data.get("score", 0))
	var endless = score > 0
	_waves = int(data.get("waves", 0))
	var district = _map_name(str(data.get("map", net.current_map))).to_upper()
	var box = VBoxContainer.new()
	box.rect_position = Vector2(80, 28)
	box.add_constant_override("separation", 6)
	add_child(box)
	var stop = HBoxContainer.new()
	stop.add_constant_override("separation", 8)
	stop.add_child(preload("res://ui/glyph.gd").new("stop", UI.MUTED, 16.0))
	stop.add_child(UI.label("STOP", 22, UI.MUTED))
	box.add_child(stop)
	var title = "ENDLESS TAPE COMPLETE" if endless and not won else district + (" IS SAFE" if won else " IS LOST")
	box.add_child(UI.label(title, 60, UI.ACID if won else UI.PINK))
	# Wave segments (campaign).
	var seg_row = HBoxContainer.new()
	seg_row.add_constant_override("separation", 8)
	box.add_child(seg_row)
	for i in 5:
		var seg = UI.label(" %d " % (i + 1), 22, UI.PAPER)
		seg.rect_min_size = Vector2(62, 30)
		seg.align = Label.ALIGN_CENTER
		seg_row.add_child(seg)
		_segments.append(seg)
	if endless:
		seg_row.add_child(UI.label("  + ENDLESS", 22, UI.AMBER))
	# Metrics.
	var metrics = HBoxContainer.new()
	metrics.add_constant_override("separation", 46)
	box.add_child(metrics)
	_metric(metrics, "TIME", int(data.get("time_s", 0)), "clock")
	_metric(metrics, "WAVES", _waves, "number" if endless else "waves")
	_metric(metrics, "KILLS", int(data.get("kills", 0)), "number")
	if endless:
		_metric(metrics, "SCORE", score, "tape")
	# Players.
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_constant_override("hseparation", 34)
	grid.add_constant_override("vseparation", 2)
	box.add_child(grid)
	for h in ["CALLSIGN", "KILLS", "REVIVES", "TURNED", "WEAPON"]:
		grid.add_child(UI.label(h, 20, UI.CYAN))
	var players: Array = data.get("players", []) if data.get("players") is Array else []
	var mvp: Label
	var best = -1
	for p in players:
		if not (p is Dictionary):
			continue
		var own: bool = str(p.get("name", "")).to_upper() == Settings.player_name.to_upper()
		var color: Color = UI.CYAN if own else UI.PAPER
		var nm = UI.label(str(p.get("name", "")).to_upper().left(16), 28, color)
		nm.rect_min_size = Vector2(260, 0)
		grid.add_child(nm)
		for k in ["kills", "revives", "downs"]:
			var v = p.get(k)
			var l = UI.label("-" if v == null else "0", 28, color)
			grid.add_child(l)
			if v != null:
				_tallies.append([l, int(v), "number"])
		grid.add_child(UI.label(str(p.get("weapon", "")).to_upper().left(18), 22, UI.MUTED))
		var contribution = int(p.get("kills", 0)) + 2 * int(p.get("revives", 0))
		if contribution > best:
			best = contribution
			mvp = nm
	if players.size() > 1 and mvp:
		mvp.add_color_override("font_color", UI.AMBER)
		mvp.text += "  MVP"
	# Squad mutations and feat progress.
	var muts = data.get("mutations", [])
	if muts is Array and not muts.empty():
		var names = []
		for m in muts:
			names.append(str(m).to_upper())
		box.add_child(UI.label("SQUAD MUTATIONS  /  " + ", ".join(names), 20, UI.ACID))
	var feats = net.get_meta("run_feats") if net.has_meta("run_feats") else []
	if feats is Array and not feats.empty():
		var tally = {}
		for f in feats:
			tally[str(f[0])] = int(tally.get(str(f[0]), 0)) + int(f[1])
		var parts = []
		for k2 in tally:
			parts.append("%s +%d" % [k2.replace("_", " ").to_upper(), tally[k2]])
		var line = "FEAT PROGRESS  /  " + ", ".join(parts.slice(0, min(3, parts.size()) - 1))
		if parts.size() > 3:
			line += "  +%d MORE" % (parts.size() - 3)
		box.add_child(UI.label(line, 20, UI.AMBER))
		Sound.play("ui_achievement", -9.0)
	var row = HBoxContainer.new()
	UI.place(row, 0.0, 1.0, 80, -96)
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
	_render(0.0)


func _metric(row: Control, caption: String, value: int, fmt: String) -> void:
	var col = VBoxContainer.new()
	col.add_constant_override("separation", -4)
	row.add_child(col)
	var l = UI.label("", 40, UI.PAPER)
	col.add_child(l)
	col.add_child(UI.label(caption, 20, UI.CYAN))
	_tallies.append([l, value, fmt])


func _fmt(v: int, fmt: String) -> String:
	match fmt:
		"clock":
			return "%d:%02d" % [v / 60, v % 60]
		"waves":
			return "%d/5" % v
		"tape":
			return "%08d" % v
	return str(v)


func _render(k: float) -> void:
	for t in _tallies:
		t[0].text = _fmt(int(round(t[1] * k)), t[2])
	var lit = int(round(min(_waves, 5) * k))
	for i in _segments.size():
		var on = i < lit
		var sb = UI.panel(Color("#29545d") if on else UI.PANEL, UI.CYAN if on else UI.MUTED.darkened(0.55))
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		_segments[i].add_stylebox_override("normal", sb)


func _process(delta: float) -> void:
	if not _counting:
		return
	_t += delta
	if _t >= COUNT_TIME:
		_skip()
		return
	var f = _t / COUNT_TIME
	_render(1.0 - pow(1.0 - f, 2.0))
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = TICK
		Sound.play("ui_tick", -18.0, lerp(0.94, 1.14, f))


func _skip() -> void:
	_counting = false
	_render(1.0)


func _input(event: InputEvent) -> void:
	if not _counting or event.is_echo() or not event.is_pressed():
		return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventScreenTouch:
		_skip()
		get_tree().set_input_as_handled()


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
