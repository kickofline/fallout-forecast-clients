extends RefCounted
## Exports all enemy archetypes (rest poses with articulated named bones)
## and player models across all 5 skins x 10 suit colors + Turned variant.

const ENEMY_SCENES := {
	"drip": "res://enemies/drip/drip.tscn",
	"gutter": "res://enemies/gutter/gutter.tscn",
	"mister": "res://enemies/mister/mister.tscn",
	"hailstone": "res://enemies/hailstone/hailstone.tscn",
	"sleet": "res://enemies/sleet/sleet.tscn",
	"smog": "res://enemies/smog/smog.tscn",
	"static": "res://enemies/static/static.tscn",
	"thunderhead": "res://enemies/thunderhead/thunderhead.tscn",
	"undertow": "res://enemies/undertow/undertow.tscn",
}

const SKIN_IDS := ["standard", "gas_mask", "firefighter", "bio_tech", "ion_rig"]
const COLOR_IDS := [
	"hazmat_yellow", "teal", "hot_pink", "lime", "orange",
	"purple", "white", "red", "storm_blue", "rust",
]


func export_characters(tree: SceneTree, baker: RefCounted, out_dir: String) -> Dictionary:
	print("[Characters] Exporting enemies & players...")
	var enemies_out := {}
	var players_out := {}

	# Deterministic seed so Drip/Gutter pick a consistent iconic outfit (office/raincoat).
	seed(1987)

	# 1. Standard & weather-specialist infected enemies
	for enemy_id in ENEMY_SCENES:
		var info := await _export_infected(tree, baker, out_dir, enemy_id, ENEMY_SCENES[enemy_id], 0)
		enemies_out[enemy_id] = info

	# 2. Cloudburst (Wave 3 miniboss Mister)
	var cb := await _export_infected(tree, baker, out_dir, "cloudburst", ENEMY_SCENES["mister"], 3)
	enemies_out["cloudburst"] = cb

	# 3. Cumulus (Wave 5 boss)
	var cum := await _export_cumulus(tree, baker, out_dir)
	enemies_out["cumulus"] = cum

	# 4. Turned player (enemy type "turned")
	var turned := await _export_player_model(tree, baker, out_dir, 0, 0, true, "characters/enemies/turned.glb")
	enemies_out["turned"] = turned

	# 5. Player models: all 5 skins x 10 suit colors + default per-skin alias info
	var cosmetics_script: Variant = load("res://player/cosmetics.gd")
	var colors_meta := []
	for ci in COLOR_IDS.size():
		var col: Color = cosmetics_script.call("color", ci)
		colors_meta.append({
			"index": ci,
			"id": COLOR_IDS[ci],
			"name": str(cosmetics_script.get("COLOR_NAMES")[ci]),
			"hex": "#" + col.to_html(false),
		})

	var skins_meta := []
	for si in SKIN_IDS.size():
		skins_meta.append({
			"index": si,
			"id": SKIN_IDS[si],
			"name": str(cosmetics_script.call("skin_name", si)),
		})
		for ci in COLOR_IDS.size():
			var key := "%s_%s" % [SKIN_IDS[si], COLOR_IDS[ci]]
			var rel := "characters/player/%s.glb" % key
			var info := await _export_player_model(tree, baker, out_dir, si, ci, false, rel)
			players_out[key] = info

	var cosmetics_json := {
		"skins": skins_meta,
		"colors": colors_meta,
		"turned_overlay_color": "#8ce64d8c",
		"player_hierarchy": _player_hierarchy_doc(),
		"enemy_hierarchy": _enemy_hierarchy_doc(),
	}
	baker.write_json(out_dir.path_join("characters/cosmetics.json"), cosmetics_json)

	print("  -> Exported %d enemy types and %d player skin/color models" % [enemies_out.size(), players_out.size()])
	return {"enemies": enemies_out, "players": players_out, "cosmetics": cosmetics_json}


