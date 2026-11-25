extends Node
## Manifest-driven asset lookup (assets/manifest.json, schema_version 1).
## tools/sync_assets.py copies the repo's top-level assets/ into
## res://assets/. Every getter returns null / {} when something is missing so
## the world can fall back to procedural placeholders.

const ROOT = "res://assets/"

var manifest = {}
var environments = {}
var cosmetics = {}
var _cache = {}
var _json = {}


func _ready() -> void:
	reload()


func reload() -> void:
	manifest = read_json(ROOT + "manifest.json")
	_cache.clear()
	_json.clear()
	var env_path = manifest.get("environments")
	environments = read_json(path(env_path)) if env_path is String else {}
	var cos_path = manifest.get("cosmetics")
	cosmetics = read_json(path(cos_path)) if cos_path is String else {}


func has_manifest() -> bool:
	return not manifest.empty()


func path(rel) -> String:
	var s = str(rel)
	if s.begins_with("res://"):
		return s
	return ROOT + s


func entry(section: String, id: String) -> Dictionary:
	var block = manifest.get(section)
	if block is Dictionary:
		var e = block.get(id)
		if e is Dictionary:
			return e
	elif block is Array:
		for e in block:
			if e is Dictionary and str(e.get("id", "")) == id:
				return e
	return {}


func ids(section: String) -> Array:
	var block = manifest.get(section)
	return block.keys() if block is Dictionary else []


func load_scene(rel) -> PackedScene:
	if not (rel is String) or rel.empty():
		return null
	var p = path(rel)
	if _cache.has(p):
		return _cache[p]
	var res: PackedScene = null
	if ResourceLoader.exists(p):
		res = load(p) as PackedScene
	_cache[p] = res
	return res


func load_texture(rel) -> Texture:
	if not (rel is String) or rel.empty():
		return null
	var p = path(rel)
	if _cache.has(p):
		return _cache[p]
	var tex: Texture = null
	if ResourceLoader.exists(p):
		tex = load(p) as Texture
	_cache[p] = tex
	return tex


# ------------------------------------------------------------------ maps
func map_scene(id: String, low := false) -> PackedScene:
	var e = entry("maps", id)
	if low and e.get("low_glb") is String:
		var s = load_scene(e.low_glb)
		if s:
			return s
	return load_scene(e.get("glb"))


func map_sidecar(id: String) -> Dictionary:
	var e = entry("maps", id)
	var key = "sidecar/" + id
	if not _json.has(key):
		_json[key] = read_json(path(e.get("sidecar"))) if e.get("sidecar") is String else {}
	return _json[key]


func map_environment(id: String) -> Dictionary:
	var env = environments.get(id)
	if env is Dictionary:
		return env
	var side = map_sidecar(id)
	return side.get("environment", {}) if side.get("environment") is Dictionary else {}


func map_preview(id: String) -> Texture:
	var name = "title_street" if id == "pinecrest" else id
	return load_texture("ui/%s.png" % name)


# ------------------------------------------------------------------ characters
func enemy_scene(type: String) -> PackedScene:
	return load_scene(entry("enemies", type).get("glb"))


func enemy_info(type: String) -> Dictionary:
	return entry("enemies", type)


## Player model id "<skin>_<color>" from the bridge's skin name and suit hex.
func player_model_id(skin, suit_hex) -> String:
	var skin_id = "standard"
	var s = str(skin).to_lower().replace("-", "_").replace(" ", "_")
	for k in cosmetics.get("skins", []):
		if k is Dictionary and (str(k.get("id")) == s or str(k.get("name", "")).to_lower().replace("-", "_").replace(" ", "_") == s):
			skin_id = str(k.id)
	var color_id = "teal"
	if suit_hex is String and suit_hex.begins_with("#"):
		var want = Color(suit_hex)
		var best = 99.0
		for c in cosmetics.get("colors", []):
			if c is Dictionary:
				var cc = Color(str(c.get("hex", "#ffffff")))
				var d: float = abs(cc.r - want.r) + abs(cc.g - want.g) + abs(cc.b - want.b)
				if d < best:
					best = d
					color_id = str(c.get("id", color_id))
	return "%s_%s" % [skin_id, color_id]


func player_scene(model_id: String) -> PackedScene:
	var e = entry("players", model_id)
	if e.empty():
		e = entry("players", "standard_teal")
	return load_scene(e.get("glb"))


# ------------------------------------------------------------------ items
func weapon(id: String) -> Dictionary:
	return entry("weapons", id)


func weapon_view(id: String) -> PackedScene:
	return load_scene(weapon(id).get("view_glb"))


func weapon_pickup(id: String) -> PackedScene:
	return load_scene(weapon(id).get("pickup_glb"))


func prop_scene(id: String) -> PackedScene:
	return load_scene(entry("props", id).get("glb"))


func projectile_scene(kind: String) -> PackedScene:
	var e = entry("projectiles", kind)
	if e.empty() and kind == "spore":
		e = entry("projectiles", "spore_glob")
	return load_scene(e.get("glb"))


func item_icon(id: String) -> Texture:
	return load_texture("ui/items/%s.png" % id)


func font_path() -> String:
	var p = path("fonts/VT323-Regular.ttf")
	if ResourceLoader.exists(p):
		return p
	return "res://fonts/VT323-Regular.ttf"


func sound_map() -> Dictionary:
	var a = manifest.get("audio")
	if a is Dictionary and a.get("sound_map") is String:
		var key = "sound_map"
		if not _json.has(key):
			_json[key] = read_json(path(a.sound_map))
		return _json[key]
	return {}


func read_json(p) -> Dictionary:
	if not (p is String) or p.empty():
		return {}
	var f = File.new()
	if not f.file_exists(p) or f.open(p, File.READ) != OK:
		return {}
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error == OK and parsed.result is Dictionary:
		return parsed.result
	return {}
