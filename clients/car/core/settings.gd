extends Node
## Persistent car-client settings (user://car_settings.cfg).

signal changed

const PATH = "user://car_settings.cfg"
const DEFAULT_URL = "wss://fallout-thin.drew.place/"

var player_name = "Honda"
var server_url = DEFAULT_URL
var look_sensitivity = 1.0      # multiplier on the base touch look rate
var invert_y = false
var render_scale = 0.5          # 3D viewport scale when retro is off
var retro_enabled = true        # PS1/VHS look: low-res 3D + VHS post
var retro_lines = 240           # virtual vertical resolution in retro mode
var fog_quality = 1             # 0 off-ish (thin), 1 normal, 2 dense (original)
var particle_density = 0.6      # rain/fx particle multiplier
var fps_overlay = true
var reduced_flash = false
var volume = 0.8
var hud_scale = 1.0
var button_size = 1.0
var interp_ms = 100
var map_detail = 2               # 0 low (decimated), 1 full, 2 auto (low on Android)


func _ready() -> void:
	load_settings()
	_apply_volume()


func load_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = str(cfg.get_value("player", "name", player_name))
	server_url = str(cfg.get_value("net", "server_url", server_url))
	interp_ms = int(cfg.get_value("net", "interp_ms", interp_ms))
	look_sensitivity = float(cfg.get_value("input", "look_sensitivity", look_sensitivity))
	invert_y = bool(cfg.get_value("input", "invert_y", invert_y))
	button_size = float(cfg.get_value("input", "button_size", button_size))
	render_scale = float(cfg.get_value("video", "render_scale", render_scale))
	retro_enabled = bool(cfg.get_value("video", "retro", retro_enabled))
	retro_lines = int(cfg.get_value("video", "retro_lines", retro_lines))
	fog_quality = int(cfg.get_value("video", "fog_quality", fog_quality))
	map_detail = int(cfg.get_value("video", "map_detail", map_detail))
	particle_density = float(cfg.get_value("video", "particles", particle_density))
	fps_overlay = bool(cfg.get_value("video", "fps_overlay", fps_overlay))
	reduced_flash = bool(cfg.get_value("video", "reduced_flash", reduced_flash))
	hud_scale = float(cfg.get_value("video", "hud_scale", hud_scale))
	volume = float(cfg.get_value("audio", "volume", volume))


func save() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("net", "server_url", server_url)
	cfg.set_value("net", "interp_ms", interp_ms)
	cfg.set_value("input", "look_sensitivity", look_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("input", "button_size", button_size)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "retro", retro_enabled)
	cfg.set_value("video", "retro_lines", retro_lines)
	cfg.set_value("video", "fog_quality", fog_quality)
	cfg.set_value("video", "map_detail", map_detail)
	cfg.set_value("video", "particles", particle_density)
	cfg.set_value("video", "fps_overlay", fps_overlay)
	cfg.set_value("video", "reduced_flash", reduced_flash)
	cfg.set_value("video", "hud_scale", hud_scale)
	cfg.set_value("audio", "volume", volume)
	cfg.save(PATH)
	_apply_volume()
	emit_signal("changed")


func flash_scale() -> float:
	return 0.35 if reduced_flash else 1.0


func _apply_volume() -> void:
	var bus = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear2db(max(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, volume <= 0.001)


var _args = null


## Command-line args plus user://test_args.txt (one per line). The file lets
## tests pass flags on Android, where the Godot 3 template takes none.
func args() -> Array:
	if _args != null:
		return _args
	_args = []
	for a in OS.get_cmdline_args():
		_args.append(str(a))
	var f = File.new()
	if f.file_exists("user://test_args.txt") and f.open("user://test_args.txt", File.READ) == OK:
		for line in f.get_as_text().split(char(10)):
			var t = line.strip_edges()
			if not t.empty():
				_args.append(t)
		f.close()
	return _args


## Command-line overrides for tests: --url=ws://... --name=... --no-retro --scale=0.5
func apply_cmdline() -> void:
	for arg in args():
		var a = str(arg)
		if a.begins_with("--url="):
			server_url = a.substr(6)
		elif a.begins_with("--name="):
			player_name = a.substr(7)
		elif a == "--no-retro":
			retro_enabled = false
		elif a == "--retro":
			retro_enabled = true
		elif a.begins_with("--scale="):
			render_scale = float(a.substr(8))
		elif a.begins_with("--lines="):
			retro_lines = int(a.substr(8))
		elif a.begins_with("--detail="):
			map_detail = int(a.substr(9))
		elif a.begins_with("--particles="):
			particle_density = float(a.substr(12))
