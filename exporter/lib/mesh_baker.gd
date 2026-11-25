extends RefCounted
## Core geometry, material, UV, and glTF baking utilities for Fallout Forecast -> Godot 3.6 GLES2.
## No compile-time project class_name references so this runs cleanly under `godot -s`.

const TIDE_SHADER_SUFFIX := "props/harbor/tide.gdshader"

var _texture_cache := {}
var _tide_texture: ImageTexture
var _mist_textures := {}


func clear_caches() -> void:
	_texture_cache.clear()
	_tide_texture = null
	_mist_textures.clear()


## Collect all renderable geometry under `root`, bake world-triplanar UVs,
## custom shaders, UV transforms, and negative-scale winding, then merge into
## one ArrayMesh surface per unique canonical material.
## Returns { "scene": Node3D, "triangles": int, "draw_calls": int, "materials": int,
##           "bounds_min": Vector3, "bounds_max": Vector3, "buckets": Dictionary }
func bake_level_to_merged_scene(root: Node3D, map_name: String, merge_solid_colors := false) -> Dictionary:
	var buckets := {}  # mat_key -> { "mat": StandardMaterial3D, "verts": PackedVector3Array, ... }
	var stats := {"skipped_hidden": 0, "csg_baked": 0, "mi_baked": 0, "mm_baked": 0, "labels_baked": 0}
	var root_inv := root.global_transform.affine_inverse()

	_collect_node_recursive(root, root, root_inv, buckets, stats, merge_solid_colors)

	var out_root := Node3D.new()
	out_root.name = map_name

	var total_tris := 0
	var draw_calls := 0
	var bounds_min := Vector3(INF, INF, INF)
	var bounds_max := Vector3(-INF, -INF, -INF)

	# Put opaque buckets first, transparent buckets second for clean sorting.
	var keys: Array = buckets.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ma: StandardMaterial3D = buckets[a].mat
		var mb: StandardMaterial3D = buckets[b].mat
		var ta := 1 if ma.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0
		var tb := 1 if mb.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0
		if ta != tb:
			return ta < tb
		return a < b
	)

	# Split into one MeshInstance3D per transparency/shading bucket group or a single
	# multi-surface MeshInstance3D per batch. Using one MeshInstance3D per bucket gives
	# Godot 3.6 per-material frustum culling if needed, or one combined MeshInstance3D
	# with N surfaces (1 draw call per surface). Wait: putting opaque static geometry
	# into spatial chunks OR one MeshInstance3D per material bucket?
	# One MeshInstance3D per material bucket keeps node names readable (Mat_000_asphalt)
	# and has the exact same draw-call count (= number of surfaces).
	var idx := 0
	for key in keys:
		var b: Dictionary = buckets[key]
		var verts: PackedVector3Array = b.verts
		var indices: PackedInt32Array = b.indices
		if verts.is_empty() or indices.is_empty():
			continue
		var tri_count := int(indices.size() / 3)
		total_tris += tri_count
		draw_calls += 1

		for v in verts:
			bounds_min = bounds_min.min(v)
			bounds_max = bounds_max.max(v)

		var mesh := _build_array_mesh_from_bucket(b)
		var mi := MeshInstance3D.new()
		mi.name = _safe_bucket_name(idx, b.tag)
		mi.mesh = mesh
		out_root.add_child(mi)
		mi.owner = out_root
		idx += 1

	if not is_finite(bounds_min.x):
		bounds_min = Vector3.ZERO
		bounds_max = Vector3.ZERO

	return {
		"scene": out_root,
		"triangles": total_tris,
		"draw_calls": draw_calls,
		"materials": draw_calls,
		"bounds_min": bounds_min,
		"bounds_max": bounds_max,
		"buckets": buckets,
		"stats": stats,
	}


## Build a decimated version of previously collected `buckets` using per-material
## spatial vertex-clustering grid collapse, dropping degenerate triangles.
func build_decimated_scene(buckets: Dictionary, map_name: String, target_tris := 110000) -> Dictionary:
	var orig_tris := 0
	for key in buckets:
		orig_tris += int((buckets[key].indices as PackedInt32Array).size() / 3)

	# Pick grid cell size iteratively so triangle count lands under target_tris.
	var cell := 0.14
	var best_scene: Node3D = null
	var best_tris := orig_tris
	var best_dc := 0
	for _attempt in 5:
		var out_root := Node3D.new()
		out_root.name = map_name + "_low"
		var total_tris := 0
		var dc := 0
		var idx := 0
		var keys: Array = buckets.keys()
		keys.sort()
		for key in keys:
			var b: Dictionary = buckets[key]
			var dec := _decimate_bucket(b, cell)
			if dec.is_empty():
				continue
			var tris := int((dec.indices as PackedInt32Array).size() / 3)
			if tris == 0:
				continue
			total_tris += tris
			dc += 1
			var mi := MeshInstance3D.new()
			mi.name = _safe_bucket_name(idx, b.tag)
			mi.mesh = _build_array_mesh_from_bucket(dec)
			out_root.add_child(mi)
			mi.owner = out_root
			idx += 1
		if best_scene != null:
			best_scene.free()
		best_scene = out_root
		best_tris = total_tris
		best_dc = dc
		if total_tris <= target_tris:
			break
		var ratio := sqrt(float(total_tris) / float(maxi(target_tris, 1)))
		cell *= clampf(ratio * 1.12, 1.25, 2.2)

	return {
		"scene": best_scene,
		"triangles": best_tris,
		"draw_calls": best_dc,
		"cell_size": cell,
	}


