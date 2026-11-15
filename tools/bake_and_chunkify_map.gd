@tool
class_name BakeAndChunkifyMap
extends EditorScript
## Editor and headless utility that bakes and chunkifies a monolithic level
## scene into 250x250m [ChunkRoot] scenes, binary geo resources, and a shell.

## Source level scene path to bake and chunkify.
const SOURCE_SCENE_PATH: String = "res://levels/testbed.tscn"

## Output shell scene path hosting environment, streaming, player, and globals.
const SHELL_SCENE_PATH: String = "res://levels/testbed_chunk.tscn"

## Output directory for generated chunk scenes.
const CHUNK_DIR: String = "res://levels/chunks/testbed/"

## Output directory for generated binary mesh and collision resources.
const GEO_DIR: String = "res://levels/chunks/testbed/geo/"

## Format string for generated chunk scene file paths.
const CHUNK_PATH_FMT: String = "res://levels/chunks/testbed/chunk_%d_%d.scn"

## Format string for generated chunk mesh resource paths.
const MESH_PATH_FMT: String = "res://levels/chunks/testbed/geo/chunk_%d_%d_mesh.res"

## Format string for generated chunk collision resource paths.
const COL_PATH_FMT: String = "res://levels/chunks/testbed/geo/chunk_%d_%d_col.res"

## World-space width and depth of a single streaming chunk in meters.
const CHUNK_SIZE: float = 250.0

## Polling interval in seconds for the [ChunkManager] I/O timer.
const IO_POLL_INTERVAL: float = 0.05

## Polling interval in seconds for the [PlayerChunkTracker] boundary timer.
const TRACKER_POLL_INTERVAL: float = 0.2

## Preloaded [ChunkRoot] script attached to every generated chunk root node.
const CHUNK_ROOT_SCRIPT: GDScript = preload("res://world/chunk_root.gd")

## Preloaded [ChunkManager] script attached to the shell streaming manager.
const CHUNK_MANAGER_SCRIPT: GDScript = preload("res://world/chunk_manager.gd")

## Preloaded [PlayerChunkTracker] script attached to the player node.
const TRACKER_SCRIPT: GDScript = preload("res://world/player_chunk_tracker.gd")

## Top-level node names routed into the shell Environment container.
const ENV_NODE_NAMES: Array[String] = [
	"WorldEnvironment",
	"SunshineCloudsDriverGD",
	"ArgonLightningController",
]

## Top-level node names routed into the shell GameplayGlobal container.
const GLOBAL_NODE_NAMES: Array[String] = [
	"LightSequence",
	"Triggers",
	"HideBuildingsGroup",
	"CCTVLocation1",
	"CCTVLocation2",
	"TVScreen",
	"ragdoll_destination",
]


## Entry point executed via File -> Run in the Godot Editor.
func _run() -> void:
	var ei: Object = Engine.get_singleton(&"EditorInterface")
	if ei == null:
		push_error("BakeAndChunkifyMap: EditorInterface singleton unavailable.")
		return
	var base_ctrl: Control = ei.call(&"get_base_control") as Control
	if base_ctrl == null:
		return
	await run_bake(base_ctrl.get_tree())


## Static entry point callable from both [EditorScript] and headless [SceneTree].
static func run_bake(tree: SceneTree) -> Error:
	var baker: MapBaker = MapBaker.new()
	return await baker.bake_testbed(tree)


