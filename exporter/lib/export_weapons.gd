extends RefCounted
## Exports all weapons & items (first-person viewmodels with hands + animated pivots,
## world pickups), ground supply drops, crates/airdrop/vending stations, deployed zones
## (shield dome, open umbrella, sandbag wall, planted lightning rod), decon cells, and projectiles.

const DROP_KINDS := ["ammo", "health", "suit", "supply", "scrap", "scrap_large"]
const PROJECTILE_IDS := [
	"nail_driver", "harpoon", "flare_launcher", "boombox_launcher",
	"frag", "shield_dome", "bug_bomb", "bleach_bomb", "bait_radio",
	"sandbag", "umbrella",
]


func export_weapons_and_props(tree: SceneTree, baker: RefCounted, out_dir: String) -> Dictionary:
	print("[Weapons & Props] Exporting guns, items, pickups, stations, crates, projectiles...")
	var catalog: Variant = load("res://weapons/item_catalog.gd")
	var gun_models: Variant = load("res://weapons/gun_models.gd")
	var item_models: Variant = load("res://weapons/item_models.gd")
	var pose_script: Script = load("res://weapons/item_pose.gd") as Script

	var guns_dict: Dictionary = catalog.get("GUNS")
	var stacks_dict: Dictionary = catalog.get("STACKS")
	var all_ids: Array[String] = []
	for id in guns_dict:
		all_ids.append(str(id))
	for id in stacks_dict:
		all_ids.append(str(id))

	var weapons_meta := {}
	var pickups_meta := {}

	for id in all_ids:
		var def: Resource = catalog.call("definition", id)
		var wd: Resource = def.get("weapon") if def else null

		# 1. First-person viewmodel (with named LeftHand / RightHand + animated part + Muzzle / Sight markers)
		var vm: Node3D = catalog.call("model", id, false)
		var pose: RefCounted = pose_script.new()
		if pose_script.get("PROFILES").has(id):
			pose.call("bind", vm, id)
			# Name the two hand nodes cleanly for client procedural reload animation.
			var support_hand: Node3D = pose.get("support") as Node3D
			for child in vm.get_children():
				if child == support_hand:
					child.name = "LeftHand"
				elif child is Node3D and not (child is MeshInstance3D) and child.name.begins_with("@Node3D"):
					child.name = "RightHand"

		var muzzle_pos: Vector3 = vm.get_meta("muzzle", wd.get("muzzle") if wd else Vector3.ZERO)
		var sight_pos: Vector3 = vm.get_meta("sight", Vector3.INF)
		var muzzle_marker := Node3D.new()
		muzzle_marker.name = "Muzzle"
		muzzle_marker.position = muzzle_pos
		vm.add_child(muzzle_marker)
		if sight_pos != Vector3.INF:
			var sight_marker := Node3D.new()
			sight_marker.name = "Sight"
			sight_marker.position = sight_pos
			vm.add_child(sight_marker)

		var vm_root := Node3D.new()
		vm_root.name = "View_" + id
		vm_root.add_child(vm)

		baker.clear_caches()
		var vm_stats: Dictionary = baker.sanitize_node_for_gltf(vm_root, true)
		var vm_rel := "weapons/view/%s.glb" % id
		var vm_wr: Dictionary = baker.write_glb(vm_root, out_dir.path_join(vm_rel))
		vm_root.free()

		# 2. World pickup model
		var pk: Node3D = catalog.call("model", id, true)
		var pk_root := Node3D.new()
		pk_root.name = "Pickup_" + id
		pk_root.add_child(pk)

		baker.clear_caches()
		var pk_stats: Dictionary = baker.sanitize_node_for_gltf(pk_root, true)
		var pk_rel := "weapons/pickup/%s.glb" % id
		var pk_wr: Dictionary = baker.write_glb(pk_root, out_dir.path_join(pk_rel))
		pk_root.free()

		var profile: Array = pose_script.get("PROFILES").get(id, ["", "", 0.0])
		var kind_str := "gun" if guns_dict.has(id) else "item"
		var winfo := {
			"id": id,
			"name": str(def.get("display_name")) if def else id,
			"category": kind_str,
			"is_pouch": bool(catalog.call("is_pouch", id)),
			"view_glb": vm_rel,
			"view_triangles": vm_stats.triangles,
			"view_draw_calls": vm_stats.draw_calls,
			"view_bytes": vm_wr.get("bytes", 0),
			"pickup_glb": pk_rel,
			"pickup_triangles": pk_stats.triangles,
			"pickup_draw_calls": pk_stats.draw_calls,
			"pickup_bytes": pk_wr.get("bytes", 0),
			"pose_action": str(profile[0]),
			"animated_part": str(profile[1]),
			"support_grip_z": snappedf(float(profile[2]), 0.001),
			"muzzle": baker.vec3_arr(muzzle_pos),
			"sight": baker.vec3_arr(sight_pos) if sight_pos != Vector3.INF else null,
		}
		if wd != null:
			winfo["view_position"] = baker.vec3_arr(wd.get("view_position"))
			winfo["view_rotation_degrees"] = baker.vec3_arr(wd.get("view_rotation_degrees"))
			winfo["view_scale"] = snappedf(float(wd.get("view_scale")), 0.001)
			winfo["ads_fov"] = snappedf(float(wd.get("ads_fov")), 0.1)
			winfo["ads_eye_relief"] = snappedf(float(wd.get("ads_eye_relief")), 0.001)
			winfo["tracer_color"] = baker.color_hex(wd.get("tracer_color"))
			winfo["shot_sound"] = str(wd.get("shot_sound"))
			winfo["deploy_sound"] = str(wd.get("deploy_sound"))
			winfo["blast_sound"] = str(wd.get("blast_sound"))
			winfo["effect_radius"] = snappedf(float(wd.get("effect_radius")), 0.01)
			winfo["fire_interval"] = snappedf(float(wd.get("fire_interval")), 0.001)
			winfo["reload_time"] = snappedf(float(wd.get("reload_time")), 0.01)
			winfo["mag_size"] = int(wd.get("mag_size"))
			winfo["automatic"] = bool(wd.get("automatic"))
			winfo["shell_reload"] = bool(wd.get("shell_reload"))
			winfo["cursed"] = bool(wd.get("cursed"))
		weapons_meta[id] = winfo
		pickups_meta[id] = pk_rel

	# Also export legacy gun_models.gd "bug_bomb" canister (for completeness)
	var props_meta := {}
	var bb: Node3D = gun_models.call("build", "bug_bomb")
	props_meta["bug_bomb_canister"] = _save_prop(baker, bb, out_dir, "props/bug_bomb_canister.glb", "bug_bomb_canister")

	# 3. Ground supply drops (ammo, health, suit, supply, scrap, scrap_large)
	var ammo_drop_script: Script = load("res://weapons/ammo_drop.gd") as Script
	for kind in DROP_KINDS:
		var drop := Node3D.new()
		drop.name = "Drop_" + kind
		drop.set_script(ammo_drop_script)
		drop.set("kind", kind)
		drop.set_process(false)
		tree.root.add_child(drop)
		await tree.process_frame
		drop.set_process(false)
		var root_node := Node3D.new()
		root_node.name = "pickup_" + kind
		for ch in drop.get_children():
			drop.remove_child(ch)
			root_node.add_child(ch)
		props_meta["pickup_" + kind] = _save_prop(baker, root_node, out_dir, "props/pickup_%s.glb" % kind, "pickup_" + kind)
		tree.root.remove_child(drop)
		drop.free()
		await tree.process_frame

	# 4. Vending Station (3-bay cabinet from crates/supply_station.gd)
	var station_script: Script = load("res://crates/supply_station.gd") as Script
	var st := Node3D.new()
	st.name = "VendingStation"
	st.set_script(station_script)
	st.set("is_drop", false)
	st.set_process(false)
	tree.root.add_child(st)
	await tree.process_frame
	st.set_process(false)
	var st_root := Node3D.new()
	st_root.name = "vending_station"
	var st_frame: Node3D = st.get("_frame") as Node3D
	if st_frame:
		st_frame.name = "Frame"
		st.remove_child(st_frame)
		st_root.add_child(st_frame)
	props_meta["vending_station"] = _save_prop(baker, st_root, out_dir, "props/vending_station.glb", "vending_station")
	tree.root.remove_child(st)
	st.free()
	await tree.process_frame

	# 5. Crate Station (ItemModels.projectile("crate_station") with Door & Beacon)
	var cs_node: Node3D = item_models.call("projectile", "crate_station")
	props_meta["crate_station"] = _save_prop(baker, cs_node, out_dir, "props/crate_station.glb", "crate_station")

	# 6. Airdrop + Parachute + Beacon (from SupplyStation is_drop=true)
	var ad := Node3D.new()
	ad.name = "Airdrop"
	ad.set_script(station_script)
	ad.set("is_drop", true)
	ad.set("descent_left", 0.0)
	ad.set_process(false)
	tree.root.add_child(ad)
	await tree.process_frame
	ad.set_process(false)
	var ad_root := Node3D.new()
	ad_root.name = "airdrop"
	var beacon_beam: Node3D = ad.get("_beacon_beam") as Node3D
	if beacon_beam:
		beacon_beam.name = "BeaconBeam"
	var beacon_ring: Node3D = ad.get("_beacon_ring") as Node3D
	if beacon_ring:
		beacon_ring.name = "BeaconRingOuter"
	var beacon_inner: Node3D = ad.get("_beacon_inner") as Node3D
	if beacon_inner:
		beacon_inner.name = "BeaconRingInner"
	for ch in ad.get_children():
		if ch is Node3D and ch.name != "airdrop":
			ad.remove_child(ch)
			ad_root.add_child(ch)
	props_meta["airdrop"] = _save_prop(baker, ad_root, out_dir, "props/airdrop.glb", "airdrop")
	tree.root.remove_child(ad)
	ad.free()
	await tree.process_frame

	# 7. Deployed zones: Shield Dome, Umbrella Open, Sandbag Wall, Planted Lightning Rod
	props_meta["shield_dome"] = _export_shield_dome(baker, out_dir)
	props_meta["umbrella_open"] = _save_prop(baker, item_models.call("projectile", "umbrella_open"), out_dir, "props/umbrella_open.glb", "umbrella_open")
	props_meta["sandbag_wall"] = _save_prop(baker, item_models.call("projectile", "sandbag_wall"), out_dir, "props/sandbag_wall.glb", "sandbag_wall")
	props_meta["lightning_rod_planted"] = _save_prop(baker, item_models.call("projectile", "lightning_rod"), out_dir, "props/lightning_rod_planted.glb", "lightning_rod_planted")

	# 8. Decon shower dynamic cell rack + status ring + spray cone
	props_meta["decon_shower_cells"] = _export_decon_cells(baker, out_dir)

	# 9. Projectiles
	var proj_meta := {}
	for pid in PROJECTILE_IDS:
		var pnode: Node3D = null
		if pid == "boombox_launcher":
			pnode = gun_models.call("projectile", "boombox")
		elif pid == "shield_dome":
			pnode = gun_models.call("projectile", "dome")
		elif pid == "frag":
			pnode = gun_models.call("projectile", "frag")
		elif pid == "bug_bomb":
			pnode = gun_models.call("projectile", "bug_bomb")
		else:
			pnode = catalog.call("projectile_model", pid)
		if pnode != null:
			proj_meta[pid] = _save_prop(baker, pnode, out_dir, "projectiles/%s.glb" % pid, pid)

	# Enemy spore & acid globs (enemies/mister/spore_projectile.gd)
	proj_meta["spore_glob"] = _export_spore_glob(baker, out_dir, false)
	proj_meta["acid_glob"] = _export_spore_glob(baker, out_dir, true)

	var combined := {
		"weapons": weapons_meta,
		"props": props_meta,
		"projectiles": proj_meta,
	}
	baker.write_json(out_dir.path_join("weapons/weapons.json"), combined)
	print("  -> Exported %d weapons/items (view+pickup), %d props, %d projectiles" % [weapons_meta.size(), props_meta.size(), proj_meta.size()])
	return combined