## Split previously collected `buckets` into a ground grid (XZ cells of
## `cell` metres, by triangle centroid) and emit one MeshInstance3D per cell
## with one surface per material. Godot 3 frustum-culls per instance, which
## the whole-map merge defeats; full detail is kept (no decimation).
func build_chunked_scene(buckets: Dictionary, map_name: String, cell := 20.0) -> Dictionary:
	var keys: Array = buckets.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ta := 1 if (buckets[a].mat as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0
		var tb := 1 if (buckets[b].mat as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0
		if ta != tb:
			return ta < tb
		return a < b
	)
	var cells := {}  # Vector2i -> Array of sub-buckets (in material order)
	for key in keys:
		var b: Dictionary = buckets[key]
		var verts: PackedVector3Array = b.verts
		var idx: PackedInt32Array = b.indices
		if verts.is_empty() or idx.is_empty():
			continue
		var per_cell := {}  # Vector2i -> Array of triangle start offsets (Packed* would copy on cast)
		for t in range(0, idx.size(), 3):
			var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			var k := Vector2i(floori(c.x / cell), floori(c.z / cell))
			if not per_cell.has(k):
				per_cell[k] = []
			(per_cell[k] as Array).append(t)
		for k in per_cell:
			if not cells.has(k):
				cells[k] = []
			(cells[k] as Array).append(_sub_bucket(b, per_cell[k]))

	var out_root := Node3D.new()
	out_root.name = map_name + "_chunked"
	var cell_keys: Array = cells.keys()
	cell_keys.sort()
	var surfaces := 0
	var max_surfaces := 0
	var tris := 0
	for k in cell_keys:
		var mesh := ArrayMesh.new()
		for sb in cells[k]:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = sb.verts
			arrays[Mesh.ARRAY_NORMAL] = sb.normals
			if sb.has_uv:
				arrays[Mesh.ARRAY_TEX_UV] = sb.uvs
			if sb.has_color:
				arrays[Mesh.ARRAY_COLOR] = sb.colors
			arrays[Mesh.ARRAY_INDEX] = sb.indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, sb.mat)
			tris += int((sb.indices as PackedInt32Array).size() / 3)
		surfaces += mesh.get_surface_count()
		max_surfaces = maxi(max_surfaces, mesh.get_surface_count())
		var mi := MeshInstance3D.new()
		mi.name = "Cell_%d_%d" % [k.x, k.y]
		mi.mesh = mesh
		out_root.add_child(mi)
		mi.owner = out_root
	return {
		"scene": out_root,
		"triangles": tris,
		"cells": cell_keys.size(),
		"surfaces": surfaces,
		"max_cell_surfaces": max_surfaces,
		"cell_size": cell,
	}


## The triangles starting at `tri_starts` of bucket `b`, with compacted vertices.
func _sub_bucket(b: Dictionary, tri_starts: Array) -> Dictionary:
	var verts: PackedVector3Array = b.verts
	var normals: PackedVector3Array = b.normals
	var uvs: PackedVector2Array = b.uvs
	var colors: PackedColorArray = b.colors
	var idx: PackedInt32Array = b.indices
	var has_uv: bool = b.has_uv and uvs.size() == verts.size()
	var has_col: bool = b.has_color and colors.size() == verts.size()
	var remap := {}
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ou := PackedVector2Array()
	var oc := PackedColorArray()
	var oi := PackedInt32Array()
	oi.resize(tri_starts.size() * 3)
	var w := 0
	for t in tri_starts:
		for j in 3:
			var vi: int = idx[t + j]
			var ni: int
			if remap.has(vi):
				ni = remap[vi]
			else:
				ni = ov.size()
				remap[vi] = ni
				ov.append(verts[vi])
				on.append(normals[vi] if vi < normals.size() else Vector3.UP)
				if has_uv:
					ou.append(uvs[vi])
				if has_col:
					oc.append(colors[vi])
			oi[w] = ni
			w += 1
	return {"mat": b.mat, "tag": b.tag, "verts": ov, "normals": on, "uvs": ou, "colors": oc,
		"indices": oi, "has_uv": has_uv, "has_color": has_col}


