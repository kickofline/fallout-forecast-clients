extends Control
## In-run loadout (the native inventory menu, simplified for the car): the
## five slots in hotbar order, belt pouches, reserve ammo and scrap, and a
## stat card for the focused slot. EQUIP / MOVE < / MOVE > / DROP send
## WeaponHolder._action (select, swap, drop_slot) and the host's
## _private_state redraws it. Keyboard, pad (focus_nav) and touch all work.
## Full tier only (it reads world/full_world.gd's `inv`).

signal closed

const SLOT = Vector2(150, 118)
const FocusNav = preload("res://ui/focus_nav.gd")

var world: Node
var net: Node
var sel = 0
var _slots = []
var _card: Control
var _stash: Label
var _rev = -2
var _nav: Node
var _closing = false


func _ready() -> void:
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade = ColorRect.new()
	shade.color = Color(0.025, 0.045, 0.075, 0.86)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(shade)
	var head = UI.label("LOADOUT", 40, UI.PAPER)
	UI.place(head, 0.5, 0.0, -460, 40, 300, 44)
	add_child(head)
	_stash = UI.label("", 22, UI.MUTED)
	UI.place(_stash, 0.5, 0.0, -460, 452, 920, 30)
	add_child(_stash)
	for i in 5:
		var b = Button.new()
		b.focus_mode = Control.FOCUS_ALL
		b.toggle_mode = false
		UI.place(b, 0.5, 0.0, -460 + i * (SLOT.x + 8), 100, SLOT.x, SLOT.y)
		b.connect("pressed", self, "_on_slot", [i])
		b.connect("focus_entered", self, "_select", [i])
		b.connect("draw", self, "_draw_slot", [b, i])
		add_child(b)
		_slots.append(b)
	_card = Control.new()
	UI.place(_card, 0.5, 0.0, -460, 232, 920, 110)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.connect("draw", self, "_draw_card")
	add_child(_card)
	var row = HBoxContainer.new()
	UI.place(row, 0.5, 0.0, -460, 352, 920, 60)
	row.add_constant_override("separation", 10)
	add_child(row)
	var first: Button
	for spec in [["EQUIP", "_equip"], ["MOVE <", "_move", -1], ["MOVE >", "_move", 1], ["DROP", "_drop"], ["CLOSE", "close"]]:
		var b2 = UI.button(spec[0], self, spec[1], [spec[2]] if spec.size() > 2 else [])
		b2.rect_min_size = Vector2(170, 56)
		if spec[0] == "CLOSE":
			UI.accent(b2, UI.MUTED)
		elif spec[0] == "EQUIP":
			UI.primary(b2)
		row.add_child(b2)
	var hint = UI.label(_hint_text(), 20, UI.MUTED)
	UI.place(hint, 0.5, 0.0, -460, 420, 920, 26)
	add_child(hint)
	sel = clamp(int(world.inv.slot), 0, 4)
	UI.focusable(self)
	_nav = FocusNav.new().attach(self)
	_nav.first = _slots[sel]
	_nav.connect("back", self, "close")


func _hint_text() -> String:
	match Controls.device:
		"pad":
			return "D-PAD PICK A SLOT  ·  A SELECT  ·  B CLOSE"
		"kbm":
			return "ARROWS / CLICK PICK A SLOT  ·  ENTER SELECT  ·  %s / ESC CLOSE" % Controls.hint("inventory")
	return "TAP A SLOT, THEN AN ACTION"


func close() -> void:
	if _closing:
		return
	_closing = true
	emit_signal("closed")
	queue_free()