func _export_infected(tree: SceneTree, baker: RefCounted, out_dir: String, enemy_id: String, scene_path: String, miniboss_wave: int) -> Dictionary:
	var packed := load(scene_path) as PackedScene
	var enemy := packed.instantiate() as Node3D
	enemy.set("miniboss_wave", miniboss_wave)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	tree.root.add_child(enemy)
	await tree.process_frame

	# Grab the built _model child and freeze it at clean rest pose (cancel spawn scale tween!).
	var model: Node3D = enemy.get("_model") as Node3D
	if model == null:
		# Fallback: build manually if Net.dedicated prevented _model
		var ms: Script = enemy.call("model_script")
		model = Node3D.new()
		model.set_script(ms)
		enemy.add_child(model)
		await tree.process_frame

	# Kill any running spawn tweens by disabling processing before moving children.
	model.set_process(false)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	var export_root := Node3D.new()
	export_root.name = enemy_id

	# Restore canonical scale (undo _ready's `scale *= randf_range(0.94, 1.06)` and `* 0.1` tween).
	var archetype_scale := Vector3.ONE
	if enemy_id == "mister" or enemy_id == "cloudburst":
		archetype_scale = Vector3(1.2, 1.12, 1.15)
	elif enemy_id == "gutter":
		archetype_scale = Vector3(1.05, 0.82, 1.0)
	if miniboss_wave > 0:
		var mb_scales: Dictionary = enemy.get("MINIBOSS_SCALES")
		archetype_scale *= float(mb_scales.get(miniboss_wave, 2.5))

	# Assign deterministic articulated bone names before sanitizing!
	var body: Node3D = model.get("_body") as Node3D
	var head: Node3D = model.get("_head") as Node3D
	var jaw: Node3D = model.get("_jaw") as Node3D
	var limbs: Array = model.get("limbs") if model.get("limbs") is Array else []
	var elbows: Array = model.get("_elbows") if model.get("_elbows") is Array else []
	var knees: Array = model.get("_knees") if model.get("_knees") is Array else []
	var sparks: Node3D = model.get("_sparks") as Node3D
	var mutation_root: Node3D = model.get("_mutation_root") as Node3D

	if body:
		body.name = "Body"
		# Reset any dynamic animation rotation/offset from the 1 frame _process ran
		body.position = Vector3.ZERO
		body.rotation = Vector3(-0.25 if enemy_id == "gutter" else 0.0, 0.0, 0.0)
		body.scale = Vector3.ONE
	if head:
		head.name = "Head"
		head.rotation = Vector3.ZERO
	if jaw:
		jaw.name = "Jaw"
		jaw.rotation = Vector3.ZERO
	if sparks:
		sparks.name = "Sparks"
		sparks.visible = true
		sparks.position = Vector3(0.0, 1.55, -0.42)
		sparks.rotation = Vector3.ZERO
	if mutation_root and mutation_root.get_child_count() == 0:
		mutation_root.get_parent().remove_child(mutation_root)
		mutation_root.free()

	# limbs order in infected_model.gd / weather_infected_model.gd:
	# [0]=ArmL (side=-1), [1]=LegL (side=-1), [2]=ArmR (side=+1), [3]=LegR (side=+1)
	var reach: float = float(model.get("_reach")) if model.get("_reach") != null else 1.15
	var arm_names := ["ArmL", "ArmR"]
	var leg_names := ["LegL", "LegR"]
	var elbow_names := ["ElbowL", "ElbowR"]
	var knee_names := ["KneeL", "KneeR"]
	for i in limbs.size():
		var limb := limbs[i] as Node3D
		if limb == null:
			continue
		var side_idx := 0 if i < 2 else 1
		if i % 2 == 0:
			limb.name = arm_names[side_idx]
			# Preserve rest Z spread (sleet/undertow) and set rest reach on X
			limb.rotation.x = reach
			limb.rotation.y = 0.0
		else:
			limb.name = leg_names[side_idx]
			limb.rotation = Vector3.ZERO
	for i in elbows.size():
		var el := elbows[i] as Node3D
		if el:
			el.name = elbow_names[mini(i, 1)]
			el.rotation = Vector3(0.25, 0.0, 0.0)
	for i in knees.size():
		var kn := knees[i] as Node3D
		if kn:
			kn.name = knee_names[mini(i, 1)]
			kn.rotation = Vector3(-0.08, 0.0, 0.0)

	# Strip material_overlay (visibility shader) before moving to export_root.
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = null

	# Move model children into export_root with canonical archetype_scale.
	var parts_wrapper := Node3D.new()
	parts_wrapper.name = "Rig"
	parts_wrapper.scale = archetype_scale
	export_root.add_child(parts_wrapper)
	for child in model.get_children():
		model.remove_child(child)
		parts_wrapper.add_child(child)

	var pivots := _collect_pivots(export_root)
	baker.clear_caches()
	var stats: Dictionary = baker.sanitize_node_for_gltf(export_root, true)
	var rel := "characters/enemies/%s.glb" % enemy_id
	var wr: Dictionary = baker.write_glb(export_root, out_dir.path_join(rel))
	if not wr.ok:
		push_error("Failed writing enemy %s: %s" % [enemy_id, wr.get("error", "")])

	export_root.free()
	tree.root.remove_child(enemy)
	enemy.free()
	await tree.process_frame

	return {
		"id": enemy_id,
		"glb": rel,
		"triangles": stats.triangles,
		"draw_calls": stats.draw_calls,
		"bytes": wr.get("bytes", 0),
		"rest_reach_rad": snappedf(reach, 0.001),
		"scale": baker.vec3_arr(archetype_scale),
		"pivots": pivots,
	}