func _decimate_bucket(b: Dictionary, cell: float) -> Dictionary:
	var verts: PackedVector3Array = b.verts
	var normals: PackedVector3Array = b.normals
	var uvs: PackedVector2Array = b.uvs
	var colors: PackedColorArray = b.colors
	var indices: PackedInt32Array = b.indices
	var has_uv: bool = b.has_uv and uvs.size() == verts.size()
	var has_col: bool = b.has_color and colors.size() == verts.size()

	# Don't crush tiny emissive/sign/transparent geometry; keep smaller cell there.
	var mat: StandardMaterial3D = b.mat
	var local_cell := cell
	if mat.emission_enabled or mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		local_cell = minf(cell * 0.35, 0.06)
	elif mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		local_cell = minf(cell * 0.5, 0.12)

	var inv := 1.0 / maxf(local_cell, 0.001)
	var cell_map := {}  # Vector3i -> int new_idx
	var acc_v: Array[Vector3] = []
	var acc_n: Array[Vector3] = []
	var acc_uv: Array[Vector2] = []
	var acc_c: Array[Color] = []
	var acc_cnt: Array[int] = []
	var remap := PackedInt32Array()
	remap.resize(verts.size())

	for i in verts.size():
		var v := verts[i]
		var n := normals[i] if i < normals.size() else Vector3.UP
		# Quantize normal octant too so hard edges don't fold across 90-degree corners.
		var nx := 1 if n.x > 0.45 else (-1 if n.x < -0.45 else 0)
		var ny := 1 if n.y > 0.45 else (-1 if n.y < -0.45 else 0)
		var nz := 1 if n.z > 0.45 else (-1 if n.z < -0.45 else 0)
		var key := "%d,%d,%d|%d,%d,%d" % [floori(v.x * inv), floori(v.y * inv), floori(v.z * inv), nx, ny, nz]
		var cid: int
		if cell_map.has(key):
			cid = cell_map[key]
			acc_v[cid] += v
			acc_n[cid] += n
			if has_uv:
				acc_uv[cid] += uvs[i]
			if has_col:
				acc_c[cid] += colors[i]
			acc_cnt[cid] += 1
		else:
			cid = acc_v.size()
			cell_map[key] = cid
			acc_v.append(v)
			acc_n.append(n)
			if has_uv:
				acc_uv.append(uvs[i])
			if has_col:
				acc_c.append(colors[i])
			acc_cnt.append(1)
		remap[i] = cid

	var new_indices := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var i0 := remap[indices[t]]
		var i1 := remap[indices[t + 1]]
		var i2 := remap[indices[t + 2]]
		if i0 == i1 or i1 == i2 or i2 == i0:
			continue
		new_indices.append(i0)
		new_indices.append(i1)
		new_indices.append(i2)

	if new_indices.is_empty():
		return {}

	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_uv := PackedVector2Array()
	var out_c := PackedColorArray()
	out_v.resize(acc_v.size())
	out_n.resize(acc_n.size())
	if has_uv:
		out_uv.resize(acc_uv.size())
	if has_col:
		out_c.resize(acc_c.size())
	for i in acc_v.size():
		var inv_c := 1.0 / float(acc_cnt[i])
		out_v[i] = acc_v[i] * inv_c
		var nn := acc_n[i]
		out_n[i] = nn.normalized() if nn.length_squared() > 0.0001 else Vector3.UP
		if has_uv:
			out_uv[i] = acc_uv[i] * inv_c
		if has_col:
			out_c[i] = acc_c[i] * inv_c

	return {
		"mat": b.mat,
		"tag": b.tag,
		"verts": out_v,
		"normals": out_n,
		"uvs": out_uv,
		"colors": out_c,
		"indices": new_indices,
		"has_uv": has_uv,
		"has_color": has_col,
	}


func _collect_node_recursive(node: Node, root: Node3D, root_inv: Transform3D, buckets: Dictionary, stats: Dictionary, merge_solid_colors: bool) -> void:
	if node is Node3D and not (node as Node3D).visible:
		stats.skipped_hidden += 1
		return
	# Skip dynamic puddle areas (their geometry starts hidden and grows dynamically in rain).
	if node.is_in_group("puddles"):
		return
	# Skip NavigationRegion3D / CollisionShape3D / Area3D subtrees unless they hold static props.
	if node is Area3D or node is CollisionShape3D or node is CollisionPolygon3D:
		return

	if node is CSGShape3D:
		# Only bake root CSG shapes; child CSGs are already combined into their parent CSGShape3D.
		if not (node.get_parent() is CSGShape3D):
			var csg := node as CSGShape3D
			var baked := csg.bake_static_mesh()
			if baked != null and baked.get_surface_count() > 0:
				var xf := root_inv * csg.global_transform
				var override_mat: Material = csg.material_override
				if override_mat == null and csg is CSGPrimitive3D:
					override_mat = (csg as CSGPrimitive3D).material
				_append_mesh(baked, xf, override_mat, null, Color.WHITE, buckets, merge_solid_colors)
				stats.csg_baked += 1
		# Still traverse non-CSG children (e.g. a MeshInstance3D or Label3D parented to a CSGBox3D).
		for child in node.get_children():
			if not (child is CSGShape3D):
				_collect_node_recursive(child, root, root_inv, buckets, stats, merge_solid_colors)
		return

	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var xf := root_inv * mi.global_transform
			_append_mesh(mi.mesh, xf, mi.material_override, mi, Color.WHITE, buckets, merge_solid_colors)
			stats.mi_baked += 1
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm != null and mm.mesh != null:
			var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			var base_xf := root_inv * mmi.global_transform
			var buf := mm.buffer
			var stride := (12 if mm.transform_format == MultiMesh.TRANSFORM_3D else 8) \
					+ (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
			var use_buf := mm.transform_format == MultiMesh.TRANSFORM_3D and buf.size() >= count * stride
			for i in count:
				var inst_xf: Transform3D
				var inst_col := Color.WHITE
				if use_buf:
					var o := i * stride
					var b := Basis(
						Vector3(buf[o + 0], buf[o + 4], buf[o + 8]),
						Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
						Vector3(buf[o + 2], buf[o + 6], buf[o + 10])
					)
					var org := Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
					inst_xf = base_xf * Transform3D(b, org)
					if mm.use_colors:
						inst_col = Color(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15])
				else:
					inst_xf = base_xf * mm.get_instance_transform(i)
					if mm.use_colors:
						inst_col = mm.get_instance_color(i)
				_append_mesh(mm.mesh, inst_xf, mmi.material_override, null, inst_col, buckets, merge_solid_colors)
			stats.mm_baked += count
	elif node is Label3D:
		var lbl := node as Label3D
		var parent := lbl.get_parent()
		# Hide redundant DECON floating label (DeconShower hides it at runtime).
		if not (parent and parent.is_in_group("decon_shower")) and not lbl.text.strip_edges().is_empty():
			_append_label3d_as_strokes(lbl, root_inv, buckets, merge_solid_colors)
			stats.labels_baked += 1

	for child in node.get_children():
		_collect_node_recursive(child, root, root_inv, buckets, stats, merge_solid_colors)


