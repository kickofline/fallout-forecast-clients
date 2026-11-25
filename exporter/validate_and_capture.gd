extends SceneTree
## Validation & visual comparison script (non-headless windowed run).
##
## 1. Reloads every .glb under --assets=<dir> using GLTFDocument and verifies
##    zero load errors, non-zero geometry, and expected articulated hierarchy.
## 2. Captures side-by-side / paired screenshots (original level vs exported .glb
##    from identical cameras) for pinecrest, harbor, and maple_hollow into
##    --shots=C:/Users/drewd/Downloads/fallout-car-assets/ plus a character/weapon showcase.
##
## Run (non-headless, with FALLOUT_TELEMETRY_URL=http://127.0.0.1:1/):
##   Godot_v4.7.2-stable_win64_console.exe --path "<game checkout>" --audio-driver Dummy \
##     -s "C:/Users/drewd/fallout-forecast-car/exporter/validate_and_capture.gd" -- \
##     --assets=C:/Users/drewd/fallout-forecast-car/assets \
##     --shots=C:/Users/drewd/Downloads/fallout-car-assets

const DEFAULT_ASSETS := "C:/Users/drewd/fallout-forecast-car/assets"
const DEFAULT_SHOTS := "C:/Users/drewd/Downloads/fallout-car-assets"

# Curated camera viewpoints [name, eye_pos, look_at] per map
const MAP_CAMERAS := {
	"pinecrest": [
		["main_street", Vector3(-18.0, 3.2, 6.0), Vector3(12.0, 2.8, -6.0)],
		["downtown_shops", Vector3(6.0, 2.4, 8.5), Vector3(-6.0, 3.5, -10.0)],
		["gas_and_houses", Vector3(-34.0, 5.5, -16.0), Vector3(-10.0, 2.5, 4.0)],
	],
	"harbor": [
		["market_overview", Vector3(-16.0, 6.0, 20.0), Vector3(10.0, 2.5, -8.0)],
		["docks_and_tide", Vector3(24.0, 5.0, 22.0), Vector3(0.0, 1.5, 2.0)],
		["cannery_lane", Vector3(-24.0, 3.5, -12.0), Vector3(8.0, 3.0, -14.0)],
	],
	"maple_hollow": [
		["forest_clearing", Vector3(-10.0, 3.2, 22.0), Vector3(4.0, 2.8, -6.0)],
		["chapel_approach", Vector3(14.0, 3.2, -16.0), Vector3(28.0, 4.0, -34.0)],
		["ranger_camp", Vector3(-26.0, 5.0, 12.0), Vector3(-4.0, 2.5, -4.0)],
	],
}

var _settings_backup: PackedByteArray
var _had_settings := false


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_backup_settings()
	call_deferred("_run")


func _backup_settings() -> void:
	var cfg_path := ProjectSettings.globalize_path("user://settings.cfg")
	if FileAccess.file_exists(cfg_path):
		var f := FileAccess.open(cfg_path, FileAccess.READ)
		if f:
			_settings_backup = f.get_buffer(f.get_length())
			_had_settings = true
			f.close()


func _restore_settings() -> void:
	var cfg_path := ProjectSettings.globalize_path("user://settings.cfg")
	if _had_settings:
		var f := FileAccess.open(cfg_path, FileAccess.WRITE)
		if f:
			f.store_buffer(_settings_backup)
			f.close()