func _export_cumulus(tree: SceneTree, baker: RefCounted, out_dir: String) -> Dictionary:
	var packed := load("res://enemies/boss/boss_cumulus.tscn") as PackedScene
	var boss := packed.instantiate() as Node3D
	boss.set("preview_only", true)
	boss.set_process(false)
	tree.root.add_child(boss)
	await tree.process_frame

	boss.set_process(false)
	var export_root := Node3D.new()
	export_root.name = "cumulus"

	var rig := Node3D.new()
	rig.name = "Rig"
	var boss_scale := 1.42
	rig.scale = Vector3.ONE * boss_scale
	export_root.add_child(rig)

	# Name all animated sub-parts cleanly
	var outer: Node3D = boss.get("_storm_crown_outer") as Node3D
	if outer:
		outer.name = "StormCrownOuter"
	var inner: Node3D = boss.get("_storm_crown_inner") as Node3D
	if inner:
		inner.name = "StormCrownInner"
	var shell: Node3D = boss.get("_shell") as Node3D
	if shell:
		shell.name = "Shell"
	var core_rings: Node3D = boss.get("_core_rings") as Node3D
	if core_rings:
		core_rings.name = "CoreRings"
		core_rings.visible = true
	var sac_halos: Array = boss.get("_sac_halos") if boss.get("_sac_halos") is Array else []
	for i in sac_halos.size():
		if sac_halos[i] is Node3D:
			(sac_halos[i] as Node3D).name = "SacHalo%d" % i

	for child in boss.get_children():
		boss.remove_child(child)
		rig.add_child(child)

	var pivots := _collect_pivots(export_root)
	baker.clear_caches()
	var stats: Dictionary = baker.sanitize_node_for_gltf(export_root, true)
	var rel := "characters/enemies/cumulus.glb"
	var wr: Dictionary = baker.write_glb(export_root, out_dir.path_join(rel))
	if not wr.ok:
		push_error("Failed writing cumulus: %s" % wr.get("error", ""))

	export_root.free()
	tree.root.remove_child(boss)
	boss.free()
	await tree.process_frame

	return {
		"id": "cumulus",
		"glb": rel,
		"triangles": stats.triangles,
		"draw_calls": stats.draw_calls,
		"bytes": wr.get("bytes", 0),
		"scale": [boss_scale, boss_scale, boss_scale],
		"pivots": pivots,
	}


