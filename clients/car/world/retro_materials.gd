extends Node
## Autoload "RetroMat": prepares every imported model for the GLES2 look.
## - Nearest filtering on 64x64 world textures (README: clear FLAG_FILTER).
## - Emissive neon gets emission_energy ~2 (Godot 3 clamps glTF emissive).
## - With the retro look on, opaque lit SpatialMaterials are swapped for the
##   PS1 vertex-snap shader (shaders/ps1.shader), like retro_screen.gd does.
## Converted materials are cached per source material.

const PS1 = preload("res://shaders/ps1.shader")
const PS1_TRI = preload("res://shaders/ps1_triplanar.shader")

var snap = 120.0
var _converted = {}
var _fixed = {}
var _all = []
var _wetness = 0.0


func prepare(root: Node) -> void:
	if root == null:
		return
	_walk(root)


func _walk(node: Node) -> void:
	if node is MeshInstance:
		_prepare_mesh(node)
	for c in node.get_children():
		_walk(c)


func _prepare_mesh(mi: MeshInstance) -> void:
	if mi.material_override:
		var o = _convert(mi.material_override)
		if o:
			mi.material_override = o
		return
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m = mi.get_surface_material(i)
		if m == null:
			m = mi.mesh.surface_get_material(i)
		var c = _convert(m)
		if c:
			mi.set_surface_material(i, c)


func _fix(m: SpatialMaterial) -> void:
	if _fixed.has(m):
		return
	_fixed[m] = true
	var tex = m.albedo_texture
	if tex and not ("mist" in tex.resource_path):
		tex.flags = Texture.FLAG_REPEAT
	if m.emission_enabled:
		m.emission_energy = max(m.emission_energy, 2.0)
	# GLES2 vertex lighting: keep materials cheap.
	m.flags_vertex_lighting = true


func _convert(material: Material) -> Material:
	if material == null or not (material is SpatialMaterial):
		return null
	var m = material as SpatialMaterial
	_fix(m)
	if not Settings.retro_enabled:
		return null
	if _converted.has(m):
		return _converted[m]
	if m.flags_transparent or m.flags_unshaded or m.emission_enabled or m.params_grow or m.flags_no_depth_test \
			or m.params_billboard_mode != SpatialMaterial.BILLBOARD_DISABLED or m.params_cull_mode != SpatialMaterial.CULL_BACK:
		_converted[m] = null
		return null
	var s = ShaderMaterial.new()
	if m.uv1_triplanar:
		s.shader = PS1_TRI
		s.set_shader_param("uv_scale", m.uv1_scale)
	else:
		s.shader = PS1
		s.set_shader_param("uv_scale", m.uv1_scale)
		s.set_shader_param("uv_offset", m.uv1_offset)
		s.set_shader_param("use_vertex_color", m.vertex_color_use_as_albedo)
		s.set_shader_param("use_texture", m.albedo_texture != null)
		# Baked-triplanar surfaces (exporter names them tri_*) don't snap, like
		# the original's triplanar path; snapped ground/road layers z-fight.
		s.set_shader_param("snap", 0.0 if m.resource_name.begins_with("tri_") else snap)
	s.set_shader_param("albedo", m.albedo_color)
	if m.albedo_texture:
		s.set_shader_param("albedo_texture", m.albedo_texture)
	s.set_shader_param("dry_roughness", m.roughness)
	s.set_shader_param("wetness", _wetness)
	_converted[m] = s
	_all.append(s)
	return s


## Storm wetness on every converted surface (cheap uniform write).
func set_wetness(w: float) -> void:
	if abs(w - _wetness) < 0.02:
		return
	_wetness = w
	for s in _all:
		s.set_shader_param("wetness", w)


func clear_cache() -> void:
	_converted.clear()
	_all.clear()


# ------------------------------------------------------------------ merging
## Character / weapon glbs use one flat-colour material per primitive (~30
## draw calls per model). instance_merged() bakes each lit, untextured
## material's colour into vertex colours and merges everything that moves
## together (the subtree of one animated pivot) into a single surface, so a
## rig costs about one draw call per limb. Results are cached per scene.

var _templates = {}
var _merged_material: SpatialMaterial


func _exit_tree() -> void:
	for template in _templates.values():
		template.free()
	_templates.clear()


