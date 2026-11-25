extends RefCounted
## Exports playable districts (pinecrest, harbor, maple_hollow) with all runtime
## restyles, signs, tree shelters, sidecar JSONs, and per-weather environment JSONs.

const MAP_IDS := ["pinecrest", "harbor", "maple_hollow"]
const DECIMATE_TRI_THRESHOLD := 150000
## Grid cell size (metres) for the frustum-cullable <map>_chunked.glb.
const CHUNK_CELL := 40.0

## Fold untextured opaque solid colours into vertex colours (default; turn off
## with --no-fold-colors, then folding only happens past 180 materials). It
## halves the maps' material/draw-call count and renders identically on the
## Godot 3 client (fixed-camera A/B, 2026-11-25); the SGX is draw-call bound.
var fold_colors := true


func export_maps(tree: SceneTree, baker: RefCounted, out_dir: String, filter_maps: PackedStringArray, skip_decimate := false, chunked := false) -> Dictionary:
	var maps_script: Variant = load("res://game/maps.gd")
	var tree_shelter_script: Variant = load("res://props/tree_shelter.gd")
	var restyle_script: Variant = load("res://props/building_restyle.gd")
	var signs_script: Variant = load("res://props/map_signs.gd")

	var results := {}
	var all_envs := {}

	var target_ids: Array[String] = []
	for id in MAP_IDS:
		if filter_maps.is_empty() or id in filter_maps:
			target_ids.append(id)

	for map_id in target_ids:
		print("[Maps] Exporting %s..." % map_id)
		var entry: Dictionary = maps_script.call("entry", map_id)
		var scene_path := str(entry.get("scene", ""))
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("Could not load map scene: " + scene_path)
			continue

		var level := packed.instantiate() as Node3D
		level.name = "Level_" + map_id
		tree.root.add_child(level)
		# Let _ready() run (model_style.gd, puddle.gd, traffic_light.gd, CSG updates).
		await tree.process_frame
		await tree.physics_frame

		if map_id == "pinecrest":
			restyle_script.call("apply", level)
			var signs := Node.new()
			signs.name = "MapSigns"
			signs.set_script(signs_script)
			level.add_child(signs)
			await tree.process_frame
			await tree.physics_frame

		# Install tree canopy shelter areas just like main.gd does.
		tree_shelter_script.call("install", level)
		await tree.physics_frame

		# Extract environment before stripping anything.
		var env_data := _extract_environment(level, map_id)
		all_envs[map_id] = env_data

		# Extract gameplay & visual sidecar metadata (spawns, shelters, puddles, decon, stations, lights).
		var sidecar := _extract_sidecar(level, map_id, str(entry.get("name", map_id.to_upper())), env_data)

		# Bake & merge static geometry by material.
		# First pass: exact materials (no solid-color vertex folding).
		baker.clear_caches()
		var baked: Dictionary = baker.bake_level_to_merged_scene(level, map_id, false)
		var draw_calls: int = baked.draw_calls
		var used_vcol_fold := false
		# If exact materials exceed 180 draw calls, fold untextured opaque solid colors into vertex colors.
		if draw_calls > 180 or fold_colors:
			baked.scene.free()
			baker.clear_caches()
			baked = baker.bake_level_to_merged_scene(level, map_id, true)
			draw_calls = baked.draw_calls
			used_vcol_fold = true

		var glb_rel := "maps/%s.glb" % map_id
		var glb_path := out_dir.path_join(glb_rel)
		var wr: Dictionary = baker.write_glb(baked.scene, glb_path)
		if not wr.ok:
			push_error("Failed writing %s: %s" % [glb_path, wr.get("error", "")])

		var map_info := {
			"id": map_id,
			"name": str(entry.get("name", map_id.to_upper())),
			"glb": glb_rel,
			"sidecar": "maps/%s.json" % map_id,
			"triangles": baked.triangles,
			"draw_calls": baked.draw_calls,
			"bytes": wr.get("bytes", 0),
			"vcol_solid_folded": used_vcol_fold,
			"bounds": {
				"min": baker.vec3_arr(baked.bounds_min),
				"max": baker.vec3_arr(baked.bounds_max),
			},
			"bake_stats": baked.stats,
		}

		# Generate decimated variant if triangle count exceeds ~150k.
		if not skip_decimate and int(baked.triangles) > DECIMATE_TRI_THRESHOLD:
			print("  %s has %d triangles (> %d); generating decimated variant..." % [map_id, baked.triangles, DECIMATE_TRI_THRESHOLD])
			var dec: Dictionary = baker.build_decimated_scene(baked.buckets, map_id, 110000)
			var low_rel := "maps/%s_low.glb" % map_id
			var low_path := out_dir.path_join(low_rel)
			var lwr: Dictionary = baker.write_glb(dec.scene, low_path)
			if lwr.ok:
				map_info["low_glb"] = low_rel
				map_info["low_triangles"] = dec.triangles
				map_info["low_draw_calls"] = dec.draw_calls
				map_info["low_bytes"] = lwr.get("bytes", 0)
			dec.scene.free()

		# Optional (--chunked) variant: same full-detail geometry split into
		# CHUNK_CELL grid cells so Godot 3 frustum-culls per cell. Measured on the
		# head unit (2026-11-25) it was slower than the whole-map merge on all
		# three maps (draw calls cost more than the culled vertices save), so it
		# is not exported by default.
		if chunked:
			_export_chunked(baker, baked, map_id, out_dir, map_info)

		sidecar["mesh"] = map_info
		baker.write_json(out_dir.path_join("maps/%s.json" % map_id), sidecar)

		baked.scene.free()
		level.queue_free()
		await tree.process_frame

		results[map_id] = map_info
		print("  -> %s: %d tris, %d draw calls, %.2f MB%s" % [
			map_id,
			map_info.triangles,
			map_info.draw_calls,
			float(map_info.bytes) / 1048576.0,
			(" (low: %d tris, %.2f MB)" % [map_info.low_triangles, float(map_info.low_bytes) / 1048576.0]) if map_info.has("low_glb") else ""
		])

	if not all_envs.is_empty():
		baker.write_json(out_dir.path_join("maps/environments.json"), all_envs)

	return results