func _append_label3d_as_strokes(label: Label3D, root_inv: Transform3D, buckets: Dictionary, merge_solid_colors: bool) -> void:
	var neon_script: Variant = load("res://props/neon_lettering.gd")
	if neon_script == null:
		return
	var height := label.font_size * label.pixel_size * 0.62
	if height <= 0.001:
		return
	var lit := not label.shaded
	var text := label.text.replace("•", ".").replace("/", "-").replace("&", "N")
	var built: Node3D = neon_script.call("build", text, height, label.modulate, false, false)
	if built == null:
		return
	var xf := root_inv * label.global_transform
	# Match condensed sign font aspect ratio (BarlowCondensed / VT323 are narrower than NeonLettering's 4x6 grid).
	var aspect := Transform3D(Basis.from_scale(Vector3(0.76, 0.96, 1.0)), Vector3.ZERO)
	for child in built.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh != null:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = label.modulate
			mat.roughness = 0.85
			if lit:
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if label.double_sided:
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_append_mesh(mi.mesh, xf * aspect * mi.transform, mat, null, Color.WHITE, buckets, merge_solid_colors)
	built.free()


func _append_mesh(mesh: Mesh, xf: Transform3D, override_mat: Material, mi_for_surface_overrides: MeshInstance3D, instance_color: Color, buckets: Dictionary, merge_solid_colors: bool) -> void:
	var surf_count := mesh.get_surface_count()
	var flipped := xf.basis.determinant() < 0.0
	var normal_basis := xf.basis.inverse().transposed()

	for s in surf_count:
		var raw_mat: Material = override_mat
		if raw_mat == null and mi_for_surface_overrides != null:
			raw_mat = mi_for_surface_overrides.get_surface_override_material(s)
		if raw_mat == null:
			raw_mat = mesh.surface_get_material(s)

		var arrays := mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue

		var normals_var: Variant = arrays[Mesh.ARRAY_NORMAL]
		var normals: PackedVector3Array = normals_var if normals_var != null else PackedVector3Array()
		var uvs_var: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var uvs: PackedVector2Array = uvs_var if uvs_var != null else PackedVector2Array()
		var cols_var: Variant = arrays[Mesh.ARRAY_COLOR]
		var cols: PackedColorArray = cols_var if cols_var != null else PackedColorArray()
		var idx_var: Variant = arrays[Mesh.ARRAY_INDEX]
		var indices: PackedInt32Array = idx_var if idx_var != null else PackedInt32Array()

		var has_src_col := cols.size() == verts.size()
		var has_inst_col := instance_color != Color.WHITE
		var baked := _convert_material(raw_mat, has_src_col or has_inst_col, merge_solid_colors)
		var mat: StandardMaterial3D = baked.mat
		var uv_mode: String = baked.uv_mode  # "keep" | "triplanar_world" | "triplanar_local" | "tide_xz" | "uv_xform"
		var uv_scale: Vector3 = baked.uv_scale
		var uv_offset: Vector3 = baked.uv_offset
		var bucket_key: String = baked.key
		var bake_color: Color = baked.bake_vertex_color  # WHITE unless folding solid colors into vertex colors

		if not buckets.has(bucket_key):
			buckets[bucket_key] = {
				"mat": mat,
				"tag": baked.tag,
				"verts": PackedVector3Array(),
				"normals": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"colors": PackedColorArray(),
				"indices": PackedInt32Array(),
				"has_uv": mat.albedo_texture != null,
				"has_color": mat.vertex_color_use_as_albedo,
			}
		var b: Dictionary = buckets[bucket_key]
		var out_v: PackedVector3Array = b.verts
		var out_n: PackedVector3Array = b.normals
		var out_uv: PackedVector2Array = b.uvs
		var out_c: PackedColorArray = b.colors
		var out_i: PackedInt32Array = b.indices
		var want_uv: bool = b.has_uv
		var want_col: bool = b.has_color

		# Build flat triangle index list
		var tri_idx := indices
		if tri_idx.is_empty():
			tri_idx = PackedInt32Array()
			tri_idx.resize(verts.size())
			for i in verts.size():
				tri_idx[i] = i

		if uv_mode == "triplanar_world" or uv_mode == "triplanar_local":
			# Emit per-triangle vertices so each face gets crisp dominant-axis planar UVs
			# without seam bleeding across 90-degree corners.
			var base := out_v.size()
			var tri_verts := tri_idx.size()
			out_v.resize(base + tri_verts)
			out_n.resize(base + tri_verts)
			if want_uv:
				out_uv.resize(base + tri_verts)
			if want_col:
				out_c.resize(base + tri_verts)
			var ibase := out_i.size()
			out_i.resize(ibase + tri_verts)

			for t in range(0, tri_verts - 2, 3):
				var i0 := tri_idx[t]
				var i1 := tri_idx[t + (2 if flipped else 1)]
				var i2 := tri_idx[t + (1 if flipped else 2)]
				var v0 := xf * verts[i0]
				var v1 := xf * verts[i1]
				var v2 := xf * verts[i2]
				var fn := (v2 - v0).cross(v1 - v0)
				if fn.length_squared() > 1e-12:
					fn = fn.normalized()
				else:
					fn = Vector3.UP
				var ax := absf(fn.x)
				var ay := absf(fn.y)
				var az := absf(fn.z)
				var axis := 1  # Y dominant
				if ax >= ay and ax >= az:
					axis = 0
				elif az >= ay and az >= ax:
					axis = 2

				var src_ids := [i0, i1, i2]
				var world_pts := [v0, v1, v2]
				for k in 3:
					var si: int = src_ids[k]
					var wp: Vector3 = world_pts[k]
					var dst := base + t + k
					out_v[dst] = wp
					if normals.size() == verts.size():
						var wn := (normal_basis * normals[si])
						out_n[dst] = wn.normalized() if wn.length_squared() > 1e-12 else fn
					else:
						out_n[dst] = fn
					if want_uv:
						var sp := wp if uv_mode == "triplanar_world" else verts[si]
						var p := Vector3(
							sp.x * uv_scale.x + uv_offset.x,
							-(sp.y * uv_scale.y + uv_offset.y),
							sp.z * uv_scale.z + uv_offset.z
						)
						if axis == 0:
							out_uv[dst] = Vector2(p.z, p.y)
						elif axis == 1:
							out_uv[dst] = Vector2(p.x, p.z)
						else:
							out_uv[dst] = Vector2(p.x, p.y)
					if want_col:
						var c := bake_color * instance_color
						if has_src_col:
							c *= cols[si]
						out_c[dst] = c
					out_i[ibase + t + k] = dst
		else:
			var base := out_v.size()
			var vc := verts.size()
			out_v.resize(base + vc)
			out_n.resize(base + vc)
			if want_uv:
				out_uv.resize(base + vc)
			if want_col:
				out_c.resize(base + vc)
			for i in vc:
				var wp := xf * verts[i]
				out_v[base + i] = wp
				if normals.size() == vc:
					var wn := normal_basis * normals[i]
					out_n[base + i] = wn.normalized() if wn.length_squared() > 1e-12 else Vector3.UP
				else:
					out_n[base + i] = Vector3.UP
				if want_uv:
					if uv_mode == "tide_xz":
						out_uv[base + i] = Vector2(wp.x * 0.086, wp.z * 0.105)
					elif uvs.size() == vc:
						var u := uvs[i]
						if uv_mode == "uv_xform":
							u = Vector2(u.x * uv_scale.x + uv_offset.x, u.y * uv_scale.y + uv_offset.y)
						out_uv[base + i] = u
					else:
						out_uv[base + i] = Vector2.ZERO
				if want_col:
					var c := bake_color * instance_color
					if has_src_col:
						c *= cols[i]
					out_c[base + i] = c
			var ibase := out_i.size()
			out_i.resize(ibase + tri_idx.size())
			if flipped:
				for t in range(0, tri_idx.size() - 2, 3):
					out_i[ibase + t] = base + tri_idx[t]
					out_i[ibase + t + 1] = base + tri_idx[t + 2]
					out_i[ibase + t + 2] = base + tri_idx[t + 1]
			else:
				for t in tri_idx.size():
					out_i[ibase + t] = base + tri_idx[t]

		b.verts = out_v
		b.normals = out_n
		b.uvs = out_uv
		b.colors = out_c
		b.indices = out_i


