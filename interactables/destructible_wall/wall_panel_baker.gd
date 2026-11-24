@tool
## Editor and headless baker converting fractured wall GLBs into [WallPanelData] resources.
class_name WallPanelBaker
extends Node3D

## Node name prefix identifying structurally anchored wall chunks.
const ANCHOR_PREFIX: String = "anchor_chunk_"

## Node name prefix identifying destructible non-anchor wall chunks.
const CHUNK_PREFIX: String = "chunk_"

## Node name identifying the internal reinforcement steel mesh.
const REBAR_NAME: String = "rebar"

## Surface material name mapped to outer concrete surface index 0.
const OUTER_MAT_NAME: String = "concrete_outer"

## Surface material name mapped to inner concrete surface index 1.
const INNER_MAT_NAME: String = "concrete_inner"

## AABB inflation margin in meters used to broad-phase candidate adjacent chunks.
const AABB_GROW_MARGIN: float = 0.01

## Squared distance threshold (0.005 m)^2 matching shared face vertices.
const SHARED_VERT_DIST_SQ: float = 0.000025

## Squared distance threshold used to deduplicate split-normal corner vertices.
const UNIQUE_VERT_DIST_SQ: float = 1e-10

## Minimum shared triangle area in square meters rejecting edge/corner-only touches.
const MIN_SHARED_TRI_AREA: float = 1e-5

## Child node name used for the editor adjacency debug wireframe mesh.
const DEBUG_NODE_NAME: StringName = &"AdjacencyDebugMesh"

## Base directory containing wall panel model assets.
const MODELS_DIR: String = "res://interactables/destructible_wall/models/"

## Default source GLB path for the 2x3 meter destructible concrete wall panel.
const DEFAULT_GLB_PATH: String = MODELS_DIR + "wall_panel_2x3.glb"

## Default destination resource path for the baked wall panel data.
const DEFAULT_OUT_PATH: String = MODELS_DIR + "wall_panel_2x3_data.tres"

## Path to the fractured wall GLB scene to bake.
@export_file("*.glb", "*.gltf") var source_glb_path: String = DEFAULT_GLB_PATH

## Destination `.tres` path where the baked [WallPanelData] resource is saved.
@export var output_data_path: String = DEFAULT_OUT_PATH

## Baked [WallPanelData] resource previewed or produced by this baker node.
@export var baked_data: WallPanelData = null:
	set(value):
		baked_data = value
		if is_instance_valid(self) and is_inside_tree() and show_adjacency_debug:
			_rebuild_adjacency_debug()

## Inspector button trigger executing [method bake_from_glb] inside the editor.
@export var bake_now: bool = false:
	set(value):
		bake_now = false
		if not value:
			return
		if not Engine.is_editor_hint():
			return
		if not is_instance_valid(self) or not is_inside_tree():
			return
		baked_data = bake_from_glb(source_glb_path, output_data_path)
		if show_adjacency_debug:
			_rebuild_adjacency_debug()

## Toggles editor wireframe rendering of chunk centroids and adjacency edges.
@export var show_adjacency_debug: bool = false:
	set(value):
		show_adjacency_debug = value
		if not is_instance_valid(self) or not is_inside_tree():
			return
		_rebuild_adjacency_debug()

## Cached debug mesh instance displaying chunk adjacency in the editor.
var _debug_mesh_inst: MeshInstance3D = null

## Cached immediate mesh backing [member _debug_mesh_inst].
var _debug_immediate: ImmediateMesh = null


## Disables per-frame callbacks and refreshes editor adjacency debug view if enabled.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if not is_inside_tree():
		return
	if Engine.is_editor_hint() and show_adjacency_debug:
		_rebuild_adjacency_debug()