func _extract_environment(level: Node3D, map_id: String) -> Dictionary:
	var env: Environment = null
	var sun: DirectionalLight3D = null
	for n in level.find_children("*", "WorldEnvironment", true, false):
		var we := n as WorldEnvironment
		if we.environment != null:
			env = we.environment
			break
	for n in level.find_children("*", "DirectionalLight3D", true, false):
		sun = n as DirectionalLight3D
		break

	# Defaults from weather/weather_fx.gd
	var fog_color := Color(0.42, 0.38, 0.52)
	var acid_fog_color := Color(0.18, 0.32, 0.12)
	var storm_fog_tint := Color(0.33, 0.45, 0.30)
	var storm_fog_tint_amount := 0.3
	var fog_curve := [0.0, 0.012, 0.035, 0.04]
	var min_sky_energy := 0.35
	var min_sun_energy := 0.15
	match map_id:
		"harbor":
			fog_color = Color(0.37, 0.45, 0.53)
			fog_curve = [0.0, 0.011, 0.029, 0.04]
			min_sun_energy = 0.24
		"maple_hollow":
			fog_color = Color(0.43, 0.40, 0.49)
			fog_curve = [0.0, 0.012, 0.031, 0.04]
			min_sun_energy = 0.22

	var base_sky_energy := env.background_energy_multiplier if env else 1.0
	var base_ambient_energy := env.ambient_light_energy if env else 0.5
	var ambient_color := env.ambient_light_color if env else Color(0.35, 0.35, 0.45)
	var ambient_sky_contrib := env.ambient_light_sky_contribution if env else 1.0
	var ambient_source_id := env.ambient_light_source if env else Environment.AMBIENT_SOURCE_COLOR
	var ambient_source_name := "color" if ambient_source_id == Environment.AMBIENT_SOURCE_COLOR else ("sky" if ambient_source_id == Environment.AMBIENT_SOURCE_SKY else ("disabled" if ambient_source_id == Environment.AMBIENT_SOURCE_DISABLED else "bg"))
	var tonemap_mode := env.tonemap_mode if env else Environment.TONE_MAPPER_FILMIC
	var tonemap_exposure := env.tonemap_exposure if env else 1.0
	var base_fog_enabled := env.fog_enabled if env else false
	var base_fog_color := env.fog_light_color if env else fog_color
	var base_fog_density := env.fog_density if env else 0.0
	var base_fog_sky_affect := env.fog_sky_affect if env else 1.0
	var bg_color := env.background_color if env else Color(0.12, 0.14, 0.22)

	var sky_data := {}
	if env and env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var psm := env.sky.sky_material as ProceduralSkyMaterial
		sky_data = {
			"type": "procedural",
			"sky_top_color": _hex(psm.sky_top_color),
			"sky_horizon_color": _hex(psm.sky_horizon_color),
			"sky_curve": snappedf(psm.sky_curve, 0.001),
			"sky_energy_multiplier": snappedf(psm.sky_energy_multiplier, 0.001),
			"ground_bottom_color": _hex(psm.ground_bottom_color),
			"ground_horizon_color": _hex(psm.ground_horizon_color),
			"ground_curve": snappedf(psm.ground_curve, 0.001),
		}
	else:
		sky_data = {"type": "color", "color": _hex(bg_color)}

	var base_sun_energy := sun.light_energy if sun else 1.0
	var sun_color := sun.light_color if sun else Color(1.0, 0.85, 0.72)
	var sun_dir := -sun.global_basis.z if sun else Vector3(0.4, -0.7, -0.5).normalized()
	var sun_rot := sun.global_rotation if sun else Vector3(-0.8, 0.6, 0.0)

	# Compute exact per-phase values matching weather/weather_fx.gd lines 87-136.
	var phase_specs := {
		"calm": 0.0,
		"drizzle": 0.3,
		"downpour": 0.7,
		"acid_storm": 1.0,
		"clearing": 0.15,
	}
	var phases := {}
	for phase_name in phase_specs:
		var intensity: float = phase_specs[phase_name]
		var acid := clampf((intensity - 0.7) / 0.3, 0.0, 1.0)
		var fog_density := _sample_fog(intensity, fog_curve)
		var storm_tint := fog_color.lerp(storm_fog_tint, storm_fog_tint_amount * minf(intensity / 0.7, 1.0))
		var phase_fog_col := storm_tint.lerp(acid_fog_color, acid)
		var sky_e := lerpf(base_sky_energy, min_sky_energy, minf(intensity / 0.7, 1.0))
		var sun_e := lerpf(base_sun_energy, min_sun_energy, minf(intensity / 0.7, 1.0))
		var rain_col := Color(0.42, 0.92, 0.36, 0.42).lerp(Color(0.55, 1.0, 0.25, 0.55), acid)
		# Approximate GLES2 linear fog_depth_begin / fog_depth_end equivalent for exponential density.
		var approx_fog_end := snappedf(clampf(2.6 / maxf(fog_density, 0.0001), 22.0, 260.0), 0.1) if fog_density > 0.0001 else 260.0
		var approx_fog_begin := snappedf(approx_fog_end * 0.18, 0.1) if fog_density > 0.0001 else 200.0
		phases[phase_name] = {
			"intensity": intensity,
			"fog_density": snappedf(fog_density, 0.0001),
			"fog_depth_begin_gles2": approx_fog_begin,
			"fog_depth_end_gles2": approx_fog_end,
			"fog_color": _hex(phase_fog_col),
			"sky_energy": snappedf(sky_e, 0.001),
			"ambient_energy": snappedf(base_ambient_energy, 0.001),
			"sun_energy": snappedf(sun_e, 0.001),
			"rain_color": _hex_a(rain_col),
		}

	return {
		"map_id": map_id,
		"sky": sky_data,
		"ambient": {
			"source": ambient_source_name,
			"source_id": ambient_source_id,
			"color": _hex(ambient_color),
			"energy": snappedf(base_ambient_energy, 0.001),
			"sky_contribution": snappedf(ambient_sky_contrib, 0.001),
		},
		"tonemap": {
			"mode": tonemap_mode,
			"exposure": snappedf(tonemap_exposure, 0.001),
		},
		"base_fog": {
			"enabled": base_fog_enabled,
			"color": _hex(base_fog_color),
			"density": snappedf(base_fog_density, 0.0001),
			"sky_affect": snappedf(base_fog_sky_affect, 0.001),
		},
		"sun": {
			"color": _hex(sun_color),
			"energy": snappedf(base_sun_energy, 0.001),
			"direction": _v3(sun_dir.normalized()),
			"rotation_rad": _v3(sun_rot),
		},
		"fog_base": {
			"fog_color": _hex(fog_color),
			"acid_fog_color": _hex(acid_fog_color),
			"storm_fog_tint": _hex(storm_fog_tint),
			"storm_fog_tint_amount": storm_fog_tint_amount,
			"density_curve": fog_curve,
		},
		"lightning_flash": {
			"fade_rate": 2.6,
			"sky_boost": 0.85,
			"ambient_boost": 0.4,
			"sun_boost": 0.5,
		},
		"phases": phases,
	}


