@tool
class_name OrganizeAndBakeTestbed
extends EditorScript
## Organizes a level scene tree into functional Node3D buckets, preserves
## cross-node NodePath exports, and optionally bakes CSGs / inline ArrayMeshes.

## Output directory for baked CSG and externalized inline ArrayMesh resources.
const BAKED_MESH_DIR: String = "res://levels/baked_csg/"

## Set to true to bake static CSGShape3D trees into StaticBody3D + .res meshes.
const BAKE_CSG: bool = false

## Set to true to also bake procedural @tool CSG scripts into static meshes.
const BAKE_PROCEDURAL_CSG: bool = false

## Set to true to externalize inline ArrayMesh subresources into binary .res files.
const EXTERNALIZE_INLINE_MESHES: bool = true

## Procedural CSG script paths kept live when [constant BAKE_PROCEDURAL_CSG] is false.
const PROCEDURAL_CSG_SCRIPTS: Array[String] = [
	"res://environment/procedural_fence_csg.gd",
	"res://player/procedural_spiral_stairs_csg.gd",
	"res://player/procedural_stairs_csg.gd",
]

## Standard functional bucket names created under the scene root.
const BUCKET_NAMES: Array[StringName] = [
	&"Environment",
	&"Geometry",
	&"Interactables",
	&"Triggers",
	&"Enemies",
	&"VFX",
	&"Entities",
]


## Executes scene organization and optional baking on the active editor scene.
func _run() -> void:
	var root: Node = get_scene()
	if root == null:
		push_error("OrganizeAndBakeTestbed: No active scene open in the editor.")
		return

	var stats: Dictionary[StringName, int] = organize_scene(root)
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.mark_scene_as_unsaved()

	var baked_csg: int = stats.get(&"baked_csg", 0)
	var ext_meshes: int = stats.get(&"ext_meshes", 0)
	var moved_nodes: int = stats.get(&"moved_nodes", 0)
	print(
		(
			"OrganizeAndBakeTestbed Complete! Baked CSGs: %d | Externalized Meshes: %d | Moved: %d"
			% [baked_csg, ext_meshes, moved_nodes]
		)
	)


## Organizes [param root] in-place and returns operation counts.
static func organize_scene(root: Node) -> Dictionary[StringName, int]:
	var stats: Dictionary[StringName, int] = {
		&"baked_csg": 0,
		&"ext_meshes": 0,
		&"moved_nodes": 0,
	}
	if not is_instance_valid(root):
		return stats

	if BAKE_CSG or EXTERNALIZE_INLINE_MESHES:
		var abs_dir: String = ProjectSettings.globalize_path(BAKED_MESH_DIR)
		if not DirAccess.dir_exists_absolute(abs_dir):
			var err: Error = DirAccess.make_dir_recursive_absolute(abs_dir)
			if err != OK:
				push_error("OrganizeAndBakeTestbed: Failed to create dir: " + BAKED_MESH_DIR)
				return stats

	var links: Array[Dictionary] = _capture_all_nodepath_references(root)

	if BAKE_CSG:
		stats[&"baked_csg"] = _bake_all_csg_roots(root)

	if EXTERNALIZE_INLINE_MESHES:
		stats[&"ext_meshes"] = _externalize_inline_array_meshes(root)

	var buckets: Dictionary[StringName, Node3D] = _ensure_buckets(root)
	stats[&"moved_nodes"] = _organize_root_children(root, buckets)
	_restore_all_nodepath_references(links)
	return stats