## Bakes [param glb_path] into a [WallPanelData] resource and saves it to [param out_path].
static func bake_from_glb(glb_path: String, out_path: String) -> WallPanelData:
	if not ResourceLoader.exists(glb_path):
		push_error("WallPanelBaker: GLB not found at ", glb_path)
		return null

	var packed: PackedScene = ResourceLoader.load(glb_path) as PackedScene
	if packed == null:
		push_error("WallPanelBaker: Failed to load PackedScene from ", glb_path)
		return null

	var root: Node = packed.instantiate()
	if root == null:
		push_error("WallPanelBaker: Failed to instantiate scene from ", glb_path)
		return null

	var chunks: Array[ChunkBuildData] = []
	var rebar_holder: RebarBuildData = RebarBuildData.new()
	_collect_mesh_nodes(root, Transform3D.IDENTITY, chunks, rebar_holder)

	if chunks.is_empty():
		root.free()
		push_error("WallPanelBaker: No chunk meshes found in ", glb_path)
		return null
	if chunks.size() > WallPanelData.MAX_CHUNKS:
		var found_count: int = chunks.size()
		root.free()
		push_error(
			"WallPanelBaker: Chunk count ",
			found_count,
			" exceeds MAX_CHUNKS (",
			WallPanelData.MAX_CHUNKS,
			")"
		)
		return null

	chunks.sort_custom(_compare_chunks)

	var data: WallPanelData = _build_panel_data(chunks, rebar_holder)
	root.free()

	if data == null or not data.is_valid():
		push_error("WallPanelBaker: Built invalid WallPanelData from ", glb_path)
		return null

	if not out_path.is_empty():
		var dir_err: Error = DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			push_error("WallPanelBaker: Could not create output dir for ", out_path)
			return null
		var save_err: Error = ResourceSaver.save(data, out_path)
		if save_err != OK:
			push_error("WallPanelBaker: Failed saving ", out_path, " error=", save_err)
			return null

	_print_bake_summary(data, out_path)
	return data


## Recursively traverses [param node] to collect chunk meshes and the rebar mesh.
static func _collect_mesh_nodes(
	node: Node,
	parent_xform: Transform3D,
	chunks: Array[ChunkBuildData],
	rebar_holder: RebarBuildData
) -> void:
	var current_xform: Transform3D = parent_xform
	if node is Node3D and node.get_parent() != null:
		current_xform = parent_xform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		var node_name: String = String(mesh_inst.name)
		if mesh_inst.mesh != null:
			if node_name == REBAR_NAME:
				rebar_holder.mesh = mesh_inst.mesh
				rebar_holder.xform = current_xform
			elif node_name.begins_with(ANCHOR_PREFIX) or node_name.begins_with(CHUNK_PREFIX):
				var entry: ChunkBuildData = ChunkBuildData.new()
				entry.chunk_name = node_name
				entry.is_anchor = node_name.begins_with(ANCHOR_PREFIX)
				entry.mesh = mesh_inst.mesh
				entry.xform = current_xform
				chunks.append(entry)

	for child: Node in node.get_children():
		_collect_mesh_nodes(child, current_xform, chunks, rebar_holder)


## Deterministic lexicographical comparator for sorting chunks by node name.
static func _compare_chunks(a: ChunkBuildData, b: ChunkBuildData) -> bool:
	return a.chunk_name < b.chunk_name


## Builds all geometry, collision shapes, centroids, volumes, and adjacency into [WallPanelData].
static func _build_panel_data(
	chunks: Array[ChunkBuildData], rebar_holder: RebarBuildData
) -> WallPanelData:
	var count: int = chunks.size()
	var data: WallPanelData = WallPanelData.new()
	data.chunk_count = count

	var names: PackedStringArray = PackedStringArray()
	var centroids: PackedVector3Array = PackedVector3Array()
	var volumes: PackedFloat32Array = PackedFloat32Array()
	var shapes: Array[ConvexPolygonShape3D] = []
	var meshes: Array[ArrayMesh] = []

	var outer_st: SurfaceTool = SurfaceTool.new()
	outer_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	outer_st.set_custom_format(0, SurfaceTool.CUSTOM_R_FLOAT)

	var inner_st: SurfaceTool = SurfaceTool.new()
	inner_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	inner_st.set_custom_format(0, SurfaceTool.CUSTOM_R_FLOAT)

	var outer_state: SurfaceBuildState = SurfaceBuildState.new()
	var inner_state: SurfaceBuildState = SurfaceBuildState.new()
	var has_bounds: bool = false
	var full_bounds: AABB = AABB()

	for idx: int in range(count):
		var chunk: ChunkBuildData = chunks[idx]
		_analyze_chunk_geometry(chunk)
		if not has_bounds:
			full_bounds = chunk.aabb
			has_bounds = true
		else:
			full_bounds = full_bounds.merge(chunk.aabb)

		if chunk.is_anchor:
			data.anchor_mask |= WallPanelData.bit_for_chunk(idx)

		names.append(chunk.chunk_name)
		centroids.append(chunk.centroid)
		volumes.append(chunk.volume)
		shapes.append(_build_chunk_shape(chunk))
		meshes.append(_build_chunk_mesh(chunk, outer_st, inner_st, outer_state, inner_state, idx))

	var merged_mesh: ArrayMesh = ArrayMesh.new()
	_finalize_surface_tool(outer_st, outer_state, merged_mesh, OUTER_MAT_NAME)
	_finalize_surface_tool(inner_st, inner_state, merged_mesh, INNER_MAT_NAME)

	data.panel_size = full_bounds.size
	data.merged_mesh = merged_mesh
	data.chunk_names = names
	data.chunk_centroids = centroids
	data.chunk_volumes = volumes
	data.chunk_shapes = shapes
	data.chunk_meshes = meshes
	data.adjacency = _compute_adjacency(chunks)

	if rebar_holder.mesh != null:
		data.rebar_mesh = _build_rebar_mesh(rebar_holder)
		data.rebar_shape = data.rebar_mesh.create_trimesh_shape()

	return data