func _sample_fog(intensity: float, curve: Array) -> float:
	var stops := [0.0, 0.3, 0.7, 1.0]
	for i in range(1, stops.size()):
		if intensity <= stops[i]:
			var t := inverse_lerp(stops[i - 1], stops[i], intensity)
			return lerpf(float(curve[i - 1]), float(curve[i]), t)
	return float(curve[curve.size() - 1])


func _extract_sidecar(level: Node3D, map_id: String, display_name: String, env_data: Dictionary) -> Dictionary:
	var player_spawns := []
	var enemy_spawns := []
	var drain_spawns := []
	var crate_spawns := []
	var vending_stations := []
	var decon_showers := []
	var boss_anchors := []
	var shelters := []
	var puddles := []
	var lights := []

	var space := level.get_world_3d().direct_space_state if level.get_world_3d() else null

	for node in level.find_children("*", "", true, false):
		if node is Node3D:
			var n3 := node as Node3D
			if n3.is_in_group("player_spawn"):
				player_spawns.append({"name": n3.name, "pos": _v3(n3.global_position), "rot_y": snappedf(n3.global_rotation.y, 0.001)})
			if n3.is_in_group("enemy_spawn"):
				enemy_spawns.append({"name": n3.name, "pos": _v3(n3.global_position)})
			if n3.is_in_group("drain_spawn"):
				drain_spawns.append({"name": n3.name, "pos": _v3(n3.global_position)})
			if n3.is_in_group("crate_spawn"):
				crate_spawns.append({"name": n3.name, "pos": _v3(n3.global_position)})
			if n3.is_in_group("crate_station"):
				vending_stations.append({
					"name": n3.name,
					"pos": _v3(n3.global_position),
					"rot_y": snappedf(n3.global_rotation.y, 0.001),
					"size": [2.09, 2.07, 0.91],
				})
			if n3.is_in_group("decon_shower"):
				decon_showers.append({
					"name": n3.name,
					"pos": _v3(n3.global_position),
					"rot_y": snappedf(n3.global_rotation.y, 0.001),
					"interact_offset": [0.0, 1.0, 0.0],
					"radius": 2.2,
				})
			if n3.is_in_group("boss_anchor"):
				boss_anchors.append({"name": n3.name, "pos": _v3(n3.global_position)})
			if n3.is_in_group("shelter") and n3 is Area3D:
				var is_tree := n3.get_parent() != null and n3.get_parent().is_in_group("tree_canopy_trunks")
				for child in n3.get_children():
					if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
						var cs := child as CollisionShape3D
						var sh := cs.shape
						var srec := {
							"name": str(n3.name) if not is_tree else str(n3.get_parent().name) + "_canopy",
							"pos": _v3(cs.global_position),
							"rot": _v3(cs.global_rotation),
							"is_tree_canopy": is_tree,
						}
						if sh is BoxShape3D:
							srec["shape"] = "box"
							srec["size"] = _v3((sh as BoxShape3D).size)
						elif sh is CylinderShape3D:
							srec["shape"] = "cylinder"
							srec["radius"] = snappedf((sh as CylinderShape3D).radius, 0.001)
							srec["height"] = snappedf((sh as CylinderShape3D).height, 0.001)
						elif sh is SphereShape3D:
							srec["shape"] = "sphere"
							srec["radius"] = snappedf((sh as SphereShape3D).radius, 0.001)
						else:
							srec["shape"] = sh.get_class()
						shelters.append(srec)
			if n3.is_in_group("puddles"):
				var floor_y := n3.global_position.y + 0.075
				if space != null:
					var q := PhysicsRayQueryParameters3D.create(n3.global_position + Vector3.UP * 0.6, n3.global_position + Vector3.DOWN * 0.6, 1)
					var hit := space.intersect_ray(q)
					if not hit.is_empty():
						floor_y = (hit.position as Vector3).y + 0.03
				var pcol: Variant = n3.get("color")
				var acol: Variant = n3.get("acid_color")
				puddles.append({
					"name": n3.name,
					"pos": _v3(n3.global_position),
					"floor_y": snappedf(floor_y, 0.001),
					"max_radius": snappedf(float(n3.get("max_radius") if n3.get("max_radius") != null else 2.5), 0.001),
					"grow_time": snappedf(float(n3.get("grow_time") if n3.get("grow_time") != null else 45.0), 0.01),
					"dry_time": snappedf(float(n3.get("dry_time") if n3.get("dry_time") != null else 25.0), 0.01),
					"color": _hex_a(pcol if pcol is Color else Color(0.3, 0.62, 0.27, 0.7)),
					"acid_color": _hex_a(acol if acol is Color else Color(0.42, 0.88, 0.2, 0.82)),
				})
			if n3 is OmniLight3D and n3.visible:
				var ol := n3 as OmniLight3D
				lights.append({
					"name": ol.name,
					"type": "omni",
					"pos": _v3(ol.global_position),
					"color": _hex(ol.light_color),
					"energy": snappedf(ol.light_energy, 0.01),
					"range": snappedf(ol.omni_range, 0.01),
				})
			elif n3 is SpotLight3D and n3.visible:
				var sl := n3 as SpotLight3D
				lights.append({
					"name": sl.name,
					"type": "spot",
					"pos": _v3(sl.global_position),
					"dir": _v3(-sl.global_basis.z.normalized()),
					"color": _hex(sl.light_color),
					"energy": snappedf(sl.light_energy, 0.01),
					"range": snappedf(sl.spot_range, 0.01),
					"angle_deg": snappedf(sl.spot_angle, 0.1),
				})

	return {
		"id": map_id,
		"name": display_name,
		"player_spawns": player_spawns,
		"enemy_spawns": enemy_spawns,
		"drain_spawns": drain_spawns,
		"crate_spawns": crate_spawns,
		"vending_stations": vending_stations,
		"decon_showers": decon_showers,
		"boss_anchors": boss_anchors,
		"shelters": shelters,
		"puddles": puddles,
		"lights": lights,
		"environment": env_data,
	}


func _export_chunked(baker: RefCounted, baked: Dictionary, map_id: String, out_dir: String, map_info: Dictionary) -> void:
	var ch: Dictionary = baker.build_chunked_scene(baked.buckets, map_id, CHUNK_CELL)
	var ch_rel := "maps/%s_chunked.glb" % map_id
	var cwr: Dictionary = baker.write_glb(ch.scene, out_dir.path_join(ch_rel))
	if cwr.ok:
		map_info["chunked_glb"] = ch_rel
		map_info["chunked_cells"] = ch.cells
		map_info["chunked_surfaces"] = ch.surfaces
		map_info["chunked_max_cell_surfaces"] = ch.max_cell_surfaces
		map_info["chunked_cell_size"] = ch.cell_size
		map_info["chunked_bytes"] = cwr.get("bytes", 0)
	else:
		push_error("Failed writing %s: %s" % [ch_rel, cwr.get("error", "")])
	print("  chunked: %d cells, %d surfaces (max %d per cell), %d tris" % [ch.cells, ch.surfaces, ch.max_cell_surfaces, ch.triangles])
	ch.scene.free()


static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func _hex_a(c: Color) -> String:
	return "#" + c.to_html(true)