## Scans [param root] descendants and records resolved targets for all NodePath properties.
static func _capture_all_nodepath_references(root: Node) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	var all_nodes: Array[Node] = _get_all_descendants(root)
	all_nodes.push_front(root)

	for node: Node in all_nodes:
		for prop: Dictionary in node.get_property_list():
			var raw_usage: Variant = prop.get("usage", 0)
			var usage: int = raw_usage if raw_usage is int else 0
			if (usage & PROPERTY_USAGE_STORAGE) == 0:
				continue

			var raw_name: Variant = prop.get("name", &"")
			var prop_name: StringName = StringName(raw_name) if raw_name is StringName else &""
			if prop_name == &"" and raw_name is String:
				prop_name = StringName(raw_name as String)

			var raw_type: Variant = prop.get("type", TYPE_NIL)
			var prop_type: int = raw_type if raw_type is int else TYPE_NIL

			if prop_type == TYPE_NODE_PATH:
				if node is AnimationPlayer and prop_name == &"root_node":
					continue
				var raw_np: Variant = node.get(prop_name)
				if raw_np is NodePath:
					var np: NodePath = raw_np
					if not np.is_empty():
						var target: Node = node.get_node_or_null(np)
						if is_instance_valid(target):
							(
								links
								. append(
									{
										"source": node,
										"property": prop_name,
										"is_array": false,
										"target": target,
									}
								)
							)
			elif prop_type == TYPE_ARRAY:
				var raw_arr: Variant = node.get(prop_name)
				if raw_arr is Array:
					var arr: Array = raw_arr
					if not arr.is_empty() and arr[0] is NodePath:
						var targets: Array[Node] = []
						var has_valid: bool = false
						for item: Variant in arr:
							if item is NodePath:
								var item_np: NodePath = item
								if not item_np.is_empty():
									var tgt: Node = node.get_node_or_null(item_np)
									targets.append(tgt)
									if is_instance_valid(tgt):
										has_valid = true
									continue
							targets.append(null)
						if has_valid:
							(
								links
								. append(
									{
										"source": node,
										"property": prop_name,
										"is_array": true,
										"targets": targets,
									}
								)
							)
	return links


## Recomputes relative NodePath values after hierarchy reorganization.
static func _restore_all_nodepath_references(links: Array[Dictionary]) -> void:
	for entry: Dictionary in links:
		var raw_source: Variant = entry.get("source")
		var source: Node = raw_source if raw_source is Node else null
		if not is_instance_valid(source):
			continue

		var raw_prop: Variant = entry.get("property", &"")
		var prop_name: StringName = raw_prop if raw_prop is StringName else &""
		var raw_is_arr: Variant = entry.get("is_array", false)
		var is_array: bool = raw_is_arr if raw_is_arr is bool else false

		if not is_array:
			var raw_target: Variant = entry.get("target")
			var target: Node = raw_target if raw_target is Node else null
			if is_instance_valid(target):
				source.set(prop_name, source.get_path_to(target))
		else:
			var raw_targets: Variant = entry.get("targets")
			var raw_current: Variant = source.get(prop_name)
			if raw_targets is Array and raw_current is Array:
				var targets: Array = raw_targets
				var current_arr: Array = (raw_current as Array).duplicate()
				for i: int in range(mini(targets.size(), current_arr.size())):
					var raw_t: Variant = targets[i]
					var tgt: Node = raw_t if raw_t is Node else null
					if is_instance_valid(tgt):
						current_arr[i] = source.get_path_to(tgt)
				source.set(prop_name, current_arr)


