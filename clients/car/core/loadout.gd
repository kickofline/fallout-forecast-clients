extends Reference
## Full-tier loadout: starter kit, suit colour and skin, and the feats that
## unlock colours and skins (the native game's game/feats.gd suit-unlock rows).
## Progress comes from the host's GameManager/Feats._feat_event and lives in
## user://car_feats.cfg on this device, like the native client's settings.
## Static helpers only; the lobby and title use them for their pickers and
## core/full_net.gd sends unlocked_colors() in Net._hello.

const PATH = "user://car_feats.cfg"
const STARTERS = [["pump_shotgun", "SHOTGUN"], ["nail_driver", "NAIL DRIVER"], ["service_revolver", "REVOLVER"]]
const COLOR_NAMES = ["HAZMAT YELLOW", "TEAL", "HOT PINK", "LIME", "ORANGE", "PURPLE", "WHITE", "RED", "STORM BLUE", "RUST"]
const COLOR_HEX = ["#ffd933", "#2ec9c9", "#ff4fa3", "#9be04a", "#ff8a2a", "#9a6bff", "#e6e9ec", "#e8423a", "#3d7bff", "#b5653a"]
const SKINS = ["STANDARD", "GAS MASK", "FIREFIGHTER", "BIO-TECH", "ION RIG"]
# Feat id -> [goal, reward kind, reward index, name, requires]
const UNLOCKS = {
	"main_street": [1, "color", 2, "MAIN STREET MATINEE", []],
	"low_tide": [1, "color", 5, "LOW TIDE", []],
	"sunday_service": [1, "color", 4, "SUNDAY SERVICE", []],
	"silver_lining": [1, "color", 8, "SILVER LINING", []],
	"triple_feature": [3, "color", 9, "TRIPLE FEATURE", ["main_street", "low_tide", "sunday_service"]],
	"cold_shoulder": [50, "color", 3, "COLD SHOULDER", []],
	"first_responder": [25, "skin", 2, "FIRST RESPONDER", []],
	"clean_bill": [1, "skin", 3, "CLEAN BILL OF HEALTH", []],
	"late_late_show": [1, "skin", 4, "LATE LATE SHOW", []],
}

static func _load() -> ConfigFile:
	var cfg = ConfigFile.new()
	cfg.load(PATH)
	return cfg


static func is_done(id: String, cfg = null) -> bool:
	if cfg == null:
		cfg = _load()
	return bool(cfg.get_value("done", id, false))


static func _feat_for(kind: String, index: int) -> String:
	for id in UNLOCKS:
		if UNLOCKS[id][1] == kind and int(UNLOCKS[id][2]) == index:
			return id
	return ""


static func color_unlocked(index: int, cfg = null) -> bool:
	var f = _feat_for("color", posmod(index, COLOR_NAMES.size()))
	return f.empty() or is_done(f, cfg)


static func skin_unlocked(index: int, cfg = null) -> bool:
	var f = _feat_for("skin", posmod(index, SKINS.size()))
	return f.empty() or is_done(f, cfg)


static func unlocked_colors() -> Array:
	var cfg = _load()
	var out = []
	for i in COLOR_NAMES.size():
		if color_unlocked(i, cfg):
			out.append(i)
	return out


## Next unlocked colour/skin index after `cur` in direction `d`.
static func cycle(kind: String, cur: int, d: int) -> int:
	var n = COLOR_NAMES.size() if kind == "color" else SKINS.size()
	var cfg = _load()
	for step in range(1, n + 1):
		var i = posmod(cur + d * step, n)
		if (color_unlocked(i, cfg) if kind == "color" else skin_unlocked(i, cfg)):
			return i
	return cur


static func lock_text(kind: String, index: int) -> String:
	var f = _feat_for(kind, index)
	if f.empty():
		return ""
	var cfg = _load()
	return "%s (%d/%d)" % [UNLOCKS[f][3], int(cfg.get_value("progress", f, 0)), int(UNLOCKS[f][0])]


## GameManager/Feats._feat_event(id, amount): returns unlock names just earned.
static func feat_event(id: String, amount: int) -> Array:
	var out = []
	if not UNLOCKS.has(id) or amount <= 0 or not (UNLOCKS[id][4] as Array).empty():
		return out
	var cfg = _load()
	if is_done(id, cfg):
		return out
	var count = int(cfg.get_value("progress", id, 0)) + amount
	cfg.set_value("progress", id, min(count, int(UNLOCKS[id][0])))
	if count >= int(UNLOCKS[id][0]):
		cfg.set_value("done", id, true)
		out.append(_reward(id))
		for other in UNLOCKS:
			var req: Array = UNLOCKS[other][4]
			if req.empty() or is_done(other, cfg):
				continue
			var all = true
			for r in req:
				all = all and is_done(r, cfg)
			if all:
				cfg.set_value("done", other, true)
				out.append(_reward(other))
	cfg.save(PATH)
	return out


static func _reward(id: String) -> String:
	var u = UNLOCKS[id]
	return (COLOR_NAMES[int(u[2])] + " SUIT") if u[1] == "color" else (SKINS[int(u[2])] + " SKIN")


static func starter_label(i: int) -> String:
	return STARTERS[clamp(i, 0, 2)][1]