func _convert_material(raw_mat: Material, mesh_has_color: bool, merge_solid_colors: bool) -> Dictionary:
	var mat := StandardMaterial3D.new()
	var uv_mode := "keep"
	var uv_scale := Vector3.ONE
	var uv_offset := Vector3.ZERO
	var tex_key := "none"
	var tag := "solid"
	var bake_vertex_color := Color.WHITE

	if raw_mat is ShaderMaterial:
		var sm := raw_mat as ShaderMaterial
		var sp := sm.shader.resource_path if sm.shader else ""
		var code := sm.shader.code if sm.shader else ""
		if sp.ends_with(TIDE_SHADER_SUFFIX) or code.contains("ripple_pattern"):
			mat.albedo_color = Color.WHITE
			mat.albedo_texture = _get_baked_tide_texture(sm.get_shader_parameter("ripple_pattern"))
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.roughness = 0.72
			mat.metallic_specular = 0.28
			uv_mode = "tide_xz"
			tex_key = "baked_harbor_tide"
			tag = "harbor_tide"
		elif code.contains("mist_color"):
			var mc: Variant = sm.get_shader_parameter("mist_color")
			var mist_col: Color = mc if mc is Color else Color(0.38, 0.52, 0.62, 0.19)
			mat.albedo_color = Color.WHITE
			mat.albedo_texture = _get_baked_mist_texture(mist_col)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			tex_key = "baked_mist_" + mist_col.to_html(true)
			tag = "mist"
		else:
			# Generic fallback for any other ShaderMaterial
			var ac: Variant = sm.get_shader_parameter("albedo_color")
			if ac is Color:
				mat.albedo_color = ac
			var at: Variant = sm.get_shader_parameter("albedo_texture")
			if at is Texture2D:
				mat.albedo_texture = _exportable_texture(at)
				tex_key = _texture_id(at)
			tag = "shader"
	elif raw_mat is BaseMaterial3D:
		var src := raw_mat as BaseMaterial3D
		mat.albedo_color = src.albedo_color
		mat.roughness = src.roughness
		mat.metallic = src.metallic
		mat.metallic_specular = src.metallic_specular
		mat.shading_mode = src.shading_mode
		mat.transparency = src.transparency
		mat.alpha_scissor_threshold = src.alpha_scissor_threshold
		mat.cull_mode = src.cull_mode
		mat.blend_mode = src.blend_mode
		mat.depth_draw_mode = src.depth_draw_mode
		mat.disable_fog = src.disable_fog
		mat.no_depth_test = src.no_depth_test
		mat.vertex_color_use_as_albedo = src.vertex_color_use_as_albedo or mesh_has_color
		mat.vertex_color_is_srgb = src.vertex_color_is_srgb
		if src.emission_enabled and src.emission != Color.BLACK and src.emission_energy_multiplier > 0.0:
			mat.emission_enabled = true
			# Work around Godot 4.7.2 GLTFDocument bug that applies linear_to_srgb() instead of
			# srgb_to_linear() to emission when writing glTF 2.0 emissiveFactor. Pre-applying
			# srgb_to_linear() twice causes GLTFDocument to emit true linear glTF emissiveFactor.
			mat.emission = src.emission.srgb_to_linear().srgb_to_linear()
			mat.emission_energy_multiplier = src.emission_energy_multiplier
		if src.albedo_texture != null:
			mat.albedo_texture = _exportable_texture(src.albedo_texture)
			mat.texture_filter = src.texture_filter
			mat.texture_repeat = src.texture_repeat
			tex_key = _texture_id(src.albedo_texture)
			tag = src.albedo_texture.resource_path.get_file().get_basename()
			if tag.is_empty():
				tag = "tex"
			if src.uv1_triplanar:
				uv_mode = "triplanar_world" if src.uv1_world_triplanar else "triplanar_local"
				uv_scale = src.uv1_scale
				uv_offset = src.uv1_offset
				mat.texture_repeat = true
			elif src.uv1_scale != Vector3.ONE or src.uv1_offset != Vector3.ZERO:
				uv_mode = "uv_xform"
				uv_scale = src.uv1_scale
				uv_offset = src.uv1_offset
		else:
			tag = "solid_" + src.albedo_color.to_html(false)
			if mat.emission_enabled:
				tag = "emissive_" + src.emission.to_html(false)
	else:
		mat.albedo_color = Color(0.8, 0.8, 0.8)
		mat.roughness = 0.85

	if mesh_has_color:
		mat.vertex_color_use_as_albedo = true

	# Optional solid-color folding into vertex colors (reduces draw calls drastically on SGX 544MP).
	# Only fold untextured opaque non-emissive materials with matching roughness/metallic/cull/shading.
	if merge_solid_colors and mat.albedo_texture == null \
			and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and not mat.emission_enabled:
		bake_vertex_color = mat.albedo_color
		mat.albedo_color = Color.WHITE
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		tag = "vcol_unshaded" if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED else "vcol_lit"

	var key := _canonical_mat_key(mat, tex_key)
	# Baked-triplanar surfaces keep a "tri_" material name: the car client
	# skips PS1 vertex snapping on them, like the original's triplanar path
	# (snapping ground/road layers made them z-fight).
	if uv_mode.begins_with("triplanar"):
		mat.resource_name = "tri_" + tag
		key += "|tri"
	return {
		"mat": mat,
		"key": key,
		"tag": tag,
		"uv_mode": uv_mode,
		"uv_scale": uv_scale,
		"uv_offset": uv_offset,
		"bake_vertex_color": bake_vertex_color,
	}


