extends SceneTree
func _walk(n, depth):
	if n is MeshInstance and n.mesh:
		var info = []
		for i in n.mesh.get_surface_count():
			var m = n.get_surface_material(i)
			var m2 = n.mesh.surface_get_material(i)
			info.append([n.mesh.surface_get_primitive_type(i), m.get_class() if m else "null", m2.get_class() if m2 else "null",
				(m2.flags_unshaded if m2 is SpatialMaterial else "-"), (m2.emission_enabled if m2 is SpatialMaterial else "-"),
				(m2.flags_transparent if m2 is SpatialMaterial else "-"), (m2.albedo_texture != null if m2 is SpatialMaterial else "-")])
		print(depth, " ", n.name, " override=", n.material_override, " ", info)
	for c in n.get_children():
		_walk(c, depth + 1)
func _idle(_d):
	_walk(load("res://assets/characters/enemies/drip.glb").instance(), 0)
	quit()
	return true
