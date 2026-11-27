## Static utility library providing safe node, tween, and lifecycle helpers.
class_name Utilities
extends RefCounted


## Centers pivot offset of [param control] based on size or custom minimum size.
static func center_control(control: Control) -> void:
	if not is_instance_valid(control):
		return
	var sz: Vector2 = control.size
	if sz == Vector2.ZERO:
		sz = control.custom_minimum_size
	control.pivot_offset = sz * 0.5
	print("[Utilities] Center control pivot set for: ", control.name)


## Frees all child nodes under [param parent] safely using [method Node.queue_free].
static func clear_children(parent: Node) -> void:
	if not is_instance_valid(parent):
		return
	var count: int = parent.get_child_count()
	for child: Node in parent.get_children():
		child.queue_free()
	print("[Utilities] Cleared ", count, " children from: ", parent.name)


## Frees child nodes under [param parent] that belong to [param group_name].
static func clear_children_in_group(parent: Node, group_name: StringName) -> void:
	if not is_instance_valid(parent):
		return
	var freed_count: int = 0
	for child: Node in parent.get_children():
		if child.is_in_group(group_name):
			child.queue_free()
			freed_count += 1
	print(
		"[Utilities] Cleared ", freed_count, " children in '", group_name, "' from: ", parent.name
	)


## Kills [param existing_tween] if valid and creates a new [Tween] on [param node].
static func reset_tween(node: Node, existing_tween: Tween) -> Tween:
	if is_instance_valid(existing_tween) and existing_tween.is_valid():
		existing_tween.kill()
	if not is_instance_valid(node) or not node.is_inside_tree():
		return null
	var new_tw: Tween = node.create_tween()
	return new_tw


## Kills [param existing_tween] and creates a new [Tween] with transition and ease.
static func reset_tween_ext(
	node: Node,
	existing_tween: Tween,
	trans_type: Tween.TransitionType = Tween.TRANS_CUBIC,
	ease_type: Tween.EaseType = Tween.EASE_OUT
) -> Tween:
	if is_instance_valid(existing_tween) and existing_tween.is_valid():
		existing_tween.kill()
	if not is_instance_valid(node) or not node.is_inside_tree():
		return null
	var new_tw: Tween = node.create_tween()
	new_tw.set_trans(trans_type)
	new_tw.set_ease(ease_type)
	return new_tw


## Safely connects [param sig] to [param callable] if not already connected.
static func safe_connect(sig: Signal, callable: Callable, flags: int = 0) -> bool:
	if sig.is_null() or not callable.is_valid():
		return false
	if not sig.is_connected(callable):
		sig.connect(callable, flags)
		#print("[Utilities] Connected signal ", sig.get_name(), " to callable.")
		return true
	return false


## Reparents [param node] to [param new_parent] preserving global transform.
static func reparent_keep_transform(
	node: Node, new_parent: Node, keep_global_transform: bool = true
) -> void:
	if not is_instance_valid(node) or not is_instance_valid(new_parent):
		return
	if not node.is_inside_tree() or not new_parent.is_inside_tree():
		return
	node.reparent(new_parent, keep_global_transform)
	print("[Utilities] Reparented node ", node.name, " to ", new_parent.name)


## Executes 3D physics raycast using cached parameters and returns hit [Dictionary].
## Forwarded to [NodeQuery.cast_ray] as single source of truth.
static func raycast_3d(
	space_state: PhysicsDirectSpaceState3D,
	origin: Vector3,
	target: Vector3,
	collision_mask: int = CollisionLayers.MASK_ENVIRONMENT,
	exclude: Array[RID] = []
) -> Dictionary:
	return NodeQuery.cast_ray(space_state, origin, target, collision_mask, exclude)


## Creates a [SceneTreeTimer] on [param node] connecting timeout to [param callable].
static func delay_call(
	node: Node, delay_seconds: float, callable: Callable, process_always: bool = false
) -> SceneTreeTimer:
	if not is_instance_valid(node) or not node.is_inside_tree() or not callable.is_valid():
		return null
	var timer: SceneTreeTimer = node.get_tree().create_timer(delay_seconds, process_always)
	timer.timeout.connect(callable, Object.CONNECT_ONE_SHOT)
	print("[Utilities] Scheduled delay call (", delay_seconds, "s) on node: ", node.name)
	return timer


## Kills [param tween] safely if valid and currently active.
static func safe_kill_tween(tween: Tween) -> void:
	if is_instance_valid(tween) and tween.is_valid():
		tween.kill()


## Editor-only helper that bakes a [CSGShape3D] into a sibling [StaticBody3D] + .res mesh.
static func bake_csg_to_static_body(csg: CSGShape3D) -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(csg) or not csg.is_inside_tree():
		return
	if csg.has_method(&"_update_shape"):
		csg.call(&"_update_shape")
	var meshes: Array = csg.get_meshes()
	var raw_mesh: Variant = meshes[1] if meshes.size() >= 2 else null
	var array_mesh: ArrayMesh = raw_mesh if raw_mesh is ArrayMesh else null
	if array_mesh == null:
		push_error("Utilities: CSG bake failed, no ArrayMesh generated for ", csg.name)
		return
	var dir_path: String = "res://levels/baked_csg/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var save_path: String = (
		"%s%s_%d.res"
		% [dir_path, csg.name.to_snake_case().validate_filename(), Time.get_ticks_msec()]
	)
	if ResourceSaver.save(array_mesh, save_path, ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("Utilities: Failed to save baked CSG mesh to: ", save_path)
		return

	var saved_mesh: ArrayMesh = ResourceLoader.load(save_path) as ArrayMesh
	var static_body: StaticBody3D = StaticBody3D.new()
	static_body.name = String(csg.name) + "_Baked"
	static_body.transform = csg.transform
	static_body.collision_layer = csg.collision_layer | CollisionLayers.MASK_ENVIRONMENT
	static_body.collision_mask = csg.collision_mask

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	mesh_inst.mesh = saved_mesh
	static_body.add_child(mesh_inst)

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	var concave: ConcavePolygonShape3D = saved_mesh.create_trimesh_shape()
	if concave != null:
		concave.backface_collision = true
		col_shape.shape = concave
	static_body.add_child(col_shape)

	var scene_root: Node = csg.get_tree().edited_scene_root
	csg.get_parent().add_child(static_body)
	if is_instance_valid(scene_root):
		static_body.owner = scene_root
		mesh_inst.owner = scene_root
		col_shape.owner = scene_root
	print("Utilities: Baked CSG to ", save_path)