func _canonical_mat_key(m: StandardMaterial3D, tex_key: String) -> String:
	var r_bucket := int(round(m.roughness * 20.0))
	var met_bucket := int(round(m.metallic * 20.0))
	var em_key := "%s:%.2f" % [m.emission.to_html(false), m.emission_energy_multiplier] if m.emission_enabled else "0"
	return "%s|%s|r%d|m%d|e%s|s%d|t%d|c%d|vc%d|tf%d|tr%d" % [
		tex_key,
		m.albedo_color.to_html(true),
		r_bucket,
		met_bucket,
		em_key,
		m.shading_mode,
		m.transparency,
		m.cull_mode,
		1 if m.vertex_color_use_as_albedo else 0,
		m.texture_filter,
		1 if m.texture_repeat else 0,
	]


func _texture_id(tex: Texture2D) -> String:
	if not tex.resource_path.is_empty():
		return tex.resource_path
	return "mem_%d" % tex.get_instance_id()


func _exportable_texture(tex: Texture2D) -> Texture2D:
	var id := _texture_id(tex)
	if _texture_cache.has(id):
		return _texture_cache[id]
	var img := tex.get_image()
	if img != null:
		var copy := img.duplicate() as Image
		if copy.is_compressed():
			copy.decompress()
		var itex := ImageTexture.create_from_image(copy)
		if not tex.resource_path.is_empty():
			itex.resource_name = tex.resource_path.get_file().get_basename()
		_texture_cache[id] = itex
		return itex
	_texture_cache[id] = tex
	return tex


func _get_baked_tide_texture(ripple_param: Variant) -> ImageTexture:
	if _tide_texture != null:
		return _tide_texture
	var src_tex: Texture2D = ripple_param as Texture2D
	if src_tex == null:
		src_tex = load("res://assets/textures/harbor_tide.png") as Texture2D
	var img: Image = null
	if src_tex != null:
		img = src_tex.get_image()
	if img == null:
		img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.3, 0.5, 0.6))
	else:
		img = img.duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	# Match tide.gdshader in linear light space (source_color -> linear ALBEDO -> sRGB PNG):
	# ALBEDO = mix(vec3(0.09, 0.20, 0.26), texture_color * vec3(0.48, 0.69, 0.75), 0.61);
	var base_lin := Color(0.09, 0.20, 0.26, 1.0)
	var tint_lin := Color(0.48, 0.69, 0.75, 1.0)
	for y in img.get_height():
		for x in img.get_width():
			var c_lin := img.get_pixel(x, y).srgb_to_linear()
			var tinted_lin := Color(c_lin.r * tint_lin.r, c_lin.g * tint_lin.g, c_lin.b * tint_lin.b, 1.0)
			var out_srgb := base_lin.lerp(tinted_lin, 0.61).linear_to_srgb()
			out_srgb.a = 1.0
			img.set_pixel(x, y, out_srgb)
	_tide_texture = ImageTexture.create_from_image(img)
	_tide_texture.resource_name = "harbor_tide_baked"
	return _tide_texture


