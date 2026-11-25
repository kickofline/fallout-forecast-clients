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
		s.set_shader_param("snap", snap)
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