func _process(_delta: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	if Controls.pressed("inventory"):
		Controls.eat("inventory")
		close()
		return
	if int(world.inv.rev) != _rev:
		_rev = int(world.inv.rev)
		_refresh()


func _refresh() -> void:
	for b in _slots:
		b.update()
	_card.update()
	var parts = []
	var stash: Dictionary = world.inv.stash if world.inv.stash is Dictionary else {}
	for k in stash:
		if int(stash[k]) > 0:
			parts.append("%s %d" % [str(k).to_upper().replace("_", " "), int(stash[k])])
	parts.append("FRAG %d" % int(world.inv.frags))
	parts.append("DOME %d" % int(world.inv.domes))
	parts.append("SCRAP %d" % int(world.inv.scrap))
	_stash.text = "   ".join(parts)


func _row(i: int) -> Array:
	var rows: Array = world.inv.rows
	if i >= 0 and i < rows.size() and rows[i] is Array and rows[i].size() >= 4:
		return rows[i]
	return []


func _select(i: int) -> void:
	sel = i
	_refresh()


func _on_slot(i: int) -> void:
	if sel == i:
		_equip()
	_select(i)


func _send(action: String, expected: int, slot: int) -> void:
	net.rpc_send(net.holder_path(), "_action", [world.run_id, action, expected, slot])
	Sound.play("ui_tick", -8.0)


func _equip(_x = null) -> void:
	var row = _row(sel)
	if row.empty():
		return
	_send("select", int(row[0]), sel)


func _move(d: int) -> void:
	var to = sel + d
	var row = _row(sel)
	if row.empty() or to < 0 or to > 4:
		return
	_send("swap", int(row[0]), sel * 5 + to)
	sel = to
	if _slots[to].is_visible_in_tree() and Controls.device != "touch":
		_slots[to].grab_focus()
	_refresh()


func _drop(_x = null) -> void:
	var row = _row(sel)
	if row.empty():
		return
	_send("drop_slot", int(row[0]), sel)


func _draw_slot(b: Button, i: int) -> void:
	var row = _row(i)
	var r = Rect2(Vector2.ZERO, b.rect_size)
	var current = i == int(world.inv.slot) and str(world.inv.pouch).empty()
	b.draw_rect(r, Color(0.047, 0.078, 0.133, 0.8))
	var col: Color = UI.MUTED if row.empty() else UI.tier_color(int(row[2]))
	UI.frame_rect(b, r, Color(col.r, col.g, col.b, 1.0 if i == sel else 0.45), 3.0 if i == sel else 1.0)
	UI.draw_text(b, Vector2(8, 22), str(i + 1), 20, UI.PAPER)
	if current:
		UI.draw_text(b, Vector2(r.size.x - 70, 22), "HELD", 18, UI.CYAN)
	if row.empty():
		UI.draw_text_centered(b, r.size.x * 0.5, 70, "EMPTY", 20, UI.MUTED)
		return
	var id = str(row[1])
	var icon = Assets.item_icon(id)
	if icon:
		b.draw_texture_rect(icon, Rect2(Vector2(r.size.x * 0.5 - 30, 26), Vector2(60, 60)), false)
	var it = net.item(id)
	var nm = str(it.get("name", id)).to_upper()
	UI.draw_text_centered(b, r.size.x * 0.5, r.size.y - 10, nm.left(16), 18, col)
	if str(it.get("kind", "")) != "gun" and int(row[3]) > 1:
		UI.draw_text(b, Vector2(r.size.x - 34, r.size.y - 30), "x%d" % int(row[3]), 18, UI.PAPER)


func _draw_card() -> void:
	var row = _row(sel)
	var r = Rect2(Vector2.ZERO, _card.rect_size)
	_card.draw_rect(r, Color(0.047, 0.078, 0.133, 0.7))
	_card.draw_rect(Rect2(Vector2.ZERO, Vector2(3, r.size.y)), UI.CYAN)
	if row.empty():
		UI.draw_text(_card, Vector2(16, 34), "SLOT %d IS EMPTY" % (sel + 1), 26, UI.MUTED)
		return
	var id = str(row[1])
	var it = net.item(id)
	var tier = int(row[2])
	var col = UI.tier_color(tier)
	UI.draw_text(_card, Vector2(16, 34), str(it.get("name", id)).to_upper(), 30, col)
	UI.draw_text(_card, Vector2(16, 60), ["COMMON", "RARE", "LEGENDARY"][clamp(tier, 0, 2)] + "   " + str(it.get("kind", "")).to_upper(), 20, UI.MUTED)
	var stats = []
	var w = it.get("weapon")
	if w is Dictionary and str(it.get("kind", "")) == "gun":
		var stash: Dictionary = world.inv.stash if world.inv.stash is Dictionary else {}
		stats.append("MAG %d / %d" % [int(row[3]), int(w.get("mag_size", 0))])
		stats.append("RESERVE %d" % int(stash.get(str(it.get("ammo_type", "")), 0)))
		if w.get("damage") != null:
			stats.append("DMG %d%s" % [int(w.damage), (" x%d" % int(w.pellets)) if int(w.get("pellets", 1)) > 1 else ""])
		if float(w.get("fire_interval", 0.0)) > 0.0:
			stats.append("RATE %.1f/S" % (1.0 / float(w.fire_interval)))
		if w.get("reload_time") != null:
			stats.append("RELOAD %.1fS" % float(w.reload_time))
	else:
		stats.append("COUNT %d" % int(row[3]))
	UI.draw_text(_card, Vector2(16, 92), "   ".join(stats), 22, UI.PAPER)
	var desc = str(it.get("desc", it.get("description", "")))
	if not desc.empty():
		UI.draw_text(_card, Vector2(460, 60), desc.left(52), 18, UI.MUTED)