func _export_player_model(tree: SceneTree, baker: RefCounted, out_dir: String, skin_idx: int, color_idx: int, is_turned: bool, rel_path: String) -> Dictionary:
	var cosmetics_script: Variant = load("res://player/cosmetics.gd")
	var pm_script: Script = load("res://player/player_model.gd") as Script
	var col: Color = cosmetics_script.call("color", color_idx)
	if is_turned:
		# Blend turned sickly green overlay (Color(0.55, 0.9, 0.3, 0.55)) into the hazmat look.
		col = col.lerp(Color(0.55, 0.9, 0.3), 0.55)

	var pm := Node3D.new()
	pm.name = "PlayerModel"
	pm.set_script(pm_script)
	pm.set("suit_color", col)
	pm.set("skin", skin_idx)
	pm.set_process(false)
	tree.root.add_child(pm)
	await tree.process_frame

	var hips: Node3D = pm.get("_hips") as Node3D
	var torso: Node3D = pm.get("_torso") as Node3D
	var head: Node3D = pm.get("_head") as Node3D
	var arms: Array = pm.get("_arms") if pm.get("_arms") is Array else []
	var forearms: Array = pm.get("_forearms") if pm.get("_forearms") is Array else []
	var legs: Array = pm.get("_legs") if pm.get("_legs") is Array else []
	var shins: Array = pm.get("_shins") if pm.get("_shins") is Array else []
	var weapon_mount: Node3D = pm.get("weapon_mount") as Node3D

	if hips:
		hips.name = "Hips"
		hips.position = Vector3(0.0, 0.92, 0.0)
		hips.rotation = Vector3.ZERO
	if torso:
		torso.name = "Torso"
		torso.rotation = Vector3(0.35, 0.0, 0.0) if is_turned else Vector3.ZERO
	if head:
		head.name = "Head"
		head.rotation = Vector3(0.3, 0.0, 0.35) if is_turned else Vector3.ZERO
	for i in arms.size():
		var arm := arms[i] as Node3D
		if arm:
			arm.name = "ArmL" if i == 0 else "ArmR"
			arm.rotation = Vector3(1.4, 0.0, 0.1 if i == 0 else -0.1) if is_turned else Vector3.ZERO
	for i in forearms.size():
		var fore := forearms[i] as Node3D
		if fore:
			fore.name = "ForearmL" if i == 0 else "ForearmR"
			fore.rotation = Vector3(0.2 if i == 0 else 0.3, 0.0, 0.0) if is_turned else Vector3.ZERO
	for i in legs.size():
		var leg := legs[i] as Node3D
		if leg:
			leg.name = "LegL" if i == 0 else "LegR"
			leg.rotation = Vector3.ZERO
	for i in shins.size():
		var shin := shins[i] as Node3D
		if shin:
			shin.name = "ShinL" if i == 0 else "ShinR"
			shin.rotation = Vector3.ZERO
	if weapon_mount:
		weapon_mount.name = "WeaponMount"
		if forearms.size() > 1 and forearms[1] is Node3D:
			weapon_mount.position = (forearms[1] as Node3D).to_global(Vector3(0, -0.29, 0))

	# If turned, tint every mesh slightly toward sickly green (matching _turned_overlay) so glTF reflects it.
	if is_turned:
		var turned_tint := Color(0.55, 0.9, 0.3)
		for mi in pm.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
			if m != null:
				var copy := m.duplicate() as StandardMaterial3D
				copy.albedo_color = copy.albedo_color.lerp(turned_tint, 0.42)
				if not copy.emission_enabled:
					copy.emission_enabled = true
					copy.emission = turned_tint * 0.25
					copy.emission_energy_multiplier = 0.5
				(mi as MeshInstance3D).material_override = copy

	# Merge direct box pieces per bone (keeps articulated bones intact, cuts draw calls from ~30 to ~10!).
	var mesh_merge: Variant = load("res://props/mesh_merge.gd")
	var bones := []
	for b in [hips, torso, head] + arms + forearms + legs + shins:
		if b != null:
			bones.append(b)
	for b in bones:
		mesh_merge.call("merge_children", b, true)

	pm.set_process(false)
	var out_id := "turned" if is_turned else "%s_%s" % [SKIN_IDS[skin_idx], COLOR_IDS[color_idx]]
	var export_root := Node3D.new()
	export_root.name = out_id
	for child in pm.get_children():
		pm.remove_child(child)
		export_root.add_child(child)

	var pivots := _collect_pivots(export_root)
	baker.clear_caches()
	var stats: Dictionary = baker.sanitize_node_for_gltf(export_root, true)
	var wr: Dictionary = baker.write_glb(export_root, out_dir.path_join(rel_path))
	if not wr.ok:
		push_error("Failed writing player %s: %s" % [rel_path, wr.get("error", "")])

	export_root.free()
	tree.root.remove_child(pm)
	pm.free()
	await tree.process_frame

	return {
		"id": out_id,
		"skin": SKIN_IDS[skin_idx],
		"color": COLOR_IDS[color_idx],
		"color_hex": "#" + col.to_html(false),
		"turned": is_turned,
		"glb": rel_path,
		"triangles": stats.triangles,
		"draw_calls": stats.draw_calls,
		"bytes": wr.get("bytes", 0),
		"pivots": pivots,
	}


