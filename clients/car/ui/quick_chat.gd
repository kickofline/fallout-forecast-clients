extends Control
## In-run chat: controller-friendly quick messages plus a text line for a
## keyboard (or the Android on-screen keyboard), with the recent squad chat.
## Sends Net._request_chat through the session's lobby_action("chat").

signal closed

const QUICK = ["NEED HEALS", "REGROUP ON ME", "GET TO SHELTER", "DOWNED, HELP", "AMMO HERE", "NICE SHOT", "ON MY WAY", "THANKS"]
const FocusNav = preload("res://ui/focus_nav.gd")

var net: Node
var _edit = LineEdit.new()
var _log: Label
var _closing = false
var _seen = -1


func _ready() -> void:
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade = ColorRect.new()
	shade.color = Color(0.025, 0.045, 0.075, 0.82)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(shade)
	var head = UI.label("SQUAD CHAT", 36, UI.PAPER)
	UI.place(head, 0.5, 0.0, -460, 36, 400, 40)
	add_child(head)
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_constant_override("hseparation", 10)
	grid.add_constant_override("vseparation", 10)
	UI.place(grid, 0.5, 0.0, -460, 90, 920, 130)
	add_child(grid)
	var first: Button
	for q in QUICK:
		var b = UI.button(q, self, "_send", [q])
		b.rect_min_size = Vector2(222, 56)
		grid.add_child(b)
		if first == null:
			first = b
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 10)
	UI.place(row, 0.5, 0.0, -460, 232, 920, 56)
	add_child(row)
	_edit.placeholder_text = "TYPE A MESSAGE"
	_edit.max_length = 100
	_edit.rect_min_size = Vector2(560, 56)
	_edit.connect("text_entered", self, "_on_entered")
	row.add_child(_edit)
	var send = UI.button("SEND", self, "_on_send_pressed")
	send.rect_min_size = Vector2(160, 56)
	UI.primary(send)
	row.add_child(send)
	var close_b = UI.button("CLOSE", self, "close")
	close_b.rect_min_size = Vector2(170, 56)
	UI.accent(close_b, UI.MUTED)
	row.add_child(close_b)
	_log = UI.label("", 22, UI.PAPER)
	UI.place(_log, 0.5, 0.0, -460, 300, 920, 170)
	_log.valign = Label.VALIGN_BOTTOM
	_log.clip_text = true
	add_child(_log)
	UI.focusable(self)
	var nav = FocusNav.new().attach(self)
	nav.first = first
	nav.connect("back", self, "close")
	if Controls.device == "kbm":
		_edit.call_deferred("grab_focus")


func _process(_delta: float) -> void:
	var chat: Array = net.get("chat") if net.get("chat") is Array else []
	if chat.size() != _seen:
		_seen = chat.size()
		var lines = []
		for i in range(max(0, chat.size() - 6), chat.size()):
			var m = chat[i]
			if m is Dictionary:
				lines.append("%s: %s" % [str(m.get("from", "")).to_upper(), str(m.get("text", ""))])
		_log.text = "\n".join(lines)


func _send(text: String) -> void:
	text = text.strip_edges()
	if text.empty():
		return
	net.lobby_action("chat", {"text": text.substr(0, 100)})
	close()


func _on_entered(text: String) -> void:
	_send(text)


func _on_send_pressed() -> void:
	_send(_edit.text)


func close() -> void:
	if _closing:
		return
	_closing = true
	emit_signal("closed")
	queue_free()