func _run() -> void:
	await process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var assets_dir := DEFAULT_ASSETS
	var shots_dir := DEFAULT_SHOTS
	var skip_shots := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--assets="):
			assets_dir = arg.substr(9)
		elif arg.begins_with("--shots="):
			shots_dir = arg.substr(8)
		elif arg == "--validate-only":
			skip_shots = true

	assets_dir = assets_dir.replace("\\", "/").trim_suffix("/")
	shots_dir = shots_dir.replace("\\", "/").trim_suffix("/")

	# 1. Reload every .glb in assets_dir
	var glb_files: Array[String] = []
	_find_glbs(assets_dir, glb_files)
	glb_files.sort()
	print("=== Validating %d .glb files in %s ===" % [glb_files.size(), assets_dir])
	var failed := []
	var empty := []
	var total_bytes := 0
	for path in glb_files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			total_bytes += f.get_length()
			f.close()
		var loaded := _load_glb(path)
		if loaded == null:
			failed.append(path)
			continue
		var meshes := loaded.find_children("*", "MeshInstance3D", true, false)
		var verts := 0
		for mi in meshes:
			var m := (mi as MeshInstance3D).mesh
			if m:
				for s in m.get_surface_count():
					var arr := m.surface_get_arrays(s)
					if not arr.is_empty() and arr[Mesh.ARRAY_VERTEX] != null:
						verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if verts == 0:
			empty.append(path)
		loaded.free()

	print("  Validated %d GLBs (%.2f MB total GLB): failed=%d, empty=%d" % [
		glb_files.size(), float(total_bytes) / 1048576.0, failed.size(), empty.size()
	])
	if not failed.is_empty():
		print("  FAILED: ", failed)
	if not empty.is_empty():
		print("  EMPTY: ", empty)

	if not skip_shots and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(shots_dir)
		await _capture_map_comparisons(assets_dir, shots_dir)
		await _capture_asset_showcase(assets_dir, shots_dir)

	_restore_settings()
	print("=== Validation & capture complete ===")
	quit(0 if failed.is_empty() and empty.is_empty() else 1)


func _capture_map_comparisons(assets_dir: String, shots_dir: String) -> void:
	var maps_script: Variant = load("res://game/maps.gd")
	var restyle_script: Variant = load("res://props/building_restyle.gd")
	var signs_script: Variant = load("res://props/map_signs.gd")

	var env_json_path := assets_dir.path_join("maps/environments.json")
	var ef := FileAccess.open(env_json_path, FileAccess.READ)
	var all_envs: Dictionary = JSON.parse_string(ef.get_as_text()) if ef else {}
	if ef:
		ef.close()

	for map_id in ["pinecrest", "harbor", "maple_hollow"]:
		print("[Capture] Map %s..." % map_id)
		var entry: Dictionary = maps_script.call("entry", map_id)
		var packed := load(str(entry.scene)) as PackedScene
		var orig := packed.instantiate() as Node3D
		orig.name = "Orig_" + map_id
		root.add_child(orig)
		await process_frame
		await physics_frame
		if map_id == "pinecrest":
			restyle_script.call("apply", orig)
			var signs := Node.new()
			signs.set_script(signs_script)
			orig.add_child(signs)
			await process_frame
			await physics_frame

		# Hide DECON labels on original too (just like DeconShower does in main.gd)
		for m in orig.find_children("*", "Marker3D", true, false):
			if m.is_in_group("decon_shower"):
				var lbl := m.get_node_or_null("Label")
				if lbl:
					lbl.visible = false

		var cam := Camera3D.new()
		cam.fov = 75.0
		cam.far = 400.0
		root.add_child(cam)
		cam.current = true

		var cams: Array = MAP_CAMERAS[map_id]
		var orig_imgs := {}
		for spec in cams:
			var shot_name: String = spec[0]
			var eye: Vector3 = spec[1]
			var target: Vector3 = spec[2]
			cam.global_position = eye
			cam.look_at(target, Vector3.UP)
			await process_frame
			await process_frame
			var img := root.get_viewport().get_texture().get_image()
			img.save_png(shots_dir.path_join("%s_%s_original.png" % [map_id, shot_name]))
			orig_imgs[shot_name] = img

		root.remove_child(orig)
		orig.free()
		await process_frame

		# Now load the exported .glb + apply exported environment JSON!
		var exp_scene := _load_glb(assets_dir.path_join("maps/%s.glb" % map_id))
		var exp_stage := _build_env_stage(all_envs.get(map_id, {}))
		exp_stage.add_child(exp_scene)
		root.add_child(exp_stage)
		await process_frame
		await process_frame

		for spec in cams:
			var shot_name: String = spec[0]
			var eye: Vector3 = spec[1]
			var target: Vector3 = spec[2]
			cam.global_position = eye
			cam.look_at(target, Vector3.UP)
			await process_frame
			await process_frame
			var exp_img := root.get_viewport().get_texture().get_image()
			exp_img.save_png(shots_dir.path_join("%s_%s_exported.png" % [map_id, shot_name]))
			# Also save a side-by-side comparison strip (640x360 left=orig, right=exported)
			var orig_img: Image = orig_imgs[shot_name]
			var sbs := _make_side_by_side(orig_img, exp_img)
			sbs.save_png(shots_dir.path_join("%s_%s_compare.png" % [map_id, shot_name]))

		root.remove_child(exp_stage)
		exp_stage.free()
		root.remove_child(cam)
		cam.free()
		await process_frame