## Converts root CSGShape3D trees into StaticBody3D + external binary .res ArrayMesh.
static func _bake_all_csg_roots(root: Node) -> int:
	var csg_roots: Array[CSGShape3D] = []
	_collect_csg_roots(root, root, csg_roots)

	var baked_count: int = 0
	var scene_prefix: String = root.name.to_snake_case()

	for csg: CSGShape3D in csg_roots:
		if not is_instance_valid(csg):
			continue

		var raw_scr: Variant = csg.get_script()
		var scr: Script = raw_scr if raw_scr is Script else null
		if scr != null and not BAKE_PROCEDURAL_CSG:
			if scr.resource_path in PROCEDURAL_CSG_SCRIPTS:
				print("OrganizeAndBakeTestbed: Keeping live procedural CSG: ", csg.name)
				continue

		if csg.has_method(&"_update_shape"):
			csg.call(&"_update_shape")

		var mesh_pair: Array = csg.get_meshes()
		var raw_mesh: Variant = mesh_pair[1] if mesh_pair.size() >= 2 else null
		var array_mesh: ArrayMesh = raw_mesh if raw_mesh is ArrayMesh else null
		if array_mesh == null:
			push_warning("OrganizeAndBakeTestbed: CSG produced no ArrayMesh: " + csg.name)
			continue
		if array_mesh.get_surface_count() == 0:
			continue

		var safe_name: String = csg.name.to_snake_case().validate_filename()
		var mesh_path: String = (
			"%s%s_%s_%d.res" % [BAKED_MESH_DIR, scene_prefix, safe_name, baked_count]
		)
		var save_err: Error = ResourceSaver.save(array_mesh, mesh_path, ResourceSaver.FLAG_COMPRESS)
		if save_err != OK:
			push_error("OrganizeAndBakeTestbed: Failed saving mesh: " + mesh_path)
			continue

		var saved_mesh: ArrayMesh = ResourceLoader.load(mesh_path) as ArrayMesh
		var parent: Node = csg.get_parent()
		var orig_name: String = csg.name
		var orig_xform: Transform3D = csg.transform
		var use_collision: bool = csg.use_collision
		var col_layer: int = (
			csg.collision_layer | CollisionLayers.MASK_ENVIRONMENT
			if use_collision
			else CollisionLayers.MASK_ENVIRONMENT
		)
		var col_mask: int = csg.collision_mask if use_collision else 1

		var replacement: Node3D = null
		if use_collision:
			var static_body: StaticBody3D = StaticBody3D.new()
			static_body.collision_layer = col_layer
			static_body.collision_mask = col_mask

			var mesh_inst: MeshInstance3D = MeshInstance3D.new()
			mesh_inst.name = "MeshInstance3D"
			mesh_inst.mesh = saved_mesh
			mesh_inst.gi_mode = csg.gi_mode
			mesh_inst.cast_shadow = csg.cast_shadow
			static_body.add_child(mesh_inst)

			var col_shape: CollisionShape3D = CollisionShape3D.new()
			col_shape.name = "CollisionShape3D"
			var concave: ConcavePolygonShape3D = saved_mesh.create_trimesh_shape()
			if concave != null:
				concave.backface_collision = true
				col_shape.shape = concave
			static_body.add_child(col_shape)
			replacement = static_body
		else:
			var mesh_inst: MeshInstance3D = MeshInstance3D.new()
			mesh_inst.mesh = saved_mesh
			mesh_inst.gi_mode = csg.gi_mode
			mesh_inst.cast_shadow = csg.cast_shadow
			replacement = mesh_inst

		replacement.transform = orig_xform
		parent.add_child(replacement)
		parent.move_child(replacement, csg.get_index())
		replacement.owner = root
		for child: Node in replacement.get_children():
			child.owner = root

		for child: Node in csg.get_children():
			if not (child is CSGShape3D):
				csg.remove_child(child)
				replacement.add_child(child)
				_set_owner_recursive(child, root)

		parent.remove_child(csg)
		csg.free()
		replacement.name = orig_name
		baked_count += 1

	return baked_count


## Saves inline ArrayMesh subresources to external binary .res files.
static func _externalize_inline_array_meshes(root: Node) -> int:
	var count: int = 0
	var scene_prefix: String = root.name.to_snake_case()
	var all_nodes: Array[Node] = _get_all_descendants(root)

	for node: Node in all_nodes:
		if node != root and not node.scene_file_path.is_empty():
			continue
		if node.owner != root:
			continue
		if node is MeshInstance3D:
			var mi: MeshInstance3D = node as MeshInstance3D
			if mi.mesh is ArrayMesh:
				var am: ArrayMesh = mi.mesh as ArrayMesh
				if am.resource_path.is_empty() or am.resource_path.contains("::"):
					var safe_name: String = mi.name.to_snake_case().validate_filename()
					var mesh_path: String = (
						"%s%s_inline_%s_%d.res" % [BAKED_MESH_DIR, scene_prefix, safe_name, count]
					)
					if ResourceSaver.save(am, mesh_path, ResourceSaver.FLAG_COMPRESS) == OK:
						mi.mesh = ResourceLoader.load(mesh_path) as ArrayMesh
						count += 1
	return count


## Collects top-level CSGShape3D roots, ignoring child boolean operands and sub-scenes.
static func _collect_csg_roots(node: Node, scene_root: Node, out_roots: Array[CSGShape3D]) -> void:
	if node is CSGShape3D:
		var csg: CSGShape3D = node as CSGShape3D
		if csg.is_root_shape():
			out_roots.append(csg)
		return
	if node != scene_root and not node.scene_file_path.is_empty():
		return
	for child: Node in node.get_children():
		_collect_csg_roots(child, scene_root, out_roots)


## Creates or retrieves standard functional Node3D buckets under [param root].
static func _ensure_buckets(root: Node) -> Dictionary[StringName, Node3D]:
	var buckets: Dictionary[StringName, Node3D] = {}
	for b_name: StringName in BUCKET_NAMES:
		var existing_node: Node = root.get_node_or_null(NodePath(b_name))
		var existing: Node3D = existing_node if existing_node is Node3D else null
		if existing == null:
			existing = Node3D.new()
			existing.name = b_name
			root.add_child(existing)
			existing.owner = root
		buckets[b_name] = existing
	return buckets


