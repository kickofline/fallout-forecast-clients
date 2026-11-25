extends Control
## ItemHotbar (touch layout): five slots + frag / dome belt pouches, no
## filled boxes; selected cell outlined and raised, tier underline, icon,
## consumable count, scrap counter at the right end.

const CELL = Vector2(72, 66)
const GAP = 5.0
const CELLS = 7
const INK = Color(0.047, 0.078, 0.133, 0.9)
const MUTED = Color("#728b92")
const POUCH_COLORS = [Color("#ff9f6b"), Color("#7aeeff")]
const POUCH_ITEMS = ["frag", "shield_dome"]

var world: Node
var _flash = 0.0
var _state_key = ""
var _scrap_icon: Texture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect_size = Vector2(CELLS * CELL.x + (CELLS - 1) * GAP, CELL.y)


func width() -> float:
	return CELLS * CELL.x + (CELLS - 1) * GAP


func flash() -> void:
	_flash = 1.2


func cell_at(at: Vector2) -> int:
	if not visible:
		return -1
	var local = at - rect_global_position
	for i in CELLS:
		if Rect2(Vector2(i * (CELL.x + GAP) - GAP * 0.5, -10), Vector2(CELL.x + GAP, CELL.y + 20)).has_point(local):
			return i
	return -1


func _process(delta: float) -> void:
	if world == null:
		return
	_flash = max(0.0, _flash - delta)
	var key = to_json([world.you.get("slot"), world.you.get("slots"), world.you.get("scrap"), world.you.get("pouch"),
		world.you.get("grenades"), world.you.get("domes"), int(_flash * 10)])
	if key != _state_key:
		_state_key = key
		update()


func _draw() -> void:
	if world == null:
		return
	var you: Dictionary = world.you
	var slots = you.get("slots")
	if not (slots is Array):
		slots = []
	var current = int(you.get("slot", 1)) - 1
	var pouch = str(you.get("pouch", "")) if you.get("pouch") != null else ""
	for i in 5:
		var item = slots[i] if i < slots.size() else null
		var selected = pouch.empty() and current == i
		var at = Vector2(i * (CELL.x + GAP), -5.0 if selected else 0.0)
		var color: Color = MUTED if not (item is Dictionary) else UI.tier_color(int(item.get("tier", 0)))
		if selected:
			draw_rect(Rect2(at, CELL), Color(color.r, color.g, color.b, 0.14))
			var outline = Color("#ffc365").linear_interpolate(Color("#c7faff"), 1.0 - _flash / 1.2) if _flash > 0.0 else Color("#c7faff")
			draw_rect(Rect2(at, CELL), outline, false, 2.0)
		else:
			draw_rect(Rect2(at, CELL), Color(0.047, 0.078, 0.133, 0.35))
			draw_rect(Rect2(at, CELL), Color(0.43, 0.54, 0.56, 0.4), false, 1.0)
		UI.draw_text(self, at + Vector2(5, 16), str(i + 1), 16, Color(0.91, 0.91, 0.84, 0.8 if selected else 0.45))
		if not (item is Dictionary):
			draw_rect(Rect2(at + Vector2(30, 32), Vector2(12, 2)), Color(color.r, color.g, color.b, 0.5))
			continue
		draw_rect(Rect2(at + Vector2(6, CELL.y - 5), Vector2(CELL.x - 12, 2)), color)
		var id = str(item.get("item", ""))
		var icon = Assets.item_icon(id)
		var alpha = 1.0 if selected else 0.75
		if icon:
			draw_texture_rect(icon, Rect2(at + Vector2(14, 9), Vector2(44, 44)), false, Color(1, 1, 1, alpha))
		else:
			var initials = ""
			for word in str(item.get("name", id)).split(" "):
				initials += word.left(1)
			UI.draw_text_centered(self, at.x + CELL.x * 0.5, at.y + 42, initials.to_upper(), 26, Color(color.r, color.g, color.b, alpha))
		if item.get("ammo") == null:
			UI.draw_text(self, at + Vector2(CELL.x - 22, CELL.y - 9), str(int(item.get("count", 1))), 20, color)
	# Pouches (frag / shield dome): tap to ready, FIRE throws.
	var counts = [int(you.get("grenades", 0)) if you.get("grenades") != null else 0,
		int(you.get("domes", 0)) if you.get("domes") != null else 0]
	for j in 2:
		var at2 = Vector2((5 + j) * (CELL.x + GAP), 0)
		var held = pouch == POUCH_ITEMS[j]
		var c: Color = POUCH_COLORS[j] if counts[j] > 0 else MUTED
		draw_rect(Rect2(at2, CELL), Color(INK.r, INK.g, INK.b, 0.6))
		draw_rect(Rect2(at2, CELL), Color(c.r, c.g, c.b, 0.95 if held else 0.5), false, 2.0 if held else 1.0)
		var icon2 = Assets.item_icon(POUCH_ITEMS[j])
		if icon2:
			draw_texture_rect(icon2, Rect2(at2 + Vector2(15, 6), Vector2(42, 42)), false, Color(1, 1, 1, 1.0 if counts[j] > 0 else 0.45))
		UI.draw_text_centered(self, at2.x + CELL.x * 0.5, at2.y + 61, str(counts[j]), 20, c)
	# Scrap.
	var scrap = str(int(you.get("scrap", 0))) if you.get("scrap") != null else "0"
	var sx = width() + 10.0
	draw_rect(Rect2(Vector2(sx, CELL.y - 22), Vector2(12, 12)), Color("#ffc365"), false, 2.0)
	UI.draw_text(self, Vector2(sx + 18, CELL.y - 9), scrap, 22, Color("#ffc365"))
