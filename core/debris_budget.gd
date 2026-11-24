## Global debris budget manager enforcing a FIFO cap on active [RigidBody3D] debris.
# class_name DebrisBudget
extends Node

## Default maximum number of active debris bodies allowed simultaneously.
const DEFAULT_MAX_DEBRIS: int = 48

## Runtime maximum number of active debris bodies before oldest entries are evicted.
var max_debris: int = DEFAULT_MAX_DEBRIS

## FIFO list of currently tracked active debris [RigidBody3D] instances.
var _active_bodies: Array[RigidBody3D] = []


## Disables per-frame processing and binds [signal SceneTree.scene_changed].
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	var tree: SceneTree = get_tree()
	if is_instance_valid(tree):
		Utilities.safe_connect(tree.scene_changed, _on_scene_changed)
	print("DebrisBudget: Initialized with max_debris = ", max_debris)


## Disconnects global [SceneTree] signals when exiting the tree.
func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if is_instance_valid(tree) and tree.scene_changed.is_connected(_on_scene_changed):
		tree.scene_changed.disconnect(_on_scene_changed)


## Registers [param body] under the FIFO debris budget, evicting oldest entries if full.
func register_debris(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	_prune_invalid()
	if _active_bodies.has(body):
		return
	var limit: int = maxi(max_debris, 1)
	while _active_bodies.size() >= limit:
		var oldest: RigidBody3D = _active_bodies[0]
		_active_bodies.remove_at(0)
		if is_instance_valid(oldest) and not oldest.is_queued_for_deletion():
			_evict_body(oldest)
	_active_bodies.append(body)
	var exit_cb: Callable = _on_debris_tree_exited.bind(body.get_instance_id())
	body.tree_exited.connect(exit_cb, Object.CONNECT_ONE_SHOT)


## Prunes freed or queued debris and returns the active tracked count.
func get_active_count() -> int:
	_prune_invalid()
	return _active_bodies.size()


## Evicts all tracked debris bodies and clears the active registry.
func clear_all() -> void:
	if _active_bodies.is_empty():
		return
	var snapshot: Array[RigidBody3D] = _active_bodies.duplicate()
	_active_bodies.clear()
	var cleared_count: int = 0
	for body: RigidBody3D in snapshot:
		if is_instance_valid(body) and not body.is_queued_for_deletion():
			_evict_body(body)
			cleared_count += 1
	if cleared_count > 0:
		print("DebrisBudget: Cleared ", cleared_count, " debris bodies.")


## Clears active debris when the [SceneTree] transitions to a new scene.
func _on_scene_changed() -> void:
	print("DebrisBudget: Scene changed, clearing active debris.")
	clear_all()


## Prunes [param body_id] and any invalid entries when a tracked body exits the tree.
func _on_debris_tree_exited(body_id: int) -> void:
	_prune_invalid(body_id)


## Compacts [member _active_bodies] in place, dropping invalid or [param exclude_id] nodes.
func _prune_invalid(exclude_id: int = -1) -> void:
	var write_idx: int = 0
	for i: int in range(_active_bodies.size()):
		var entry: RigidBody3D = _active_bodies[i]
		var keep: bool = is_instance_valid(entry) and not entry.is_queued_for_deletion()
		if keep and (exclude_id == -1 or entry.get_instance_id() != exclude_id):
			_active_bodies[write_idx] = entry
			write_idx += 1
	_active_bodies.resize(write_idx)


## Evicts [param body] via evict_now if supported, otherwise calls [method Node.queue_free].
func _evict_body(body: RigidBody3D) -> void:
	if body.has_method(&"evict_now"):
		body.call(&"evict_now")
	else:
		body.queue_free()
