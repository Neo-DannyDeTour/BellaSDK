class_name Utilities
extends RefCounted
## Centralized static utility class for project-wide boilerplate reduction and safe operations.

## Cached query parameters for [method raycast_3d] to eliminate per-frame allocations at 60 FPS.
static var _cached_ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


## Sets pivot offset of [param control] to its visual center using size or custom minimum size.
static func center_control(control: Control) -> void:
	if not is_instance_valid(control):
		return
	var sz: Vector2 = control.size
	if sz == Vector2.ZERO:
		sz = control.custom_minimum_size
	control.pivot_offset = sz * 0.5
	print("[Utilities] Center control pivot set for: ", control.name)


## Safely clears and frees all child nodes under [param parent] via [method Node.queue_free].
static func clear_children(parent: Node) -> void:
	if not is_instance_valid(parent):
		return
	var count: int = parent.get_child_count()
	for child: Node in parent.get_children():
		child.queue_free()
	print("[Utilities] Cleared ", count, " children from: ", parent.name)


## Kills [param existing_tween] if valid and creates a new managed [Tween] on [param node].
static func reset_tween(node: Node, existing_tween: Tween) -> Tween:
	if is_instance_valid(existing_tween) and existing_tween.is_valid():
		existing_tween.kill()
	if not is_instance_valid(node) or not node.is_inside_tree():
		return null
	var new_tw: Tween = node.create_tween()
	return new_tw


## Safely connects [param sig] to [param callable] if not already connected.
static func safe_connect(sig: Signal, callable: Callable, flags: int = 0) -> bool:
	if not sig.is_connected(callable):
		sig.connect(callable, flags)
		print("[Utilities] Connected signal ", sig.get_name(), " to ", callable.get_method())
		return true
	return false


## Safely reparents [param node] to [param new_parent] using native [method Node.reparent].
static func reparent_keep_transform(
	node: Node, new_parent: Node, keep_global_transform: bool = true
) -> void:
	if not is_instance_valid(node) or not is_instance_valid(new_parent):
		return
	if not node.is_inside_tree() or not new_parent.is_inside_tree():
		return
	node.reparent(new_parent, keep_global_transform)
	print("[Utilities] Reparented node ", node.name, " to ", new_parent.name)


## Executes a 3D raycast query using [param space_state] with a cached query instance.
static func raycast_3d(
	space_state: PhysicsDirectSpaceState3D,
	origin: Vector3,
	target: Vector3,
	collision_mask: int = 1,
	exclude: Array[RID] = []
) -> Dictionary:
	if not space_state:
		return {}
	_cached_ray_query.from = origin
	_cached_ray_query.to = target
	_cached_ray_query.collision_mask = collision_mask
	_cached_ray_query.exclude = exclude
	return space_state.intersect_ray(_cached_ray_query)


## Creates a [SceneTreeTimer] on [param node] and connects timeout to [param callable].
static func delay_call(
	node: Node, delay_seconds: float, callable: Callable, process_always: bool = false
) -> SceneTreeTimer:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return null
	var timer: SceneTreeTimer = node.get_tree().create_timer(delay_seconds, process_always)
	timer.timeout.connect(callable, Object.CONNECT_ONE_SHOT)
	print("[Utilities] Scheduled delay call (", delay_seconds, "s) on node: ", node.name)
	return timer


## Traverses parent hierarchy of [param node] to find first ancestor of type [param script_type].
static func find_ancestor_of_type(node: Node, script_type: Script) -> Node:
	if not is_instance_valid(node) or not script_type:
		return null
	var current: Node = node.get_parent()
	while is_instance_valid(current):
		if is_instance_of(current, script_type):
			print("[Utilities] Found ancestor ", current.name, " for ", node.name)
			return current
		current = current.get_parent()
	return null
