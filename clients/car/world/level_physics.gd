extends Reference
## Level collision + navigation for the Full tier and solo play.
##
## OWNER: the exporter/physics worker. This file is a working stub so other
## code can call it before the real data exists.
##
## Contract:
##   var lp = preload("res://world/level_physics.gd").new()
##   var info = lp.build(level_root, map_id)   # call once after the level is instanced
##   info.navigation  -> Navigation (Godot 3) node or null; parented under level_root
##   info.source      -> "exported" (assets/maps/<id>_physics.json) | "trimesh_fallback"
##
## Collision layers (match the native game, client-responsibilities.md §3):
##   bit 0 (layer 1) world geometry: floors, walls, roofs, props. Player KCC,
##                   roof rays and enemy movement collide with this.
##   bit 3 (layer 4) shelter areas (Area nodes from the map sidecar `shelters`).
## Enemies/players are NOT on layer 1.
##
## Navigation: Navigation.get_simple_path(from, to) in world coordinates.


func build(level_root: Spatial, _map_id: String) -> Dictionary:
	# Fallback: trimesh collision from every render mesh, no navigation.
	var n = 0
	for mi in _meshes(level_root):
		mi.create_trimesh_collision()
		n += 1
	print("PHYSICS fallback trimesh meshes=%d" % n)
	return {"navigation": null, "source": "trimesh_fallback"}


func _meshes(node: Node, out := []) -> Array:
	if node is MeshInstance and node.mesh:
		out.append(node)
	for c in node.get_children():
		_meshes(c, out)
	return out