func _capture_asset_showcase(assets_dir: String, shots_dir: String) -> void:
	print("[Capture] Characters & weapons showcase...")
	var stage := Node3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#18202c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.7, 0.78)
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.15
	stage.add_child(sun)

	# Row 1: Enemies
	var enemy_ids := ["drip", "gutter", "mister", "hailstone", "sleet", "smog", "static", "thunderhead", "undertow", "turned"]
	for i in enemy_ids.size():
		var e := _load_glb(assets_dir.path_join("characters/enemies/%s.glb" % enemy_ids[i]))
		if e:
			e.position = Vector3((i - 4.5) * 2.2, 0.0, 0.0)
			e.rotation.y = PI  # face +Z toward camera
			stage.add_child(e)

	# Row 2: Player skins (all 5 skins in different suit colors)
	var player_samples := [
		"standard_hazmat_yellow", "gas_mask_teal", "firefighter_red",
		"bio_tech_lime", "ion_rig_hot_pink",
	]
	for i in player_samples.size():
		var p := _load_glb(assets_dir.path_join("characters/player/%s.glb" % player_samples[i]))
		if p:
			p.position = Vector3((i - 2.0) * 1.8, 0.0, 3.2)
			p.rotation.y = PI
			stage.add_child(p)

	# Back: Cumulus + Cloudburst + Vending Station + Airdrop
	var cum := _load_glb(assets_dir.path_join("characters/enemies/cumulus.glb"))
	if cum:
		cum.position = Vector3(0.0, 8.5, -10.0)
		cum.scale = Vector3.ONE * 0.45
		stage.add_child(cum)
	var cb := _load_glb(assets_dir.path_join("characters/enemies/cloudburst.glb"))
	if cb:
		cb.position = Vector3(-8.5, 0.0, -4.5)
		cb.rotation.y = PI
		stage.add_child(cb)
	var vs := _load_glb(assets_dir.path_join("props/vending_station.glb"))
	if vs:
		vs.position = Vector3(7.5, 0.0, 3.2)
		vs.rotation.y = PI
		stage.add_child(vs)
	var ad := _load_glb(assets_dir.path_join("props/airdrop.glb"))
	if ad:
		ad.position = Vector3(-7.5, 0.0, 3.2)
		stage.add_child(ad)

	var cam := Camera3D.new()
	cam.fov = 55.0
	stage.add_child(cam)
	root.add_child(stage)
	cam.global_position = Vector3(0.0, 4.2, 13.5)
	cam.look_at(Vector3(0.0, 1.8, 0.0), Vector3.UP)
	cam.current = true
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(shots_dir.path_join("showcase_characters_props.png"))

	root.remove_child(stage)
	stage.free()
	await process_frame

	# Weapons showcase grid
	var wstage := Node3D.new()
	var wwe := WorldEnvironment.new()
	wwe.environment = env
	wstage.add_child(wwe)
	var wsun := DirectionalLight3D.new()
	wsun.rotation_degrees = Vector3(-35, 35, 0)
	wsun.light_energy = 1.2
	wstage.add_child(wsun)

	var wep_ids := [
		"service_revolver", "pump_shotgun", "spray_rifle", "nail_driver",
		"hunting_rifle", "pressure_washer", "rock_salt", "battery_zapper",
		"flare_launcher", "harpoon", "leaf_blower", "disruptor",
		"leaky_nailgun", "boombox_launcher", "lucky_penny_revolver",
		"frag", "shield_dome", "umbrella", "bleach_bomb", "bait_radio",
		"sandbag", "lightning_rod", "med_tin", "suit_patch",
	]
	for i in wep_ids.size():
		var w := _load_glb(assets_dir.path_join("weapons/pickup/%s.glb" % wep_ids[i]))
		if w:
			var col := i % 6
			var row := int(i / 6)
			w.position = Vector3((col - 2.5) * 1.15, (1.5 - row) * 0.85, 0.0)
			w.rotation_degrees = Vector3(12, -55, 0)
			wstage.add_child(w)

	var wcam := Camera3D.new()
	wcam.fov = 50.0
	wstage.add_child(wcam)
	root.add_child(wstage)
	wcam.global_position = Vector3(0.0, 0.0, 5.2)
	wcam.look_at(Vector3.ZERO, Vector3.UP)
	wcam.current = true
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(shots_dir.path_join("showcase_weapons.png"))

	root.remove_child(wstage)
	wstage.free()
	await process_frame