func instance_merged(scene: PackedScene, pivots: Array) -> Spatial:
	if scene == null:
		return null
	var key = scene.resource_path + "|" + str(pivots)
	if not _templates.has(key):
		var t: Spatial = scene.instance()
		_merge(t, pivots)
		_templates[key] = t
	return _templates[key].duplicate()


func _shared_material() -> SpatialMaterial:
	if _merged_material == null:
		_merged_material = SpatialMaterial.new()
		_merged_material.vertex_color_use_as_albedo = true
		_merged_material.albedo_color = Color.white
		_merged_material.roughness = 1.0
		_merged_material.flags_vertex_lighting = true
	return _merged_material


func _merge(root: Spatial, pivots: Array) -> void:
	var groups = {}      # owner node -> {verts, normals, colors, indices} (Arrays)
	_collect(root, Transform(), root, pivots, groups)
	for owner in groups:
		var g = groups[owner]
		if g.verts.empty():
			continue
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PoolVector3Array(g.verts)
		arrays[Mesh.ARRAY_NORMAL] = PoolVector3Array(g.normals)
		arrays[Mesh.ARRAY_COLOR] = PoolColorArray(g.colors)
		arrays[Mesh.ARRAY_INDEX] = PoolIntArray(g.indices)
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi = MeshInstance.new()
		mi.name = "Merged"
		mi.mesh = mesh
		mi.material_override = _shared_material()
		owner.add_child(mi)


func _collect(node: Node, rel: Transform, owner: Spatial, pivots: Array, groups: Dictionary) -> void:
	for c in node.get_children():
		if not (c is Spatial):
			continue
		var child_owner = owner
		var child_rel = rel * c.transform
		if c.name in pivots:
			child_owner = c
			child_rel = Transform()
		_collect(c, child_rel, child_owner, pivots, groups)
		if c is MeshInstance and c.mesh and c.material_override == null:
			_split(c, child_rel, child_owner, groups)


func _surface_material(mi: MeshInstance, i: int) -> Material:
	var m = mi.get_surface_material(i)
	return m if m != null else mi.mesh.surface_get_material(i)


func _flat(m) -> bool:
	return m is SpatialMaterial and not (m.flags_unshaded or m.flags_transparent or m.emission_enabled 		or m.albedo_texture or m.params_billboard_mode != SpatialMaterial.BILLBOARD_DISABLED)


## Moves the flat-colour surfaces of mi into its owner's merge group; the
## rest (unshaded eyes, emissive cores, textured parts) stay on mi.
func _split(mi: MeshInstance, xf: Transform, owner: Spatial, groups: Dictionary) -> void:
	var keep = ArrayMesh.new()
	var kept = 0
	var merged = 0
	for i in mi.mesh.get_surface_count():
		var m = _surface_material(mi, i)
		if mi.mesh.surface_get_primitive_type(i) == Mesh.PRIMITIVE_TRIANGLES and _flat(m):
			_append(mi.mesh.surface_get_arrays(i), m, xf, owner, groups)
			merged += 1
		else:
			keep.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(i), mi.mesh.surface_get_arrays(i))
			keep.surface_set_material(kept, m)
			kept += 1
	if merged == 0:
		return
	for i in mi.get_surface_material_count():
		mi.set_surface_material(i, null)
	mi.mesh = keep if kept > 0 else null


func _append(arr: Array, m: SpatialMaterial, xf: Transform, owner: Spatial, groups: Dictionary) -> void:
	if not groups.has(owner):
		groups[owner] = {"verts": [], "normals": [], "colors": [], "indices": []}
	var g = groups[owner]
	var tint = m.albedo_color
	var use_vc = m.vertex_color_use_as_albedo
	var v: PoolVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n = arr[Mesh.ARRAY_NORMAL]
	var c = arr[Mesh.ARRAY_COLOR]
	var idx = arr[Mesh.ARRAY_INDEX]
	var base = g.verts.size()
	var verts: Array = g.verts
	var normals: Array = g.normals
	var colors: Array = g.colors
	var indices: Array = g.indices
	for k in v.size():
		verts.append(xf.xform(v[k]))
		normals.append(xf.basis.xform(n[k]).normalized() if n != null and k < n.size() else Vector3.UP)
		var col = tint
		if use_vc and c != null and k < c.size():
			col = col * c[k]
		colors.append(col)
	if idx != null and idx.size() > 0:
		for k in idx.size():
			indices.append(base + idx[k])
	else:
		for k in v.size():
			indices.append(base + k)