## Internal [RefCounted] worker performing the bake without instantiating [EditorScript].
class MapBaker:
	extends RefCounted

	## Bakes [constant SOURCE_SCENE_PATH] into chunks and [constant SHELL_SCENE_PATH].
	func bake_testbed(tree: SceneTree) -> Error:
		if not ResourceLoader.exists(SOURCE_SCENE_PATH):
			push_error("BakeAndChunkifyMap: Missing source scene ", SOURCE_SCENE_PATH)
			return ERR_FILE_NOT_FOUND

		DirAccess.make_dir_recursive_absolute(CHUNK_DIR)
		DirAccess.make_dir_recursive_absolute(GEO_DIR)

		var packed_src: PackedScene = ResourceLoader.load(SOURCE_SCENE_PATH) as PackedScene
		if packed_src == null:
			push_error("BakeAndChunkifyMap: Failed to load ", SOURCE_SCENE_PATH)
			return ERR_CANT_OPEN

		var source_root: Node = packed_src.instantiate()
		if not (source_root is Node3D):
			source_root.free()
			push_error("BakeAndChunkifyMap: Source root is not Node3D.")
			return ERR_INVALID_DATA

		var src_3d: Node3D = source_root as Node3D
		var shell_root: Node3D = _create_shell_root(src_3d.name)
		var env_dir: Node3D = shell_root.get_node("Environment") as Node3D
		var global_dir: Node3D = shell_root.get_node("GameplayGlobal") as Node3D

		var plain_csgs: Array[Dictionary] = []
		var special_csgs: Array[Dictionary] = []
		var chunk_nodes: Dictionary[Vector2i, Array] = {}

		_route_top_level_nodes(
			src_3d, shell_root, env_dir, global_dir, plain_csgs, special_csgs, chunk_nodes
		)

		var chunk_surfaces: Dictionary[Vector2i, Dictionary] = {}
		var chunk_faces: Dictionary[Vector2i, PackedVector3Array] = {}
		var temp_hosts: Array[Node] = []

		await _bake_plain_csgs(plain_csgs, tree, chunk_surfaces, chunk_faces, temp_hosts)
		await _bake_special_csgs(special_csgs, tree, chunk_nodes, temp_hosts)

		var all_coords: Dictionary[Vector2i, bool] = {}
		for coord: Vector2i in chunk_surfaces.keys():
			all_coords[coord] = true
		for coord: Vector2i in chunk_faces.keys():
			all_coords[coord] = true
		for coord: Vector2i in chunk_nodes.keys():
			all_coords[coord] = true

		var chunk_roots: Array[Node3D] = []
		for coord: Vector2i in all_coords.keys():
			var built_chunk: Node3D = _save_chunk_scene(
				coord, chunk_surfaces, chunk_faces, chunk_nodes
			)
			chunk_roots.append(built_chunk)

		_sanitize_external_node_refs(shell_root, shell_root)
		var shell_err: Error = _save_packed_scene(shell_root, SHELL_SCENE_PATH)
		for built_chunk: Node3D in chunk_roots:
			built_chunk.free()
		shell_root.free()
		for host_node: Node in temp_hosts:
			host_node.free()
		src_3d.free()
		print("BakeAndChunkifyMap: Baked ", all_coords.size(), " chunks to ", CHUNK_DIR)
		return shell_err

	## Creates the organized shell hierarchy with Environment, Streaming, and GameplayGlobal.
	func _create_shell_root(root_name: String) -> Node3D:
		var shell: Node3D = Node3D.new()
		shell.name = root_name

		var env_node: Node3D = Node3D.new()
		env_node.name = "Environment"
		shell.add_child(env_node)
		env_node.owner = shell

		var streaming_node: Node3D = Node3D.new()
		streaming_node.name = "Streaming"
		shell.add_child(streaming_node)
		streaming_node.owner = shell

		var dyn_container: Node3D = Node3D.new()
		dyn_container.name = "DynamicContainer"
		streaming_node.add_child(dyn_container)
		dyn_container.owner = shell

		var raw_mgr: Variant = CHUNK_MANAGER_SCRIPT.new()
		var chunk_mgr: Node3D = raw_mgr if raw_mgr is Node3D else null
		assert(chunk_mgr != null, "BakeAndChunkifyMap: Failed to instantiate ChunkManager.")
		chunk_mgr.name = "ChunkManager"
		streaming_node.add_child(chunk_mgr)
		chunk_mgr.owner = shell
		chunk_mgr.set(&"chunk_dir", CHUNK_DIR)
		chunk_mgr.set(&"dynamic_container", dyn_container)

		var io_timer: Timer = Timer.new()
		io_timer.name = "IOTimer"
		io_timer.wait_time = IO_POLL_INTERVAL
		io_timer.one_shot = false
		chunk_mgr.add_child(io_timer)
		io_timer.owner = shell

		var global_node: Node3D = Node3D.new()
		global_node.name = "GameplayGlobal"
		shell.add_child(global_node)
		global_node.owner = shell

		return shell

	## Routes top-level children of [param src_root] into shell containers or chunk buckets.
	func _route_top_level_nodes(
		src_root: Node3D,
		shell_root: Node3D,
		env_dir: Node3D,
		global_dir: Node3D,
		plain_csgs: Array[Dictionary],
		special_csgs: Array[Dictionary],
		chunk_nodes: Dictionary[Vector2i, Array]
	) -> void:
		var children: Array[Node] = src_root.get_children()
		for child: Node in children:
			if child.name == &"Player":
				_move_node(child, shell_root, src_root, shell_root)
				_ensure_player_tracker(child, shell_root)
			elif String(child.name) in ENV_NODE_NAMES:
				_move_node(child, env_dir, src_root, shell_root)
			elif String(child.name) in GLOBAL_NODE_NAMES or not (child is Node3D):
				_move_node(child, global_dir, src_root, shell_root)
			else:
				_collect_spatial_node(
					child, Transform3D.IDENTITY, src_root, plain_csgs, special_csgs, chunk_nodes
				)

	## Ensures [param player] has a [PlayerChunkTracker] and [Timer] child owned by [param owner_root].
	func _ensure_player_tracker(player: Node, owner_root: Node) -> void:
		var existing: Node = player.get_node_or_null("PlayerChunkTracker")
		if existing != null:
			return
		var raw_tracker: Variant = TRACKER_SCRIPT.new()
		var tracker: Node3D = raw_tracker if raw_tracker is Node3D else null
		assert(tracker != null, "BakeAndChunkifyMap: Failed to instantiate PlayerChunkTracker.")
		tracker.name = "PlayerChunkTracker"
		player.add_child(tracker)
		tracker.owner = owner_root

		var poll_timer: Timer = Timer.new()
		poll_timer.name = "PollTimer"
		poll_timer.wait_time = TRACKER_POLL_INTERVAL
		poll_timer.one_shot = false
		poll_timer.autostart = true
		tracker.add_child(poll_timer)
		poll_timer.owner = owner_root

	## Recursively classifies [param node] into plain CSG, special CSG, or chunked Node3D.
	func _collect_spatial_node(
		node: Node,
		parent_xform: Transform3D,
		src_root: Node,
		plain_csgs: Array[Dictionary],
		special_csgs: Array[Dictionary],
		chunk_nodes: Dictionary[Vector2i, Array]
	) -> void:
		if not (node is Node3D):
			return
		var node_3d: Node3D = node as Node3D
		var world_xform: Transform3D = parent_xform * node_3d.transform

		if node_3d is CSGShape3D:
			var csg: CSGShape3D = node_3d as CSGShape3D
			if _is_special_csg(csg):
				special_csgs.append({"node": csg, "xform": world_xform})
			else:
				_extract_nested_specials(csg, world_xform, src_root, special_csgs, chunk_nodes)
				plain_csgs.append({"node": csg, "xform": world_xform})
			return

		if _is_plain_folder(node_3d):
			var folder_children: Array[Node] = node_3d.get_children()
			for child: Node in folder_children:
				_collect_spatial_node(
					child, world_xform, src_root, plain_csgs, special_csgs, chunk_nodes
				)
			return

		var coord: Vector2i = _world_to_chunk(world_xform.origin)
		if not chunk_nodes.has(coord):
			var empty_list: Array = []
			chunk_nodes[coord] = empty_list
		var list: Array = chunk_nodes[coord]
		list.append({"node": node_3d, "xform": world_xform, "src_root": src_root})

	## Extracts grouped, scripted, or non-CSG descendants from inside a plain CSG tree.
	func _extract_nested_specials(
		csg_parent: CSGShape3D,
		parent_xform: Transform3D,
		src_root: Node,
		special_csgs: Array[Dictionary],
		chunk_nodes: Dictionary[Vector2i, Array]
	) -> void:
		var children: Array[Node] = csg_parent.get_children()
		for child: Node in children:
			if not (child is Node3D):
				continue
			var child_3d: Node3D = child as Node3D
			var child_xform: Transform3D = parent_xform * child_3d.transform
			if child_3d is CSGShape3D:
				var child_csg: CSGShape3D = child_3d as CSGShape3D
				if _is_special_csg(child_csg):
					csg_parent.remove_child(child_csg)
					special_csgs.append({"node": child_csg, "xform": child_xform})
				else:
					_extract_nested_specials(
						child_csg, child_xform, src_root, special_csgs, chunk_nodes
					)
			else:
				csg_parent.remove_child(child_3d)
				var coord: Vector2i = _world_to_chunk(child_xform.origin)
				if not chunk_nodes.has(coord):
					var empty_list: Array = []
					chunk_nodes[coord] = empty_list
				var list: Array = chunk_nodes[coord]
				list.append({"node": child_3d, "xform": child_xform, "src_root": src_root})

	## Returns true if [param csg] has a custom script or non-internal gameplay groups.
	func _is_special_csg(csg: CSGShape3D) -> bool:
		if csg.get_script() != null:
			return true
		return _has_gameplay_groups(csg)

	## Returns true if [param node] is a bare organizational Node3D folder.
	func _is_plain_folder(node: Node3D) -> bool:
		if node.get_class() != "Node3D":
			return false
		if node.get_script() != null or node.scene_file_path != "":
			return false
		return not _has_gameplay_groups(node)

	## Returns true if [param node] belongs to any non-internal group.
	func _has_gameplay_groups(node: Node) -> bool:
		var groups: Array[StringName] = node.get_groups()
		for grp: StringName in groups:
			if not String(grp).begins_with("_"):
				return true
		return false

	## Bakes plain CSG nodes in [param tree] and splits triangles into chunk surface buckets.
	func _bake_plain_csgs(
		plain_csgs: Array[Dictionary],
		tree: SceneTree,
		chunk_surfaces: Dictionary[Vector2i, Dictionary],
		chunk_faces: Dictionary[Vector2i, PackedVector3Array],
		temp_hosts: Array[Node]
	) -> void:
		if plain_csgs.is_empty():
			return

		var host: Node3D = Node3D.new()
		host.name = "TempCSGBakeHost"
		tree.root.add_child(host)
		temp_hosts.append(host)

		for entry: Dictionary in plain_csgs:
			var raw_csg: Variant = entry["node"]
			var csg: CSGShape3D = raw_csg if raw_csg is CSGShape3D else null
			if csg == null:
				continue
			_clear_owners_recursive(csg)
			if csg.get_parent() != null:
				csg.get_parent().remove_child(csg)
			csg.transform = Transform3D.IDENTITY
			host.add_child(csg)

		await tree.process_frame
		await tree.process_frame

		for entry: Dictionary in plain_csgs:
			var raw_csg: Variant = entry["node"]
			var csg: CSGShape3D = raw_csg if raw_csg is CSGShape3D else null
			var raw_xform: Variant = entry["xform"]
			var xform: Transform3D = raw_xform if raw_xform is Transform3D else Transform3D.IDENTITY
			if csg == null:
				continue
			var baked: ArrayMesh = csg.bake_static_mesh()
			if baked != null:
				_split_mesh_into_chunks(
					baked, xform, csg.use_collision, chunk_surfaces, chunk_faces
				)

	## Splits [param baked] triangles by centroid into 250m chunks and merges by Material.
	func _split_mesh_into_chunks(
		baked: ArrayMesh,
		world_xform: Transform3D,
		use_col: bool,
		chunk_surfaces: Dictionary[Vector2i, Dictionary],
		chunk_faces: Dictionary[Vector2i, PackedVector3Array]
	) -> void:
		var normal_basis: Basis = world_xform.basis.inverse().transposed()
		var surface_count: int = baked.get_surface_count()

		for s_idx: int in range(surface_count):
			var mat: Material = baked.surface_get_material(s_idx)
			var arrays: Array = baked.surface_get_arrays(s_idx)
			if arrays.is_empty():
				continue

			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue

			var raw_norms: Variant = arrays[Mesh.ARRAY_NORMAL]
			var norms: PackedVector3Array = (
				raw_norms if raw_norms is PackedVector3Array else PackedVector3Array()
			)
			var raw_uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
			var uvs: PackedVector2Array = (
				raw_uvs if raw_uvs is PackedVector2Array else PackedVector2Array()
			)
			var raw_uv2s: Variant = arrays[Mesh.ARRAY_TEX_UV2]
			var uv2s: PackedVector2Array = (
				raw_uv2s if raw_uv2s is PackedVector2Array else PackedVector2Array()
			)
			var raw_colors: Variant = arrays[Mesh.ARRAY_COLOR]
			var colors: PackedColorArray = (
				raw_colors if raw_colors is PackedColorArray else PackedColorArray()
			)
			var raw_tangents: Variant = arrays[Mesh.ARRAY_TANGENT]
			var tangents: PackedFloat32Array = (
				raw_tangents if raw_tangents is PackedFloat32Array else PackedFloat32Array()
			)
			var raw_indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var indices: PackedInt32Array = (
				raw_indices if raw_indices is PackedInt32Array else PackedInt32Array()
			)

			var tri_count: int = verts.size() / 3 if indices.is_empty() else indices.size() / 3
			for t_idx: int in range(tri_count):
				var base: int = t_idx * 3
				var i0: int = base if indices.is_empty() else indices[base]
				var i1: int = base + 1 if indices.is_empty() else indices[base + 1]
				var i2: int = base + 2 if indices.is_empty() else indices[base + 2]

				var p0: Vector3 = world_xform * verts[i0]
				var p1: Vector3 = world_xform * verts[i1]
				var p2: Vector3 = world_xform * verts[i2]
				var centroid: Vector3 = (p0 + p1 + p2) / 3.0
				var coord: Vector2i = _world_to_chunk(centroid)
				var origin: Vector3 = _chunk_origin(coord)

				var st: SurfaceTool = _get_surface_tool(chunk_surfaces, coord, mat)
				_append_vertex(
					st, p0 - origin, i0, norms, uvs, uv2s, colors, tangents, normal_basis
				)
				_append_vertex(
					st, p1 - origin, i1, norms, uvs, uv2s, colors, tangents, normal_basis
				)
				_append_vertex(
					st, p2 - origin, i2, norms, uvs, uv2s, colors, tangents, normal_basis
				)

				if use_col:
					if not chunk_faces.has(coord):
						chunk_faces[coord] = PackedVector3Array()
					var faces: PackedVector3Array = chunk_faces[coord]
					faces.append(p0 - origin)
					faces.append(p1 - origin)
					faces.append(p2 - origin)
					chunk_faces[coord] = faces

	## Returns or creates a [SurfaceTool] for ([param coord], [param mat]) in [param buckets].
	func _get_surface_tool(
		buckets: Dictionary[Vector2i, Dictionary], coord: Vector2i, mat: Material
	) -> SurfaceTool:
		if not buckets.has(coord):
			var mat_map: Dictionary = {}
			buckets[coord] = mat_map
		var coord_map: Dictionary = buckets[coord]
		var mat_key: Variant = mat
		if not coord_map.has(mat_key):
			var st: SurfaceTool = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			if mat != null:
				st.set_material(mat)
			coord_map[mat_key] = st
		var raw_st: Variant = coord_map[mat_key]
		return raw_st if raw_st is SurfaceTool else null

	## Appends one transformed vertex and its attributes to [param st].
	func _append_vertex(
		st: SurfaceTool,
		local_pos: Vector3,
		idx: int,
		norms: PackedVector3Array,
		uvs: PackedVector2Array,
		uv2s: PackedVector2Array,
		colors: PackedColorArray,
		tangents: PackedFloat32Array,
		normal_basis: Basis
	) -> void:
		if idx < norms.size():
			st.set_normal((normal_basis * norms[idx]).normalized())
		if idx < uvs.size():
			st.set_uv(uvs[idx])
		if idx < uv2s.size():
			st.set_uv2(uv2s[idx])
		if idx < colors.size():
			st.set_color(colors[idx])
		var t_off: int = idx * 4
		if t_off + 3 < tangents.size():
			var t_vec: Vector3 = Vector3(tangents[t_off], tangents[t_off + 1], tangents[t_off + 2])
			var world_t: Vector3 = (normal_basis * t_vec).normalized()
			st.set_tangent(Plane(world_t, tangents[t_off + 3]))
		st.add_vertex(local_pos)

	## Bakes grouped or scripted CSGs into standalone StaticBody3D + MeshInstance3D nodes.
	func _bake_special_csgs(
		special_csgs: Array[Dictionary],
		tree: SceneTree,
		chunk_nodes: Dictionary[Vector2i, Array],
		temp_hosts: Array[Node]
	) -> void:
		if special_csgs.is_empty():
			return

		var host: Node3D = Node3D.new()
		host.name = "TempSpecialCSGHost"
		tree.root.add_child(host)
		temp_hosts.append(host)

		for entry: Dictionary in special_csgs:
			var raw_csg: Variant = entry["node"]
			var csg: CSGShape3D = raw_csg if raw_csg is CSGShape3D else null
			if csg == null:
				continue
			_clear_owners_recursive(csg)
			if csg.get_parent() != null:
				csg.get_parent().remove_child(csg)
			csg.transform = Transform3D.IDENTITY
			host.add_child(csg)

		await tree.process_frame
		await tree.process_frame

		for entry: Dictionary in special_csgs:
			var raw_csg: Variant = entry["node"]
			var csg: CSGShape3D = raw_csg if raw_csg is CSGShape3D else null
			var raw_xform: Variant = entry["xform"]
			var xform: Transform3D = raw_xform if raw_xform is Transform3D else Transform3D.IDENTITY
			if csg == null:
				continue
			var baked_mesh: ArrayMesh = csg.bake_static_mesh()
			var baked_col: Shape3D = csg.bake_collision_shape()

			var body: StaticBody3D = StaticBody3D.new()
			body.name = csg.name
			body.collision_layer = csg.collision_layer
			body.collision_mask = csg.collision_mask
			for grp: StringName in csg.get_groups():
				if not String(grp).begins_with("_"):
					body.add_to_group(grp, true)

			if baked_mesh != null:
				var mesh_inst: MeshInstance3D = MeshInstance3D.new()
				mesh_inst.name = "MeshInstance3D"
				mesh_inst.layers = csg.layers
				mesh_inst.mesh = baked_mesh
				body.add_child(mesh_inst)

			if baked_col != null:
				var col_shape: CollisionShape3D = CollisionShape3D.new()
				col_shape.name = "CollisionShape3D"
				col_shape.shape = baked_col
				body.add_child(col_shape)

			var coord: Vector2i = _world_to_chunk(xform.origin)
			if not chunk_nodes.has(coord):
				var empty_list: Array = []
				chunk_nodes[coord] = empty_list
			var list: Array = chunk_nodes[coord]
			list.append({"node": body, "xform": xform, "src_root": null})

	## Builds, saves geo resources, and packs a single 250m [ChunkRoot] scene at [param coord].
	func _save_chunk_scene(
		coord: Vector2i,
		chunk_surfaces: Dictionary[Vector2i, Dictionary],
		chunk_faces: Dictionary[Vector2i, PackedVector3Array],
		chunk_nodes: Dictionary[Vector2i, Array]
	) -> Node3D:
		var chunk_root: Node3D = Node3D.new()
		chunk_root.name = "Chunk_%d_%d" % [coord.x, coord.y]
		chunk_root.set_script(CHUNK_ROOT_SCRIPT)
		var origin: Vector3 = _chunk_origin(coord)

		if chunk_surfaces.has(coord):
			var coord_map: Dictionary = chunk_surfaces[coord]
			var array_mesh: ArrayMesh = ArrayMesh.new()
			for mat_key: Variant in coord_map.keys():
				var raw_st: Variant = coord_map[mat_key]
				if raw_st is SurfaceTool:
					var st: SurfaceTool = raw_st
					st.commit(array_mesh)
			if array_mesh.get_surface_count() > 0:
				var mesh_path: String = MESH_PATH_FMT % [coord.x, coord.y]
				ResourceSaver.save(array_mesh, mesh_path)
				var saved_mesh: Mesh = ResourceLoader.load(mesh_path) as Mesh
				var env_mesh: MeshInstance3D = MeshInstance3D.new()
				env_mesh.name = "EnvironmentMesh"
				env_mesh.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
				env_mesh.mesh = saved_mesh
				chunk_root.add_child(env_mesh)
				env_mesh.owner = chunk_root

		if chunk_faces.has(coord):
			var faces: PackedVector3Array = chunk_faces[coord]
			if not faces.is_empty():
				var col_shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
				col_shape.set_faces(faces)
				var col_path: String = COL_PATH_FMT % [coord.x, coord.y]
				ResourceSaver.save(col_shape, col_path)
				var saved_col: Shape3D = ResourceLoader.load(col_path) as Shape3D

				var env_body: StaticBody3D = StaticBody3D.new()
				env_body.name = "EnvironmentCollision"
				env_body.collision_layer = CollisionLayers.layer_to_mask(
					CollisionLayers.LAYER_ENVIRONMENT_IDX
				)
				env_body.collision_mask = CollisionLayers.MASK_NONE
				chunk_root.add_child(env_body)
				env_body.owner = chunk_root

				var col_node: CollisionShape3D = CollisionShape3D.new()
				col_node.name = "CollisionShape3D"
				col_node.shape = saved_col
				env_body.add_child(col_node)
				col_node.owner = chunk_root

		if chunk_nodes.has(coord):
			var list: Array = chunk_nodes[coord]
			for entry_var: Variant in list:
				if not (entry_var is Dictionary):
					continue
				var entry: Dictionary = entry_var
				var raw_node: Variant = entry["node"]
				var node_3d: Node3D = raw_node if raw_node is Node3D else null
				var raw_xform: Variant = entry["xform"]
				var xform: Transform3D = (
					raw_xform if raw_xform is Transform3D else Transform3D.IDENTITY
				)
				var raw_src: Variant = entry["src_root"]
				var src_root: Node = raw_src if raw_src is Node else null
				if node_3d == null:
					continue
				_move_node(node_3d, chunk_root, src_root, chunk_root)
				node_3d.transform = Transform3D(xform.basis, xform.origin - origin)

		var chunk_path: String = CHUNK_PATH_FMT % [coord.x, coord.y]
		print("BakeAndChunkifyMap: Saving ", chunk_path)
		_sanitize_external_node_refs(chunk_root, chunk_root)
		_save_packed_scene(chunk_root, chunk_path)
		return chunk_root

	## Recursively clears [member Node.owner] on [param node] and all descendants.
	func _clear_owners_recursive(node: Node) -> void:
		node.owner = null
		var children: Array[Node] = node.get_children()
		for child: Node in children:
			_clear_owners_recursive(child)

	## Nullifies stored [Node] properties pointing outside [param root] before packing.
	func _sanitize_external_node_refs(root: Node, current: Node) -> void:
		if current != root and not current.scene_file_path.is_empty():
			_strip_subscene_persistent_signals(current)

		var props: Array[Dictionary] = current.get_property_list()
		for prop: Dictionary in props:
			var raw_usage: Variant = prop.get("usage", 0)
			var usage: int = raw_usage if raw_usage is int else 0
			if (usage & PROPERTY_USAGE_STORAGE) == 0:
				continue
			var raw_name: Variant = prop.get("name", "")
			var prop_name: String = raw_name if raw_name is String else ""
			if prop_name.is_empty():
				continue
			var raw_type: Variant = prop.get("type", TYPE_NIL)
			var prop_type: int = raw_type if raw_type is int else TYPE_NIL
			if prop_type == TYPE_OBJECT:
				var val: Variant = current.get(prop_name)
				if val is Node:
					var target_node: Node = val
					if target_node != root and not root.is_ancestor_of(target_node):
						current.set(prop_name, null)
			elif prop_type == TYPE_ARRAY:
				var arr_val: Variant = current.get(prop_name)
				if arr_val is Array:
					var arr: Array = arr_val
					var has_external: bool = false
					for item: Variant in arr:
						if item is Node:
							var item_node: Node = item
							if item_node != root and not root.is_ancestor_of(item_node):
								has_external = true
								break
					if has_external:
						var filtered: Array = []
						for item: Variant in arr:
							if item is Node:
								var item_node: Node = item
								if item_node == root or root.is_ancestor_of(item_node):
									filtered.append(item_node)
							else:
								filtered.append(item)
						current.set(prop_name, filtered)

		var children: Array[Node] = current.get_children()
		for child: Node in children:
			_sanitize_external_node_refs(root, child)

	## Disconnects persistent internal signal connections on instanced sub-scene roots.
	func _strip_subscene_persistent_signals(sub_root: Node) -> void:
		var signals: Array[Dictionary] = sub_root.get_signal_list()
		for sig_dict: Dictionary in signals:
			var raw_sig: Variant = sig_dict.get("name", "")
			var sig_str: String = ""
			if raw_sig is String:
				sig_str = raw_sig
			elif raw_sig is StringName:
				var sn: StringName = raw_sig
				sig_str = String(sn)
			if sig_str.is_empty():
				continue
			var sig_name: StringName = StringName(sig_str)
			var conns: Array[Dictionary] = sub_root.get_signal_connection_list(sig_name)
			for conn: Dictionary in conns:
				var raw_flags: Variant = conn.get("flags", 0)
				var flags: int = raw_flags if raw_flags is int else 0
				if (flags & Object.CONNECT_PERSIST) == 0:
					continue
				var raw_cb: Variant = conn.get("callable", Callable())
				if not (raw_cb is Callable):
					continue
				var cb: Callable = raw_cb
				var target: Object = cb.get_object()
				if target is Node:
					var target_node: Node = target
					if target_node == sub_root or target_node.owner == sub_root:
						sub_root.disconnect(sig_name, cb)

	## Reparents [param node] to [param new_parent] and sets owner to [param new_root].
	func _move_node(node: Node, new_parent: Node, old_root: Node, new_root: Node) -> void:
		var owned_nodes: Array[Node] = []
		_collect_owned_nodes(node, old_root, owned_nodes)
		for owned: Node in owned_nodes:
			owned.owner = null
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		new_parent.add_child(node)
		for owned: Node in owned_nodes:
			owned.owner = new_root

	## Collects [param node] and descendants owned by [param old_root] without entering sub-scenes.
	func _collect_owned_nodes(node: Node, old_root: Node, out: Array[Node]) -> void:
		if old_root == null or node.owner == old_root:
			out.append(node)
		var children: Array[Node] = node.get_children()
		for child: Node in children:
			if old_root != null and child.owner != old_root:
				continue
			_collect_owned_nodes(child, old_root, out)

	## Packs [param root] into a [PackedScene] and saves it to [param path].
	func _save_packed_scene(root: Node, path: String) -> Error:
		var packed: PackedScene = PackedScene.new()
		var pack_err: Error = packed.pack(root)
		if pack_err != OK:
			push_error("BakeAndChunkifyMap: Failed to pack ", path, " err=", pack_err)
			return pack_err
		var save_err: Error = ResourceSaver.save(packed, path)
		if save_err != OK:
			push_error("BakeAndChunkifyMap: Failed to save ", path, " err=", save_err)
		return save_err

	## Converts a world-space position into 250m chunk grid coordinates.
	func _world_to_chunk(world_pos: Vector3) -> Vector2i:
		return Vector2i(floori(world_pos.x / CHUNK_SIZE), floori(world_pos.z / CHUNK_SIZE))

	## Returns the world-space origin of chunk [param coord].
	func _chunk_origin(coord: Vector2i) -> Vector3:
		return Vector3(float(coord.x) * CHUNK_SIZE, 0.0, float(coord.y) * CHUNK_SIZE)