func _get_baked_mist_texture(mist_col: Color) -> ImageTexture:
	var key := mist_col.to_html(true)
	if _mist_textures.has(key):
		return _mist_textures[key]
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			# smoothstep(1.0, 0.15, r)
			var t := clampf((r - 1.0) / (0.15 - 1.0), 0.0, 1.0)
			var soft := t * t * (3.0 - 2.0 * t)
			var a := mist_col.a * soft * soft
			img.set_pixel(x, y, Color(mist_col.r, mist_col.g, mist_col.b, a))
	var tex := ImageTexture.create_from_image(img)
	tex.resource_name = "mist_radial"
	_mist_textures[key] = tex
	return tex


func _build_array_mesh_from_bucket(b: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.verts
	arrays[Mesh.ARRAY_NORMAL] = b.normals
	if b.has_uv and (b.uvs as PackedVector2Array).size() == (b.verts as PackedVector3Array).size():
		arrays[Mesh.ARRAY_TEX_UV] = b.uvs
	if b.has_color and (b.colors as PackedColorArray).size() == (b.verts as PackedVector3Array).size():
		arrays[Mesh.ARRAY_COLOR] = b.colors
	arrays[Mesh.ARRAY_INDEX] = b.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, b.mat)
	return mesh


func _safe_bucket_name(idx: int, tag: String) -> String:
	var clean := ""
	for ch in tag:
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_":
			clean += ch
		else:
			clean += "_"
	return "Mat_%03d_%s" % [idx, clean.substr(0, 28)]


## Clean a standalone articulated character/weapon/prop hierarchy for glTF export:
## preserves all named Node3D pivots, converts PrimitiveMesh/CSG to ArrayMesh,
## ensures exportable textures, and strips scripts/collision/lights if requested.
func sanitize_node_for_gltf(root: Node3D, strip_lights := true) -> Dictionary:
	var total_tris := 0
	var draw_calls := 0
	_sanitize_recursive(root, root, strip_lights)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			draw_calls += 1
			var arr := m.surface_get_arrays(s)
			if arr.is_empty():
				continue
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			if idx != null and not (idx as PackedInt32Array).is_empty():
				total_tris += int((idx as PackedInt32Array).size() / 3)
			elif arr[Mesh.ARRAY_VERTEX] != null:
				total_tris += int((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
	return {"triangles": total_tris, "draw_calls": draw_calls}


func _sanitize_recursive(node: Node, root: Node3D, strip_lights: bool) -> void:
	if node != root:
		node.owner = root
	# Strip scripts so glTF export never hits custom node scripts
	if node.get_script() != null:
		node.set_script(null)
	var children := node.get_children()
	for child in children:
		if child is CollisionShape3D or child is CollisionPolygon3D or child is Area3D \
				or child is NavigationRegion3D or child is NavigationAgent3D or child is AudioStreamPlayer3D:
			node.remove_child(child)
			child.free()
			continue
		if strip_lights and child is Light3D:
			node.remove_child(child)
			child.free()
			continue
		if child is StaticBody3D:
			# Replace StaticBody3D with a plain Node3D keeping name, transform, and visual children.
			var sb := child as StaticBody3D
			var repl := Node3D.new()
			repl.name = sb.name
			repl.transform = sb.transform
			repl.visible = sb.visible
			node.add_child(repl)
			repl.owner = root
			for sub in sb.get_children():
				sb.remove_child(sub)
				repl.add_child(sub)
			node.remove_child(sb)
			sb.free()
			_sanitize_recursive(repl, root, strip_lights)
			continue
		if child is Label3D:
			var lbl := child as Label3D
			if not lbl.visible or lbl.text.strip_edges().is_empty():
				node.remove_child(lbl)
				lbl.free()
				continue
			# Convert Label3D stencil on props (vending station / airdrop) to flat stroke mesh!
			var neon_script: Variant = load("res://props/neon_lettering.gd")
			if neon_script != null:
				var h := lbl.font_size * lbl.pixel_size * 0.62
				var clean_text := lbl.text.replace("•", ".").replace("/", "-").replace("&", "N")
				var strokes: Node3D = neon_script.call("build", clean_text, h, lbl.modulate, false, false)
				if strokes != null:
					strokes.name = lbl.name + "_Text"
					strokes.transform = lbl.transform
					node.add_child(strokes)
					strokes.owner = root
					_sanitize_recursive(strokes, root, strip_lights)
			node.remove_child(lbl)
			lbl.free()
			continue
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				_unpack_vertex_color_surfaces(mi)
				_ensure_exportable_mesh_materials(mi)
		_sanitize_recursive(child, root, strip_lights)


## Unpack any untextured vertex-colored surface (such as MeshMerge output on
## infected/pickups/airdrop) into explicit per-color StandardMaterial3D surfaces
## with no ARRAY_COLOR. This avoids glTF COLOR_0 import/gamma differences across
## Godot 4 and Godot 3.6 GLES2.
func _unpack_vertex_color_surfaces(mi: MeshInstance3D) -> void:
	var src_mesh := mi.mesh
	if src_mesh == null:
		return
	var needs_unpack := false
	for s in src_mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			if bm.vertex_color_use_as_albedo and bm.albedo_texture == null:
				var arr := src_mesh.surface_get_arrays(s)
				if not arr.is_empty() and arr[Mesh.ARRAY_COLOR] != null and not (arr[Mesh.ARRAY_COLOR] as PackedColorArray).is_empty():
					needs_unpack = true
					break
	if not needs_unpack:
		return

	var new_mesh := ArrayMesh.new()
	for s in src_mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		var arr := src_mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var bm := mat as BaseMaterial3D
		var cols_var: Variant = arr[Mesh.ARRAY_COLOR]
		if bm != null and bm.vertex_color_use_as_albedo and bm.albedo_texture == null \
				and cols_var != null and not (cols_var as PackedColorArray).is_empty():
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var normals_var: Variant = arr[Mesh.ARRAY_NORMAL]
			var normals: PackedVector3Array = normals_var if normals_var != null else PackedVector3Array()
			var cols: PackedColorArray = cols_var
			var idx_var: Variant = arr[Mesh.ARRAY_INDEX]
			var indices: PackedInt32Array = idx_var if idx_var != null else PackedInt32Array()
			if indices.is_empty():
				indices = PackedInt32Array()
				indices.resize(verts.size())
				for i in verts.size():
					indices[i] = i
			# Group triangles by quantized vertex color
			var by_col := {}
			for t in range(0, indices.size() - 2, 3):
				var i0 := indices[t]
				var i1 := indices[t + 1]
				var i2 := indices[t + 2]
				var c := cols[i0] * bm.albedo_color
				var ckey := c.to_html(true)
				if not by_col.has(ckey):
					by_col[ckey] = {"color": c, "verts": PackedVector3Array(), "normals": PackedVector3Array(), "indices": PackedInt32Array()}
				var g: Dictionary = by_col[ckey]
				var gv: PackedVector3Array = g.verts
				var gn: PackedVector3Array = g.normals
				var gi: PackedInt32Array = g.indices
				var base := gv.size()
				for k in [i0, i1, i2]:
					gv.append(verts[k])
					gn.append(normals[k] if k < normals.size() else Vector3.UP)
				gi.append(base)
				gi.append(base + 1)
				gi.append(base + 2)
				g.verts = gv
				g.normals = gn
				g.indices = gi
			for ckey in by_col:
				var g: Dictionary = by_col[ckey]
				var out_arr := []
				out_arr.resize(Mesh.ARRAY_MAX)
				out_arr[Mesh.ARRAY_VERTEX] = g.verts
				out_arr[Mesh.ARRAY_NORMAL] = g.normals
				out_arr[Mesh.ARRAY_INDEX] = g.indices
				var smat := _clean_std_mat(bm)
				smat.vertex_color_use_as_albedo = false
				smat.vertex_color_is_srgb = false
				smat.albedo_color = g.color
				if smat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
					smat.emission_enabled = true
					smat.emission = g.color.srgb_to_linear().srgb_to_linear()
					smat.emission_energy_multiplier = 1.0
				new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arr)
				new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, smat)
		else:
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			if mat != null:
				new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, mat)

	mi.material_override = null
	for s in src_mesh.get_surface_count():
		mi.set_surface_override_material(s, null)
	mi.mesh = new_mesh