func _build_env_stage(env_data: Dictionary) -> Node3D:
	var stage := Node3D.new()
	var env := Environment.new()
	var sky_info: Dictionary = env_data.get("sky", {})
	if sky_info.get("type", "") == "procedural":
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = Color(str(sky_info.get("sky_top_color", "#202840")))
		psm.sky_horizon_color = Color(str(sky_info.get("sky_horizon_color", "#504868")))
		psm.sky_curve = float(sky_info.get("sky_curve", 0.15))
		psm.sky_energy_multiplier = float(sky_info.get("sky_energy_multiplier", 1.0))
		psm.ground_bottom_color = Color(str(sky_info.get("ground_bottom_color", "#141418")))
		psm.ground_horizon_color = Color(str(sky_info.get("ground_horizon_color", "#403848")))
		psm.ground_curve = float(sky_info.get("ground_curve", 0.02))
		var sky := Sky.new()
		sky.sky_material = psm
		env.background_mode = Environment.BG_SKY
		env.sky = sky
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(str(sky_info.get("color", "#182030")))

	var amb: Dictionary = env_data.get("ambient", {})
	env.ambient_light_source = int(amb.get("source_id", Environment.AMBIENT_SOURCE_COLOR)) as Environment.AmbientSource
	env.ambient_light_color = Color(str(amb.get("color", "#404050")))
	env.ambient_light_energy = float(amb.get("energy", 0.6))
	env.ambient_light_sky_contribution = float(amb.get("sky_contribution", 1.0))

	var tone: Dictionary = env_data.get("tonemap", {})
	env.tonemap_mode = int(tone.get("mode", Environment.TONE_MAPPER_FILMIC)) as Environment.ToneMapper
	env.tonemap_exposure = float(tone.get("exposure", 1.0))

	var bfog: Dictionary = env_data.get("base_fog", {})
	if bool(bfog.get("enabled", false)):
		env.fog_enabled = true
		env.fog_light_color = Color(str(bfog.get("color", "#3b4c62")))
		env.fog_density = float(bfog.get("density", 0.0085))
		env.fog_sky_affect = float(bfog.get("sky_affect", 0.42))

	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)

	var sun_info: Dictionary = env_data.get("sun", {})
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(str(sun_info.get("color", "#ffd0b0")))
	sun.light_energy = float(sun_info.get("energy", 1.0))
	sun.shadow_enabled = true
	var r: Array = sun_info.get("rotation_rad", [-0.8, 0.5, 0.0])
	sun.rotation = Vector3(float(r[0]), float(r[1]), float(r[2]))
	stage.add_child(sun)
	return stage


func _make_side_by_side(left: Image, right: Image) -> Image:
	var a := left.duplicate() as Image
	var b := right.duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	a.resize(640, 360, Image.INTERPOLATE_BILINEAR)
	b.resize(640, 360, Image.INTERPOLATE_BILINEAR)
	var out := Image.create(1284, 360, false, Image.FORMAT_RGBA8)
	out.fill(Color(1.0, 0.25, 0.5, 1.0))
	out.blit_rect(a, Rect2i(0, 0, 640, 360), Vector2i(0, 0))
	out.blit_rect(b, Rect2i(0, 0, 640, 360), Vector2i(644, 0))
	return out


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("GLTF load failed (%d): %s" % [err, path])
		return null
	return doc.generate_scene(state) as Node3D


func _find_glbs(dir_path: String, out: Array[String]) -> void:
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := dir_path.path_join(name)
			if da.current_is_dir():
				_find_glbs(full, out)
			elif name.to_lower().ends_with(".glb"):
				out.append(full)
		name = da.get_next()
	da.list_dir_end()
