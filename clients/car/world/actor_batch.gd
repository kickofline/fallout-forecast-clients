extends Reference
## Build and cache one rigid vertex-skinned mesh per actor glTF. The original
## pivots still drive the pose, visibility and weapon mount. A uniform palette
## avoids the vertex texture and CPU skinning requirements of GLES2 Skeleton.

const SHADER = preload("res://shaders/actor.shader")
const MAX_PARTS = 16   # 64 vec4 uniforms, leaving room for GLES2 scene uniforms.
const HIDDEN = Transform(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var _templates = {}
var _shaders = {}


class Rig:
	var root: Spatial
	var mesh: MeshInstance
	var pivots = []
	var uniforms = []
	var materials = []
	var moving_mesh: ArrayMesh
	var still_mesh: ArrayMesh
	var still = false
	var snap = -1.0
	var wetness = -1.0

	func set_still(enabled: bool) -> void:
		if still == enabled or still_mesh == null:
			return
		still = enabled
		mesh.mesh = still_mesh if still else moving_mesh
		for i in materials.size():
			mesh.set_surface_material(i, materials[i])
			materials[i].set_shader_param("animated", not still)

	func set_style(next_snap: float, next_wetness: float) -> void:
		if snap == next_snap and wetness == next_wetness:
			return
		snap = next_snap
		wetness = next_wetness
		for material in materials:
			material.set_shader_param("snap", snap)
			material.set_shader_param("wetness", wetness)

	func update_pose() -> void:
		if still:
			return
		var inverse = root.global_transform.affine_inverse()
		for i in pivots.size():
			var pivot: Spatial = pivots[i]
			var pose = inverse * pivot.global_transform if pivot.is_visible_in_tree() else HIDDEN
			for material in materials:
				material.set_shader_param(uniforms[i], pose)


func instance(scene: PackedScene, pivots: Array, static_lod: bool):
	var key = scene.resource_path
	if not _templates.has(key):
		_templates[key] = _build(scene, pivots, static_lod)
	var template = _templates[key]
	if template == null:
		return null
	var result = Rig.new()
	result.root = template.root.duplicate(0)
	result.mesh = MeshInstance.new()
	result.mesh.name = "ActorMesh"
	result.moving_mesh = template.mesh
	result.still_mesh = template.still_mesh
	result.mesh.mesh = result.moving_mesh
	result.root.add_child(result.mesh)
	for path in template.paths:
		result.pivots.append(result.root.get_node(path))
	result.uniforms = template.uniforms
	for i in result.moving_mesh.get_surface_count():
		var material = ShaderMaterial.new()
		material.shader = _shader(result.pivots.size(), i == template.alpha_surface)
		result.mesh.set_surface_material(i, material)
		result.materials.append(material)
	return result


func clear() -> void:
	for template in _templates.values():
		if template:
			template.root.free()
	_templates.clear()
	_shaders.clear()


func _build(scene: PackedScene, pivots: Array, static_lod: bool):
	var root: Spatial = scene.instance()
	var owners = []
	var poses = []
	var render_nodes = []
	var valid = _collect(root, root, pivots, Transform(), Transform(), render_nodes)
	var opaque = _group()
	var alpha = _group()
	for row in render_nodes:
		var mesh: MeshInstance = row[0]
		var owner: Spatial = row[1]
		var local: Transform = row[2]
		var rest: Transform = row[3]
		var part = owners.find(owner)
		if part == -1:
			part = owners.size()
			owners.append(owner)
			poses.append(rest)
		for i in mesh.mesh.get_surface_count():
			var m: SpatialMaterial = _material(mesh, i)
			if not _supported(mesh.mesh, i, m):
				valid = false
				break
			_append(alpha if m.flags_transparent else opaque, mesh.mesh.surface_get_arrays(i), m, local, part)
		if not valid:
			break
	if not valid or owners.empty() or owners.size() > MAX_PARTS:
		root.free()
		push_warning("Actor batch unsupported for %s" % scene.resource_path)
		return null

	var rig_mesh = ArrayMesh.new()
	var still_mesh = ArrayMesh.new() if static_lod else null
	var bounds = AABB()
	var alpha_surface = -1
	for group in [opaque, alpha]:
		if group.vertices.empty():
			continue
		if group == alpha:
			alpha_surface = rig_mesh.get_surface_count()
		var arrays = _arrays(group)
		rig_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var rest_vertices = PoolVector3Array()
		var rest_normals = PoolVector3Array()
		rest_vertices.resize(group.vertices.size())
		rest_normals.resize(group.vertices.size())
		for i in group.vertices.size():
			var xf: Transform = poses[int(group.uv[i].x)]
			var point = xf.xform(group.vertices[i])
			bounds = bounds.expand(point)
			if still_mesh:
				rest_vertices[i] = point
				rest_normals[i] = xf.basis.xform(group.normals[i]).normalized()
		if still_mesh:
			arrays[Mesh.ARRAY_VERTEX] = rest_vertices
			arrays[Mesh.ARRAY_NORMAL] = rest_normals
			still_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# CPU culling can't see the shader's pose. Include limb swing, Thunderhead
	# charge scale, and the orbit of the Cumulus sacs.
	rig_mesh.custom_aabb = bounds.grow(max(1.25, bounds.size.length() * 0.55))
	var paths = []
	var uniforms = []
	for i in owners.size():
		paths.append(root.get_path_to(owners[i]))
		uniforms.append("part_%d" % i)
	_prune(root, pivots)
	return {"root": root, "paths": paths, "uniforms": uniforms, "mesh": rig_mesh,
		"still_mesh": still_mesh, "alpha_surface": alpha_surface}


func _collect(node: Spatial, owner: Spatial, pivots: Array, local: Transform, rest: Transform, out: Array) -> bool:
	if node is MeshInstance and node.mesh:
		out.append([node, owner, local, rest])
	for child in node.get_children():
		if child is Spatial:
			var next = child if child.name in pivots else owner
			if not _collect(child, next, pivots, Transform() if next == child else local * child.transform,
					rest * local * child.transform if next == child else rest, out):
				return false
		elif child.get_child_count() > 0:
			return false
	return true


func _prune(node: Node, pivots: Array) -> bool:
	var keep = node.name in pivots
	for child in node.get_children():
		if _prune(child, pivots):
			keep = true
		else:
			child.free()
	if node is MeshInstance:
		node.mesh = null
	return keep


func _material(mesh: MeshInstance, i: int) -> SpatialMaterial:
	var m = mesh.material_override
	if m == null:
		m = mesh.get_surface_material(i)
	if m == null:
		m = mesh.mesh.surface_get_material(i)
	return m as SpatialMaterial


func _supported(mesh: Mesh, i: int, m: SpatialMaterial) -> bool:
	return m != null and mesh.surface_get_primitive_type(i) == Mesh.PRIMITIVE_TRIANGLES 		and m.albedo_texture == null and m.params_cull_mode == SpatialMaterial.CULL_BACK 		and m.params_billboard_mode == SpatialMaterial.BILLBOARD_DISABLED 		and m.params_blend_mode == SpatialMaterial.BLEND_MODE_MIX and not m.flags_no_depth_test and not m.params_grow 		and not (m.flags_transparent and m.emission_enabled and not m.flags_unshaded)


func _group() -> Dictionary:
	return {"vertices": [], "normals": [], "colors": [], "uv": [], "extra": [], "indices": []}


func _append(group: Dictionary, arrays: Array, material: SpatialMaterial, xf: Transform, part: int) -> void:
	var vertices: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var colors = arrays[Mesh.ARRAY_COLOR]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var offset: int = group.vertices.size()
	var style = 0.0
	if material.flags_unshaded:
		style = 1.0
	elif material.emission_enabled or material.flags_transparent:
		style = 2.0
	var emission = Color(0, 0, 0)
	if style == 2.0 and material.emission_enabled:
		emission = material.emission * (max(material.emission_energy, 2.0) / 4.0)
	var normal_xf = xf.basis.inverse().transposed()
	for i in vertices.size():
		group.vertices.append(xf.xform(vertices[i]))
		group.normals.append(normal_xf.xform(normals[i]).normalized() if normals != null else Vector3.UP)
		var color = material.albedo_color
		if material.vertex_color_use_as_albedo and colors != null:
			color *= colors[i]
		if not material.flags_transparent:
			color.a = emission.b
		group.colors.append(color)
		group.uv.append(Vector2(part, style))
		group.extra.append(Vector2(emission.r, emission.g))
	var indexed = indices != null and not indices.empty()
	var count: int = indices.size() if indexed else vertices.size()
	for i in count:
		group.indices.append(offset + (indices[i] if indexed else i))


func _arrays(group: Dictionary) -> Array:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PoolVector3Array(group.vertices)
	arrays[Mesh.ARRAY_NORMAL] = PoolVector3Array(group.normals)
	arrays[Mesh.ARRAY_COLOR] = PoolColorArray(group.colors)
	arrays[Mesh.ARRAY_TEX_UV] = PoolVector2Array(group.uv)
	arrays[Mesh.ARRAY_TEX_UV2] = PoolVector2Array(group.extra)
	arrays[Mesh.ARRAY_INDEX] = PoolIntArray(group.indices)
	return arrays


func _shader(parts: int, alpha: bool) -> Shader:
	var key = Vector2(parts, int(alpha))
	if not _shaders.has(key):
		var uniforms = PoolStringArray()
		for i in parts:
			uniforms.append("uniform mat4 part_%d;" % i)
		var code = SHADER.code.replace("uniform mat4 part_0;", uniforms.join("\n"))
		code = code.replace("return part_0;", _select_part(0, parts))
		if alpha:
			code = code.replace("// ALPHA is assigned only in the translucent shader variant.",
				"ALPHA = COLOR.a;\n\tif (UV.y >= 1.5) { EMISSION = vec3(0.0); }")
		var shader = Shader.new()
		shader.code = code
		_shaders[key] = shader
	return _shaders[key]


func _select_part(first: int, end: int) -> String:
	if end - first == 1:
		return "return part_%d;" % first
	var mid = (first + end) / 2
	return "if (part < %.1f) { %s } else { %s }" % [mid - 0.5, _select_part(first, mid), _select_part(mid, end)]