## Computes panel-local bounds, unique vertices, volume, and volume centroid for [param chunk].
static func _analyze_chunk_geometry(chunk: ChunkBuildData) -> void:
	var surface_count: int = chunk.mesh.get_surface_count()
	var unique_verts: PackedVector3Array = PackedVector3Array()
	var has_bounds: bool = false
	var bounds: AABB = AABB()
	var has_ref: bool = false
	var ref_pt: Vector3 = Vector3.ZERO
	var signed_vol_6: float = 0.0
	var weighted_sum: Vector3 = Vector3.ZERO
	var flip_winding: bool = chunk.xform.basis.determinant() < 0.0

	for surf_idx: int in range(surface_count):
		var arrays: Array = chunk.mesh.surface_get_arrays(surf_idx)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var raw_verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (raw_verts is PackedVector3Array):
			continue
		var verts: PackedVector3Array = raw_verts
		if verts.is_empty():
			continue
		var raw_indices: Variant = (
			arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else null
		)
		var indices: PackedInt32Array = (
			raw_indices if raw_indices is PackedInt32Array else PackedInt32Array()
		)

		for v: Vector3 in verts:
			var local_v: Vector3 = chunk.xform * v
			if not has_bounds:
				bounds = AABB(local_v, Vector3.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(local_v)
			if not has_ref:
				ref_pt = local_v
				has_ref = true
			_append_unique_vertex(unique_verts, local_v)

		var tri_count: int = verts.size() / 3 if indices.is_empty() else indices.size() / 3
		for t_idx: int in range(tri_count):
			var base: int = t_idx * 3
			var i0: int = base if indices.is_empty() else indices[base]
			var i1_raw: int = base + 1 if indices.is_empty() else indices[base + 1]
			var i2_raw: int = base + 2 if indices.is_empty() else indices[base + 2]
			var i1: int = i2_raw if flip_winding else i1_raw
			var i2: int = i1_raw if flip_winding else i2_raw

			var a: Vector3 = (chunk.xform * verts[i0]) - ref_pt
			var b: Vector3 = (chunk.xform * verts[i1]) - ref_pt
			var c: Vector3 = (chunk.xform * verts[i2]) - ref_pt
			var tet6: float = a.dot(b.cross(c))
			signed_vol_6 += tet6
			weighted_sum += (a + b + c) * (0.25 * tet6)

	chunk.aabb = bounds
	chunk.unique_verts = unique_verts

	if absf(signed_vol_6) > 1e-8:
		chunk.centroid = ref_pt + (weighted_sum / signed_vol_6)
		chunk.volume = absf(signed_vol_6) / 6.0
	elif not unique_verts.is_empty():
		var avg: Vector3 = Vector3.ZERO
		for pt: Vector3 in unique_verts:
			avg += pt
		chunk.centroid = avg / float(unique_verts.size())
		chunk.volume = 0.0


## Appends [param candidate] to [param unique_verts] if no existing vertex is within tolerance.
static func _append_unique_vertex(unique_verts: PackedVector3Array, candidate: Vector3) -> void:
	for existing: Vector3 in unique_verts:
		if existing.distance_squared_to(candidate) <= UNIQUE_VERT_DIST_SQ:
			return
	unique_verts.append(candidate)


## Creates a centroid-centered [ConvexPolygonShape3D] from [param chunk] unique vertices.
static func _build_chunk_shape(chunk: ChunkBuildData) -> ConvexPolygonShape3D:
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	var centered: PackedVector3Array = PackedVector3Array()
	centered.resize(chunk.unique_verts.size())
	for i: int in range(chunk.unique_verts.size()):
		centered[i] = chunk.unique_verts[i] - chunk.centroid
	shape.points = centered
	return shape


## Builds the centered per-chunk [ArrayMesh] while appending to merged outer/inner [SurfaceTool]s.
static func _build_chunk_mesh(
	chunk: ChunkBuildData,
	merged_outer_st: SurfaceTool,
	merged_inner_st: SurfaceTool,
	merged_outer_state: SurfaceBuildState,
	merged_inner_state: SurfaceBuildState,
	chunk_idx: int
) -> ArrayMesh:
	var chunk_mesh: ArrayMesh = ArrayMesh.new()
	var outer_surf: int = _resolve_surface_index(chunk.mesh, OUTER_MAT_NAME, 0)
	var inner_surf: int = _resolve_surface_index(chunk.mesh, INNER_MAT_NAME, 1)

	var chunk_outer_st: SurfaceTool = SurfaceTool.new()
	chunk_outer_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chunk_outer_state: SurfaceBuildState = SurfaceBuildState.new()

	var chunk_inner_st: SurfaceTool = SurfaceTool.new()
	chunk_inner_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chunk_inner_state: SurfaceBuildState = SurfaceBuildState.new()

	if outer_surf >= 0:
		_append_mesh_surface(
			chunk.mesh,
			outer_surf,
			chunk.xform,
			Vector3.ZERO,
			merged_outer_st,
			merged_outer_state,
			chunk_idx
		)
		_append_mesh_surface(
			chunk.mesh,
			outer_surf,
			chunk.xform,
			-chunk.centroid,
			chunk_outer_st,
			chunk_outer_state,
			-1
		)

	if inner_surf >= 0:
		_append_mesh_surface(
			chunk.mesh,
			inner_surf,
			chunk.xform,
			Vector3.ZERO,
			merged_inner_st,
			merged_inner_state,
			chunk_idx
		)
		_append_mesh_surface(
			chunk.mesh,
			inner_surf,
			chunk.xform,
			-chunk.centroid,
			chunk_inner_st,
			chunk_inner_state,
			-1
		)

	_finalize_surface_tool(chunk_outer_st, chunk_outer_state, chunk_mesh, OUTER_MAT_NAME)
	_finalize_surface_tool(chunk_inner_st, chunk_inner_state, chunk_mesh, INNER_MAT_NAME)
	return chunk_mesh


## Resolves a surface index by material/surface name with fallback to [param fallback_idx].
static func _resolve_surface_index(mesh: Mesh, expected_name: String, fallback_idx: int) -> int:
	var surface_count: int = mesh.get_surface_count()
	for s: int in range(surface_count):
		var mat: Material = mesh.surface_get_material(s)
		if mat != null and mat.resource_name == expected_name:
			return s
		if mesh is ArrayMesh:
			var arr_mesh: ArrayMesh = mesh as ArrayMesh
			if arr_mesh.surface_get_name(s) == expected_name:
				return s
	if fallback_idx >= 0 and fallback_idx < surface_count:
		return fallback_idx
	return -1


## Appends all triangles of surface [param surf_idx] into [param st] with optional CUSTOM0 ID.
static func _append_mesh_surface(
	src_mesh: Mesh,
	surf_idx: int,
	xform: Transform3D,
	offset: Vector3,
	st: SurfaceTool,
	state: SurfaceBuildState,
	chunk_idx: int
) -> void:
	var arrays: Array = src_mesh.surface_get_arrays(surf_idx)
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return
	var raw_verts: Variant = arrays[Mesh.ARRAY_VERTEX]
	if not (raw_verts is PackedVector3Array):
		return
	var verts: PackedVector3Array = raw_verts
	if verts.is_empty():
		return

	var raw_norms: Variant = (
		arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL else null
	)
	var norms: PackedVector3Array = (
		raw_norms if raw_norms is PackedVector3Array else PackedVector3Array()
	)
	var raw_uvs: Variant = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV else null
	var uvs: PackedVector2Array = raw_uvs if raw_uvs is PackedVector2Array else PackedVector2Array()
	var raw_tangents: Variant = (
		arrays[Mesh.ARRAY_TANGENT] if arrays.size() > Mesh.ARRAY_TANGENT else null
	)
	var tangents: PackedFloat32Array = (
		raw_tangents if raw_tangents is PackedFloat32Array else PackedFloat32Array()
	)
	var raw_indices: Variant = (
		arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else null
	)
	var indices: PackedInt32Array = (
		raw_indices if raw_indices is PackedInt32Array else PackedInt32Array()
	)

	if norms.size() != verts.size():
		state.all_have_normals = false
	if uvs.size() != verts.size():
		state.all_have_uvs = false
	if tangents.size() != verts.size() * 4:
		state.all_have_tangents = false

	var normal_basis: Basis = xform.basis.inverse().transposed()
	var flip_winding: bool = xform.basis.determinant() < 0.0
	var custom_color: Color = Color(float(chunk_idx), 0.0, 0.0, 0.0)
	var tri_count: int = verts.size() / 3 if indices.is_empty() else indices.size() / 3

	for t_idx: int in range(tri_count):
		var base: int = t_idx * 3
		var i0: int = base if indices.is_empty() else indices[base]
		var i1_raw: int = base + 1 if indices.is_empty() else indices[base + 1]
		var i2_raw: int = base + 2 if indices.is_empty() else indices[base + 2]
		var i1: int = i2_raw if flip_winding else i1_raw
		var i2: int = i1_raw if flip_winding else i2_raw

		var tri_indices: Array[int] = [i0, i1, i2]
		for v_idx: int in tri_indices:
			if v_idx < norms.size():
				st.set_normal((normal_basis * norms[v_idx]).normalized())
			if v_idx < uvs.size():
				st.set_uv(uvs[v_idx])
			var t_off: int = v_idx * 4
			if t_off + 3 < tangents.size():
				var t_vec: Vector3 = Vector3(
					tangents[t_off], tangents[t_off + 1], tangents[t_off + 2]
				)
				st.set_tangent(Plane((normal_basis * t_vec).normalized(), tangents[t_off + 3]))
			if chunk_idx >= 0:
				st.set_custom(0, custom_color)
			st.add_vertex((xform * verts[v_idx]) + offset)
		state.tri_count += 1


## Finalizes normals, tangents, indexing, and commits one surface onto [param target_mesh].
static func _finalize_surface_tool(
	st: SurfaceTool, state: SurfaceBuildState, target_mesh: ArrayMesh, surf_name: String
) -> void:
	if state.tri_count <= 0:
		return
	if not state.all_have_normals:
		st.generate_normals()
	if not state.all_have_tangents and state.all_have_uvs:
		st.generate_tangents()
	st.index()
	var surf_idx: int = target_mesh.get_surface_count()
	st.commit(target_mesh)
	target_mesh.surface_set_name(surf_idx, surf_name)


## Extracts and bakes [param rebar_holder] mesh in panel-local coordinates.
static func _build_rebar_mesh(rebar_holder: RebarBuildData) -> ArrayMesh:
	var out_mesh: ArrayMesh = ArrayMesh.new()
	var surface_count: int = rebar_holder.mesh.get_surface_count()
	for s: int in range(surface_count):
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var state: SurfaceBuildState = SurfaceBuildState.new()
		_append_mesh_surface(rebar_holder.mesh, s, rebar_holder.xform, Vector3.ZERO, st, state, -1)
		_finalize_surface_tool(st, state, out_mesh, REBAR_NAME)
	return out_mesh


## Computes symmetric, ascending-sorted adjacency lists across all [param chunks].
static func _compute_adjacency(chunks: Array[ChunkBuildData]) -> Array[PackedInt32Array]:
	var count: int = chunks.size()
	var inflated: Array[AABB] = []
	var result: Array[PackedInt32Array] = []
	inflated.resize(count)
	result.resize(count)
	for i: int in range(count):
		inflated[i] = chunks[i].aabb.grow(AABB_GROW_MARGIN)
		result[i] = PackedInt32Array()

	for i: int in range(count):
		for j: int in range(i + 1, count):
			if not inflated[i].intersects(inflated[j]):
				continue
			if _chunks_share_face(chunks[i].unique_verts, chunks[j].unique_verts):
				result[i].append(j)
				result[j].append(i)

	for i: int in range(count):
		result[i].sort()
	return result


## Returns true when [param verts_a] and [param verts_b] share a non-degenerate triangle face.
static func _chunks_share_face(verts_a: PackedVector3Array, verts_b: PackedVector3Array) -> bool:
	var shared: PackedVector3Array = PackedVector3Array()
	for va: Vector3 in verts_a:
		for vb: Vector3 in verts_b:
			if va.distance_squared_to(vb) <= SHARED_VERT_DIST_SQ:
				shared.append(va)
				break

	var shared_count: int = shared.size()
	if shared_count < 3:
		return false

	var p0: Vector3 = shared[0]
	var p1_idx: int = -1
	var max_dist_sq: float = 0.0
	for k: int in range(1, shared_count):
		var d_sq: float = p0.distance_squared_to(shared[k])
		if d_sq > max_dist_sq:
			max_dist_sq = d_sq
			p1_idx = k

	if p1_idx < 0 or max_dist_sq <= 1e-10:
		return false

	var edge: Vector3 = shared[p1_idx] - p0
	for k: int in range(1, shared_count):
		if k == p1_idx:
			continue
		var area: float = 0.5 * edge.cross(shared[k] - p0).length()
		if area > MIN_SHARED_TRI_AREA:
			return true

	if shared_count <= 32:
		for a: int in range(shared_count):
			for b: int in range(a + 1, shared_count):
				var ab: Vector3 = shared[b] - shared[a]
				for c: int in range(b + 1, shared_count):
					var tri_area: float = 0.5 * ab.cross(shared[c] - shared[a]).length()
					if tri_area > MIN_SHARED_TRI_AREA:
						return true
	return false


## Prints concise bake metrics and connectivity verification summary.
static func _print_bake_summary(data: WallPanelData, out_path: String) -> void:
	var anchor_count: int = 0
	var min_deg: int = 999999
	var max_deg: int = 0
	var min_vol: float = INF
	var max_vol: float = 0.0
	for i: int in range(data.chunk_count):
		if WallPanelData.is_chunk_set(data.anchor_mask, i):
			anchor_count += 1
		var deg: int = data.adjacency[i].size()
		min_deg = mini(min_deg, deg)
		max_deg = maxi(max_deg, deg)
		var vol: float = data.chunk_volumes[i]
		min_vol = minf(min_vol, vol)
		max_vol = maxf(max_vol, vol)
	var supported: int = data.find_supported_mask(0)
	var all_mask: int = WallPanelData.all_chunks_mask(data.chunk_count)
	print(
		(
			"WallPanelBaker: Baked %d chunks (%d anchors) -> %s | deg=[%d..%d] vol=[%.5f..%.5f] "
			% [data.chunk_count, anchor_count, out_path, min_deg, max_deg, min_vol, max_vol]
		),
		"all_supported=",
		supported == all_mask
	)


## Rebuilds the editor [ImmediateMesh] visualizing chunk centroids and adjacency links.
func _rebuild_adjacency_debug() -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return

	_ensure_debug_mesh_node()
	if not is_instance_valid(_debug_mesh_inst) or not is_instance_valid(_debug_immediate):
		return

	_debug_immediate.clear_surfaces()
	if not show_adjacency_debug or baked_data == null or not baked_data.is_valid():
		_debug_mesh_inst.visible = false
		return

	var has_lines: bool = false
	for i: int in range(baked_data.chunk_count):
		if not baked_data.adjacency[i].is_empty():
			has_lines = true
			break
		if WallPanelData.is_chunk_set(baked_data.anchor_mask, i):
			has_lines = true
			break

	if not has_lines:
		_debug_mesh_inst.visible = false
		return

	_debug_mesh_inst.visible = true
	_debug_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for i: int in range(baked_data.chunk_count):
		var c_a: Vector3 = baked_data.chunk_centroids[i]
		var a_anchor: bool = WallPanelData.is_chunk_set(baked_data.anchor_mask, i)
		if a_anchor:
			_draw_anchor_cross(c_a, Color(0.2, 1.0, 0.3))
		for nb: int in baked_data.adjacency[i]:
			if nb <= i or nb >= baked_data.chunk_count:
				continue
			var b_anchor: bool = WallPanelData.is_chunk_set(baked_data.anchor_mask, nb)
			var edge_col: Color = (
				Color(0.2, 0.9, 1.0) if (a_anchor or b_anchor) else Color(1.0, 0.75, 0.2)
			)
			_debug_immediate.surface_set_color(edge_col)
			_debug_immediate.surface_add_vertex(c_a)
			_debug_immediate.surface_set_color(edge_col)
			_debug_immediate.surface_add_vertex(baked_data.chunk_centroids[nb])
	_debug_immediate.surface_end()


## Draws a small axis cross marker at [param center] in the active [ImmediateMesh] surface.
func _draw_anchor_cross(center: Vector3, color: Color) -> void:
	var half: float = 0.04
	var offsets: Array[Vector3] = [
		Vector3(half, 0.0, 0.0),
		Vector3(0.0, half, 0.0),
		Vector3(0.0, 0.0, half),
	]
	for off: Vector3 in offsets:
		_debug_immediate.surface_set_color(color)
		_debug_immediate.surface_add_vertex(center - off)
		_debug_immediate.surface_set_color(color)
		_debug_immediate.surface_add_vertex(center + off)


## Finds or creates the transient editor [MeshInstance3D] child for adjacency debug lines.
func _ensure_debug_mesh_node() -> void:
	if is_instance_valid(_debug_mesh_inst) and is_instance_valid(_debug_immediate):
		return
	var existing: Node = get_node_or_null(NodePath(DEBUG_NODE_NAME))
	if existing is MeshInstance3D:
		_debug_mesh_inst = existing as MeshInstance3D
	else:
		_debug_mesh_inst = MeshInstance3D.new()
		_debug_mesh_inst.name = DEBUG_NODE_NAME
		_debug_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_mesh_inst)

	if _debug_mesh_inst.mesh is ImmediateMesh:
		_debug_immediate = _debug_mesh_inst.mesh as ImmediateMesh
	else:
		_debug_immediate = ImmediateMesh.new()
		_debug_mesh_inst.mesh = _debug_immediate

	if _debug_mesh_inst.material_override == null:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		_debug_mesh_inst.material_override = mat