func _save_prop(baker: RefCounted, node: Node3D, out_dir: String, rel: String, id: String) -> Dictionary:
	var wrap := Node3D.new()
	wrap.name = id
	wrap.add_child(node)
	baker.clear_caches()
	var stats: Dictionary = baker.sanitize_node_for_gltf(wrap, true)
	var wr: Dictionary = baker.write_glb(wrap, out_dir.path_join(rel))
	if not wr.ok:
		push_error("Failed writing %s: %s" % [rel, wr.get("error", "")])
	wrap.free()
	return {
		"id": id,
		"glb": rel,
		"triangles": stats.triangles,
		"draw_calls": stats.draw_calls,
		"bytes": wr.get("bytes", 0),
	}


func _export_shield_dome(baker: RefCounted, out_dir: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "shield_dome"
	var color := Color(0.35, 0.95, 1.0)
	var radius := 6.5

	var hemi := SphereMesh.new()
	hemi.radius = 1.0
	hemi.height = 1.0
	hemi.is_hemisphere = true
	hemi.radial_segments = 24
	hemi.rings = 8
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = hemi
	shell.scale = Vector3(radius, radius, radius)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smat.albedo_color = Color(color.r, color.g, color.b, 0.16)
	shell.material_override = smat
	root.add_child(shell)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.0
	torus.rings = 28
	torus.ring_segments = 5
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = torus
	rim.position.y = 0.055
	rim.scale = Vector3(radius, 1.0, radius)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.albedo_color = Color(color.r, color.g, color.b, 0.65)
	rim.material_override = rmat
	root.add_child(rim)

	var info := _save_prop(baker, root, out_dir, "props/shield_dome.glb", "shield_dome")
	info["radius"] = radius
	info["warning_color"] = "#ffc365"
	return info


func _export_decon_cells(baker: RefCounted, out_dir: String) -> Dictionary:
	# Mirrors props/decon_shower.gd (origin at interact offset y=1.0 above marker).
	var root := Node3D.new()
	root.name = "decon_shower_cells"
	var rack := Node3D.new()
	rack.name = "CellRack"
	root.add_child(rack)
	for i in 4:
		var cell := MeshInstance3D.new()
		cell.name = "Cell%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.14
		cyl.bottom_radius = 0.14
		cyl.height = 0.13
		cyl.radial_segments = 12
		cell.mesh = cyl
		cell.position = Vector3(0, 0.05 + i * 0.19, 0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("#39f0ec")
		cell.material_override = mat
		rack.add_child(cell)

	var ring := MeshInstance3D.new()
	ring.name = "HeadRing"
	var torus := TorusMesh.new()
	torus.rings = 24
	torus.ring_segments = 6
	torus.inner_radius = 0.32
	torus.outer_radius = 0.4
	ring.mesh = torus
	ring.position = Vector3(0, 1.58, 0)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color("#2EE6E6")
	ring.material_override = rmat
	root.add_child(ring)

	var spray := Node3D.new()
	spray.name = "Spray"
	spray.position = Vector3(0, 1.5, 0)
	root.add_child(spray)
	var mist_mat := StandardMaterial3D.new()
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.albedo_color = Color(0.55, 0.96, 1.0, 0.45)
	for i in 8:
		var a := TAU * i / 8.0
		var st := MeshInstance3D.new()
		st.name = "Stream%d" % i
		var sc := CylinderMesh.new()
		sc.top_radius = 0.018
		sc.bottom_radius = 0.032
		sc.height = 2.35
		sc.radial_segments = 6
		st.mesh = sc
		st.material_override = mist_mat
		st.position = Vector3(cos(a) * 0.22, -1.18, sin(a) * 0.22)
		st.rotation = Vector3(sin(a) * 0.14, 0.0, -cos(a) * 0.14)
		spray.add_child(st)
	var cone := MeshInstance3D.new()
	cone.name = "SprayCone"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.68
	cm.height = 2.3
	cm.radial_segments = 12
	cone.mesh = cm
	cone.position = Vector3(0, -1.18, 0)
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.albedo_color = Color(0.35, 0.92, 0.95, 0.18)
	cone.material_override = cmat
	spray.add_child(cone)

	return _save_prop(baker, root, out_dir, "props/decon_shower_cells.glb", "decon_shower_cells")


func _export_spore_glob(baker: RefCounted, out_dir: String, acid: bool) -> Dictionary:
	var id := "acid_glob" if acid else "spore_glob"
	var root := Node3D.new()
	root.name = id
	var mi := MeshInstance3D.new()
	mi.name = "Glob"
	var sp := SphereMesh.new()
	sp.radial_segments = 12
	sp.rings = 6
	sp.radius = 0.2
	sp.height = 0.4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#ecfb5b") if acid else Color(0.5, 1.0, 0.3)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 1.4
	mi.mesh = sp
	mi.material_override = mat
	root.add_child(mi)
	return _save_prop(baker, root, out_dir, "projectiles/%s.glb" % id, id)
