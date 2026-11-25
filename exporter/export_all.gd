extends SceneTree
## Master Fallout Forecast asset exporter for the Godot 3.6 GLES2 Android car port.
##
## Usage:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path "<game checkout>" \
##     --audio-driver Dummy -s "C:/Users/drewd/fallout-forecast-car/exporter/export_all.gd" \
##     -- --out=C:/Users/drewd/fallout-forecast-car/assets [--only=maps,characters,weapons,audio] [--maps=pinecrest,harbor,maple_hollow]

const DEFAULT_OUT := "C:/Users/drewd/fallout-forecast-car/assets"


func _initialize() -> void:
	# Defer one frame so all game autoloads finish _ready() cleanly.
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	var args := _parse_args()
	var out_dir: String = str(args.out).replace("\\", "/").trim_suffix("/")
	var only: PackedStringArray = args.only
	var map_filter: PackedStringArray = args.maps
	var skip_decimate: bool = args.skip_decimate

	var base_dir := _exporter_dir()
	print("=== Fallout Forecast Asset Exporter ===")
	print("  Exporter dir : ", base_dir)
	print("  Output dir   : ", out_dir)
	if not only.is_empty():
		print("  Sections     : ", ", ".join(only))

	DirAccess.make_dir_recursive_absolute(out_dir)

	var baker: RefCounted = (load(base_dir.path_join("lib/mesh_baker.gd")) as Script).new()
	var map_exp: RefCounted = (load(base_dir.path_join("lib/export_maps.gd")) as Script).new()
	var char_exp: RefCounted = (load(base_dir.path_join("lib/export_characters.gd")) as Script).new()
	var wep_exp: RefCounted = (load(base_dir.path_join("lib/export_weapons.gd")) as Script).new()
	var uia_exp: RefCounted = (load(base_dir.path_join("lib/export_ui_audio.gd")) as Script).new()

	var manifest := _load_existing_manifest(out_dir)
	manifest["schema_version"] = 1
	manifest["target"] = "Godot 3.6 GLES2 / PowerVR SGX 544MP / Android 5.1"
	manifest["exported_at_unix"] = int(Time.get_unix_time_from_system())

	if only.is_empty() or "maps" in only:
		var maps_res: Dictionary = await map_exp.export_maps(self, baker, out_dir, map_filter, skip_decimate)
		if not manifest.has("maps") or map_filter.is_empty():
			manifest["maps"] = maps_res
		else:
			for k in maps_res:
				manifest["maps"][k] = maps_res[k]
		manifest["environments"] = "maps/environments.json"

	if only.is_empty() or "characters" in only:
		var chars_res: Dictionary = await char_exp.export_characters(self, baker, out_dir)
		manifest["enemies"] = chars_res.enemies
		manifest["players"] = chars_res.players
		manifest["cosmetics"] = "characters/cosmetics.json"

	if only.is_empty() or "weapons" in only:
		var wep_res: Dictionary = await wep_exp.export_weapons_and_props(self, baker, out_dir)
		manifest["weapons"] = wep_res.weapons
		manifest["props"] = wep_res.props
		manifest["projectiles"] = wep_res.projectiles
		manifest["weapons_metadata"] = "weapons/weapons.json"

	if only.is_empty() or "audio" in only or "ui" in only:
		var uia_res: Dictionary = uia_exp.export_ui_and_audio(baker, out_dir)
		manifest["fonts"] = uia_res.fonts
		manifest["ui"] = {
			"items": uia_res.ui_items,
			"screens": uia_res.ui_screens,
		}
		manifest["audio"] = {
			"sound_map": uia_res.sound_map,
			"music": uia_res.music,
			"sfx_count": uia_res.sfx_count,
		}

	var total_bytes := _dir_total_bytes(out_dir)
	manifest["total_bytes"] = total_bytes
	manifest["total_mb"] = snappedf(float(total_bytes) / 1048576.0, 0.01)

	baker.write_json(out_dir.path_join("manifest.json"), manifest)

	var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0
	print("=== Export complete in %.1fs — total assets/: %.2f MB ===" % [elapsed, manifest.total_mb])
	quit(0)


func _exporter_dir() -> String:
	var sp := (get_script() as Script).resource_path
	if not sp.is_empty():
		return sp.get_base_dir()
	var cmd := OS.get_cmdline_args()
	for i in cmd.size() - 1:
		if cmd[i] == "-s" or cmd[i] == "--script":
			return cmd[i + 1].replace("\\", "/").get_base_dir()
	return "C:/Users/drewd/fallout-forecast-car/exporter"


func _parse_args() -> Dictionary:
	var out_dir := DEFAULT_OUT
	var only := PackedStringArray()
	var maps := PackedStringArray()
	var skip_decimate := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7).split(",", false)
		elif arg.begins_with("--maps="):
			maps = arg.substr(7).split(",", false)
		elif arg == "--skip-decimate":
			skip_decimate = true
	return {"out": out_dir, "only": only, "maps": maps, "skip_decimate": skip_decimate}


func _load_existing_manifest(out_dir: String) -> Dictionary:
	var p := out_dir.path_join("manifest.json")
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _dir_total_bytes(path: String) -> int:
	var total := 0
	var da := DirAccess.open(path)
	if da == null:
		return 0
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path.path_join(name)
			if da.current_is_dir():
				total += _dir_total_bytes(full)
			else:
				var f := FileAccess.open(full, FileAccess.READ)
				if f:
					total += f.get_length()
					f.close()
		name = da.get_next()
	da.list_dir_end()
	return total
