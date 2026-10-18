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
	print("[Utilities] Reset basic tween on node: ", node.name)
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
	print("[Utilities] Reset extended tween on node: ", node.name)
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
	collision_mask: int = 1,
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


## Traverses parent hierarchy of [param node] to find ancestor matching [param script_type].
## Forwarded to [NodeQuery.find_ancestor_of_type] as single source of truth.
static func find_ancestor_of_type(node: Node, script_type: Script) -> Node:
	return NodeQuery.find_ancestor_of_type(node, script_type)


## Kills [param tween] safely if valid and currently active.
static func safe_kill_tween(tween: Tween) -> void:
	if is_instance_valid(tween) and tween.is_valid():
		tween.kill()
		print("[Utilities] Killed active tween.")


## Snaps 3D position [param pos] to coordinate grid step [param grid_step].
## Forwarded to [MathUtils.snap_to_grid_3d] as single source of truth.
static func snap_to_grid_3d(pos: Vector3, grid_step: float) -> Vector3:
	var snapped_pos: Vector3 = MathUtils.snap_to_grid_3d(pos, grid_step)
	print("[Utilities] Snapped position ", pos, " to: ", snapped_pos)
	return snapped_pos


## Normalizes radian angle [param angle_rad] to the range [-PI, PI].
## Forwarded to [MathUtils.normalize_angle] as single source of truth.
static func normalize_angle(angle_rad: float) -> float:
	var normalized: float = MathUtils.normalize_angle(angle_rad)
	print("[Utilities] Normalized angle ", angle_rad, " to: ", normalized)
	return normalized


## Checks if squared distance between [param pos_a] and [param pos_b] <= [param max_dist].
## Forwarded to [MathUtils.is_within_distance_3d] as single source of truth.
static func is_within_distance_3d(pos_a: Vector3, pos_b: Vector3, max_dist: float) -> bool:
	var is_within: bool = MathUtils.is_within_distance_3d(pos_a, pos_b, max_dist)
	print(
		"[Utilities] Distance check between ",
		pos_a,
		" and ",
		pos_b,
		" <= ",
		max_dist,
		": ",
		is_within
	)
	return is_within