## Internal per-chunk geometry container used during bake processing.
class ChunkBuildData:
	extends RefCounted

	## Deterministic node name of this chunk.
	var chunk_name: String = ""

	## True when this chunk belongs to the structurally anchored set.
	var is_anchor: bool = false

	## Source imported mesh for this chunk.
	var mesh: Mesh = null

	## Panel-local transform of this chunk node.
	var xform: Transform3D = Transform3D.IDENTITY

	## Computed volume-weighted centroid in panel-local coordinates.
	var centroid: Vector3 = Vector3.ZERO

	## Computed positive mesh volume in cubic meters.
	var volume: float = 0.0

	## Panel-local bounding box covering all vertices of this chunk.
	var aabb: AABB = AABB()

	## Deduplicated panel-local corner positions used for shape and adjacency math.
	var unique_verts: PackedVector3Array = PackedVector3Array()


## Internal source container for the extracted rebar mesh and transform.
class RebarBuildData:
	extends RefCounted

	## Source imported rebar mesh.
	var mesh: Mesh = null

	## Panel-local transform of the rebar node.
	var xform: Transform3D = Transform3D.IDENTITY


## Internal tracking flags for attribute completeness on a merged or chunk surface.
class SurfaceBuildState:
	extends RefCounted

	## Total triangles appended into the surface tool.
	var tri_count: int = 0

	## True while every appended source surface provides per-vertex normals.
	var all_have_normals: bool = true

	## True while every appended source surface provides primary UV coordinates.
	var all_have_uvs: bool = true

	## True while every appended source surface provides vertex tangents.
	var all_have_tangents: bool = true
