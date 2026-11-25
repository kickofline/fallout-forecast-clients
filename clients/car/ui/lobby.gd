extends Control
## Cloud Play lobby: squad roster, district vote "channels", ready / force
## start, quick chat. Mirrors the original's console layout at 1240x606.

const QUICK = ["READY?", "ONE SEC", "LET'S GO", "GG"]
const CHANNEL_COLORS = [Color("#66dfda"), Color("#9fb8ff"), Color("#ffbf68"), Color("#ff5689")]

var _roster = VBoxContainer.new()
var _roster_head: Label
var _maps_row = HBoxContainer.new()
var _chat = VBoxContainer.new()
var _ready: Button
var _start: Button
var _status: Label
var _me_ready = false
var _my_vote = ""
var _last_maps_key = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var title = UI.label("LOBBY", 56, UI.PAPER)
	title.rect_position = Vector2(40, 14)
	add_child(title)
	_status = UI.label("", 22, UI.CYAN)
	_status.rect_position = Vector2(220, 40)
	add_child(_status)
	var leave = UI.button("LEAVE", self, "_on_leave")
	UI.place(leave, 1.0, 0.0, -190, 22)
	leave.rect_min_size = Vector2(150, 52)
	add_child(leave)

	# Left: squad + chat.
	var left = VBoxContainer.new()
	left.rect_position = Vector2(40, 96)
	left.rect_min_size = Vector2(440, 0)
	left.add_constant_override("separation", 6)
	add_child(left)
	_roster_head = UI.label("SQUAD", 26, UI.MUTED)
	left.add_child(_roster_head)
	_roster.add_constant_override("separation", 4)
	left.add_child(_roster)
	var gap = Control.new()
	gap.rect_min_size = Vector2(0, 8)
	left.add_child(gap)
	left.add_child(UI.label("CHAT", 26, UI.MUTED))
	_chat.add_constant_override("separation", 0)
	_chat.rect_min_size = Vector2(440, 120)
	left.add_child(_chat)
	var quick = HBoxContainer.new()
	quick.add_constant_override("separation", 6)
	left.add_child(quick)
	for q in QUICK:
		var b = UI.button(q, self, "_on_quick", [q])
		b.rect_min_size = Vector2(0, 46)
		b.add_font_override("font", UI.font(22))
		quick.add_child(b)

	# Right: district channels + ready/start.
	var right = VBoxContainer.new()
	right.anchor_left = 0.0
	right.rect_position = Vector2(520, 96)
	right.add_constant_override("separation", 10)
	add_child(right)
	right.add_child(UI.label("VOTE FOR A DISTRICT", 26, UI.MUTED))
	_maps_row.add_constant_override("separation", 10)
	right.add_child(_maps_row)
	var actions = HBoxContainer.new()
	actions.add_constant_override("separation", 10)
	right.add_child(actions)
	_ready = UI.button("READY", self, "_on_ready")
	_ready.rect_min_size = Vector2(330, 70)
	_ready.add_font_override("font", UI.font(34))
	UI.primary(_ready)
	actions.add_child(_ready)
	_start = UI.button("FORCE START", self, "_on_start")
	_start.rect_min_size = Vector2(330, 70)
	_start.add_font_override("font", UI.font(30))
	UI.accent(_start, UI.AMBER)
	actions.add_child(_start)
	Net.connect("lobby_updated", self, "_on_lobby")
	refresh()


func refresh() -> void:
	_on_lobby(Net.lobby)


func _process(_delta: float) -> void:
	var rtt = "%d MS" % int(Net.rtt_ms) if Net.rtt_ms >= 0.0 else "-- MS"
	_status.text = "CLOUD PLAY  ·  ON AIR  ·  " + rtt


