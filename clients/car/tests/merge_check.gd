extends SceneTree
# godot --path client --no-window -s res://tests/merge_check.gd
func _count(n: Node) -> int:
	var c = 1 if n is MeshInstance and n.mesh != null else 0
	var s = 0
	if n is MeshInstance and n.mesh:
		s = n.mesh.get_surface_count()
	for ch in n.get_children():
		c += _count(ch)
	return c

func _surfaces(n: Node) -> int:
	var s = 0
	if n is MeshInstance and n.mesh:
		s = n.mesh.get_surface_count()
	for ch in n.get_children():
		s += _surfaces(ch)
	return s

func _idle(_d):
	var rm = root.get_node("RetroMat")
	for p in ["res://assets/characters/enemies/drip.glb", "res://assets/characters/player/standard_teal.glb", "res://assets/weapons/view/pump_shotgun.glb"]:
		var sc = load(p)
		var raw = sc.instance()
		var merged = rm.instance_merged(sc, ["Rig", "Body", "Head", "Jaw", "ArmL", "ArmR", "ElbowL", "ElbowR", "LegL", "LegR", "KneeL", "KneeR", "Hips", "Torso", "ForearmL", "ForearmR", "ShinL", "ShinR", "WeaponMount", "Muzzle", "Pump"])
		print(p, " raw meshes=", _count(raw), " surfaces=", _surfaces(raw), " -> merged meshes=", _count(merged), " surfaces=", _surfaces(merged))
		var mi = raw.find_node("*", true, false)
		for c in raw.get_children():
			print("   child ", c.name, " ", c.get_class())
	quit()
	return true