func _collect_pivots(root: Node3D) -> Dictionary:
	var out := {}
	for n in root.find_children("*", "Node3D", true, false):
		if n is MeshInstance3D:
			continue
		var n3 := n as Node3D
		out[str(root.get_path_to(n3))] = {
			"pos": [snappedf(n3.position.x, 0.001), snappedf(n3.position.y, 0.001), snappedf(n3.position.z, 0.001)],
			"rot": [snappedf(n3.rotation.x, 0.001), snappedf(n3.rotation.y, 0.001), snappedf(n3.rotation.z, 0.001)],
		}
	return out


func _player_hierarchy_doc() -> Dictionary:
	return {
		"root": "Hips (y=0.92)",
		"children": [
			"Hips/Torso (y=0.12)",
			"Hips/Torso/Head (y=0.60)",
			"Hips/Torso/ArmL (-0.3, 0.46, 0) -> ForearmL (0, -0.29, 0)",
			"Hips/Torso/ArmR (+0.3, 0.46, 0) -> ForearmR (0, -0.29, 0)",
			"Hips/LegL (-0.12, -0.06, 0) -> ShinL (0, -0.40, 0)",
			"Hips/LegR (+0.12, -0.06, 0) -> ShinR (0, -0.40, 0)",
			"WeaponMount (tracks ForearmR local (0, -0.29, 0))",
		],
	}


func _enemy_hierarchy_doc() -> Dictionary:
	return {
		"infected_bones": [
			"Rig/Body",
			"Rig/Body/Head",
			"Rig/Body/Head/Jaw (drip, gutter, mister, cloudburst)",
			"Rig/Body/ArmL -> ElbowL",
			"Rig/Body/ArmR -> ElbowR",
			"Rig/Body/LegL -> KneeL",
			"Rig/Body/LegR -> KneeR",
			"Rig/Body/Sparks (static)",
			"Rig/Body/MinibossMantle/MinibossHalo (cloudburst)",
			"Rig/MinibossGroundAura (cloudburst)",
		],
		"cumulus_bones": [
			"Rig/Body (cloud mesh + StormCrownOuter + StormCrownInner)",
			"Rig/Sac0, Rig/Sac1, Rig/Sac2 (each has SacHalo0..2, orbits at radius 5.0, y=-1.2)",
			"Rig/Core (y=-1.8) -> CoreRings (4 tumbling torus rings when core exposed)",
			"Rig/Shell (translucent shield sphere over Core while sacs_left > 0)",
		],
	}