func _on_lobby(data: Dictionary) -> void:
	if not is_inside_tree():
		return
	var players: Array = data.get("players", []) if data.get("players") is Array else []
	for c in _roster.get_children():
		c.queue_free()
	_roster_head.text = "SQUAD  %d/4" % players.size()
	for p in players:
		if not (p is Dictionary):
			continue
		var own: bool = int(p.get("id", -1)) == Net.you
		if own:
			_me_ready = bool(p.get("ready", false))
			if p.get("vote") is String:
				_my_vote = p.vote
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 10)
		var dot = ColorRect.new()
		dot.rect_min_size = Vector2(4, 30)
		dot.color = UI.CYAN if own else UI.MUTED.darkened(0.3)
		row.add_child(dot)
		var name = UI.label(str(p.get("name", "PLAYER")).to_upper(), 28, UI.PAPER)
		name.rect_min_size = Vector2(230, 0)
		name.clip_text = true
		row.add_child(name)
		if own or p.get("car") == true:
			row.add_child(UI.label("CAR", 20, UI.AMBER))
		var ready = bool(p.get("ready", false))
		var st = UI.label("READY" if ready else "-", 26, UI.ACID if ready else UI.MUTED)
		st.size_flags_horizontal = SIZE_EXPAND_FILL
		st.align = Label.ALIGN_RIGHT
		row.add_child(st)
		_roster.add_child(row)
	for c in _chat.get_children():
		c.queue_free()
	var chat: Array = data.get("chat", []) if data.get("chat") is Array else []
	for i in range(max(0, chat.size() - 4), chat.size()):
		var line = chat[i]
		if line is Dictionary:
			var l = UI.label("%s: %s" % [str(line.get("from", "")).to_upper(), str(line.get("text", ""))], 22, UI.PAPER)
			l.clip_text = true
			l.rect_min_size = Vector2(440, 0)
			_chat.add_child(l)
	_ready.text = "UNREADY" if _me_ready else "READY"
	var countdown = float(data.get("countdown", -1)) if data.get("countdown") != null else -1.0
	if countdown >= 0.0:
		_ready.text = "STARTING %d" % int(ceil(countdown))
	_build_maps(data)


func _build_maps(data: Dictionary) -> void:
	var counts: Dictionary = data.get("vote_counts", {}) if data.get("vote_counts") is Dictionary else {}
	var players: Array = data.get("players", []) if data.get("players") is Array else []
	if counts.empty():
		for p in players:
			if p is Dictionary and p.get("vote") is String:
				counts[p.vote] = int(counts.get(p.vote, 0)) + 1
	var maps: Array = Net.maps
	var key = to_json([maps, counts, _my_vote])
	if key == _last_maps_key:
		return
	_last_maps_key = key
	for c in _maps_row.get_children():
		c.queue_free()
	var i = 0
	for m in maps:
		if not (m is Dictionary):
			continue
		var id = str(m.get("id", ""))
		var color: Color = CHANNEL_COLORS[i % CHANNEL_COLORS.size()]
		var mine = id == _my_vote
		var card = Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.rect_min_size = Vector2(160, 250)
		var normal = UI.button_box(Color("#3a2016") if mine else Color(0.08, 0.12, 0.16, 0.9), UI.PAPER if mine else Color("#3b5560"), 2, 10, 10)
		normal.border_width_top = 2
		normal.border_width_right = 2
		normal.border_width_bottom = 2
		for s in ["normal", "hover", "pressed"]:
			card.add_stylebox_override(s, normal)
		card.connect("pressed", self, "_on_vote", [id])
		var col = VBoxContainer.new()
		col.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		col.margin_left = 10
		col.margin_top = 8
		col.margin_right = -10
		col.margin_bottom = -8
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_constant_override("separation", 4)
		card.add_child(col)
		col.add_child(UI.label("CHANNEL %02d" % (i + 1), 20, color))
		var thumb = TextureRect.new()
		thumb.rect_min_size = Vector2(140, 84)
		thumb.expand = true
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex = Assets.map_preview(id)
		if tex:
			thumb.texture = tex
		else:
			var ph = ColorRect.new()
			ph.color = color.darkened(0.7)
			ph.rect_min_size = Vector2(140, 84)
			ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(ph)
			thumb = null
		if thumb:
			col.add_child(thumb)
		var nm = UI.label(str(m.get("name", id)).to_upper(), 28, UI.PAPER)
		nm.autowrap = true
		nm.rect_min_size = Vector2(140, 0)
		col.add_child(nm)
		var n = int(counts.get(id, 0))
		var votes = "%d VOTE%s" % [n, "" if n == 1 else "S"]
		if mine:
			votes += " · YOURS"
		col.add_child(UI.label(votes, 20, color))
		_maps_row.add_child(card)
		i += 1


func _on_vote(id: String) -> void:
	_my_vote = id
	_last_maps_key = ""
	Net.lobby_action("vote", {"map": id})
	_build_maps(Net.lobby)


func _on_ready() -> void:
	_me_ready = not _me_ready
	_ready.text = "UNREADY" if _me_ready else "READY"
	Net.lobby_action("ready", {"v": _me_ready})


func _on_start() -> void:
	Net.lobby_action("start")


func _on_quick(text: String) -> void:
	Net.lobby_action("chat", {"text": text})


func _on_leave() -> void:
	Net.leave()