func _ensure_exportable_mesh_materials(mi: MeshInstance3D) -> void:
	if mi.material_override is BaseMaterial3D:
		mi.material_override = _clean_std_mat(mi.material_override as BaseMaterial3D)
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var ov := mi.get_surface_override_material(s)
		if ov is BaseMaterial3D:
			mi.set_surface_override_material(s, _clean_std_mat(ov as BaseMaterial3D))
		else:
			var sm := mi.mesh.surface_get_material(s)
			if sm is BaseMaterial3D and (sm as BaseMaterial3D).albedo_texture != null:
				mi.set_surface_override_material(s, _clean_std_mat(sm as BaseMaterial3D))


func _clean_std_mat(src: BaseMaterial3D) -> StandardMaterial3D:
	var m := src.duplicate() as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = src.albedo_color
		m.roughness = src.roughness
		m.metallic = src.metallic
		m.shading_mode = src.shading_mode
		m.transparency = src.transparency
		m.cull_mode = src.cull_mode
		m.emission_enabled = src.emission_enabled
		m.emission = src.emission
		m.emission_energy_multiplier = src.emission_energy_multiplier
	if m.emission_enabled and m.emission != Color.BLACK and m.emission_energy_multiplier > 0.0:
		m.emission = src.emission.srgb_to_linear().srgb_to_linear()
	if m.albedo_texture != null:
		m.albedo_texture = _exportable_texture(m.albedo_texture)
	return m


## Write a Node3D scene tree to a `.glb` file on disk using Godot's GLTFDocument.
func write_glb(scene_root: Node3D, out_path: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(scene_root, state)
	if err != OK:
		return {"ok": false, "error": "append_from_scene failed (%d)" % err}
	err = doc.write_to_filesystem(state, out_path)
	if err != OK:
		return {"ok": false, "error": "write_to_filesystem failed (%d)" % err}
	var f := FileAccess.open(out_path, FileAccess.READ)
	var bytes := f.get_length() if f else 0
	if f:
		f.close()
	return {"ok": true, "bytes": bytes}


static func vec3_arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func color_hex(c: Color, with_alpha := false) -> String:
	return "#" + c.to_html(with_alpha)


static func write_json(path: String, data: Variant) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open JSON for write: " + path)
		return false
	f.store_string(JSON.stringify(data, "\t", false) + "\n")
	f.close()
	return true