## Reparents direct children of [param root] into functional buckets preserving transforms.
static func _organize_root_children(root: Node, buckets: Dictionary[StringName, Node3D]) -> int:
	var moved: int = 0
	var children: Array[Node] = root.get_children()

	for child: Node in children:
		if BUCKET_NAMES.has(child.name):
			continue
		var raw_scr: Variant = child.get_script()
		var scr: Script = raw_scr if raw_scr is Script else null
		if (
			child is WorldEnvironment
			or child is DirectionalLight3D
			or (scr != null and scr.resource_path.ends_with("chunk_manager.gd"))
		):
			continue

		var target_name: StringName = _classify_node(child)
		var target_bucket: Node3D = buckets.get(target_name, buckets[&"Geometry"])
		if child.get_parent() != target_bucket:
			_safe_reparent(child, target_bucket, root)
			moved += 1
	return moved


## Reparents [param node] under [param new_parent] while preserving local/world transform.
static func _safe_reparent(node: Node, new_parent: Node, root: Node) -> void:
	var node_3d: Node3D = node if node is Node3D else null
	var prev_xform: Transform3D = node_3d.transform if node_3d != null else Transform3D.IDENTITY
	var parent_3d: Node3D = node.get_parent() as Node3D if node.get_parent() is Node3D else null
	var world_xform: Transform3D = (
		parent_3d.transform * prev_xform if parent_3d != null else prev_xform
	)

	_set_owner_recursive(node, null)
	node.get_parent().remove_child(node)
	new_parent.add_child(node)
	_set_owner_recursive(node, root)

	if node_3d != null:
		var new_parent_3d: Node3D = new_parent as Node3D if new_parent is Node3D else null
		if new_parent_3d != null:
			node_3d.transform = new_parent_3d.transform.affine_inverse() * world_xform
		else:
			node_3d.transform = world_xform


## Classifies [param node] into a functional bucket by scene path, script path, name, or type.
static func _classify_node(node: Node) -> StringName:
	var scene_path: String = node.scene_file_path.to_lower()
	var node_name: String = String(node.name).to_lower()
	var raw_scr: Variant = node.get_script()
	var script_path: String = (
		(raw_scr as Script).resource_path.to_lower() if raw_scr is Script else ""
	)
	var combined: String = scene_path + " " + script_path + " " + node_name

	if node.name == &"Player" or scene_path.contains("player/player.tscn"):
		return &"Entities"
	if scene_path.begins_with("res://enemies/") or script_path.begins_with("res://enemies/"):
		return &"Enemies"
	if (
		scene_path.begins_with("res://triggers/")
		or script_path.begins_with("res://triggers/")
		or combined.contains("soundscape")
		or combined.contains("checkpoint")
		or combined.contains("commentary")
		or combined.contains("trigger")
		or node is Area3D
	):
		return &"Triggers"
	if (
		scene_path.begins_with("res://interactables/")
		or script_path.begins_with("res://interactables/")
		or scene_path.begins_with("res://weapons/")
		or combined.contains("door")
		or combined.contains("valve")
		or combined.contains("button")
		or combined.contains("pickable")
		or combined.contains("plug")
		or combined.contains("socket")
		or combined.contains("cable")
		or combined.contains("zipline")
		or combined.contains("fastrope")
		or combined.contains("fast_rope")
		or combined.contains("ladder")
		or combined.contains("glass")
		or node is RigidBody3D
		or node is PhysicalBoneSimulator3D
	):
		return &"Interactables"
	if (
		scene_path.begins_with("res://vfx/")
		or script_path.begins_with("res://vfx/")
		or combined.contains("vfx_")
		or combined.contains("bloodburst")
		or node is GPUParticles3D
		or node is CPUParticles3D
		or node is Decal
	):
		return &"VFX"
	if (
		node is Light3D
		or node is ReflectionProbe
		or node is VoxelGI
		or node is FogVolume
		or node is AnimationPlayer
		or combined.contains("lights")
		or combined.contains("lightlogic")
		or combined.contains("lightsequence")
		or combined.contains("clouds")
		or combined.contains("rain")
		or combined.contains("weather")
		or combined.contains("lightning")
		or combined.contains("ocean")
		or combined.contains("snow")
	):
		return &"Environment"
	return &"Geometry"


## Collects all descendants of [param node] recursively.
static func _get_all_descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(_get_all_descendants(child))
	return result


## Sets [param new_owner] recursively on [param node] without entering instanced sub-scenes.
static func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	if node.scene_file_path.is_empty():
		for child: Node in node.get_children():
			_set_owner_recursive(child, new_owner)
