## Generic node pool manager for pre-allocation, zero-allocation spawning, and recycling.
class_name ObjectPool
extends Node

## Emitted when an object is taken from the pool. Passes [param instance].
signal object_spawned(instance: Node)

## Emitted when an active object is returned to the pool. Passes [param instance].
signal object_recycled(instance: Node)

## Default capacity count for pre-allocated entity instances.
const DEFAULT_CAPACITY: int = 32

## Dormant 3D position vector used for deactivated pooled nodes.
const DORMANT_POSITION_3D: Vector3 = Vector3(0.0, -10000.0, 0.0)

## Packed scene resource used to instantiate pooled objects.
@export var template_scene: PackedScene

## Total count of instances pre-allocated during [method _ready].
@export var initial_pool_size: int = DEFAULT_CAPACITY

## Allows pool expansion when all instances are exhausted.
@export var can_grow: bool = false

## Container node holding pre-allocated instances in the tree.
@export var pool_container: Node

## Internal list storing inactive [Node] objects ready for reuse.
var _available: Array[Node] = []

## Internal list tracking currently spawned and active [Node] objects.
var _active: Array[Node] = []

## Fast lookup dictionary mapping active instance IDs.
var _active_ids: Dictionary = {}


## Initializes the pool container and pre-allocates node instances.
func _ready() -> void:
	print("[ObjectPool] Initializing pool: ", name)
	_ensure_container()
	_preallocate_instances()


## Ensures a valid container node exists for holding pooled nodes.
func _ensure_container() -> void:
	print("[ObjectPool] Resolving container node.")
	if not is_instance_valid(pool_container):
		pool_container = self


## Pre-instantiates [member initial_pool_size] instances into the pool.
func _preallocate_instances() -> void:
	print("[ObjectPool] Pre-allocating ", initial_pool_size, " instances.")
	if template_scene == null:
		push_warning("[ObjectPool] Missing template_scene on: " + name)
		return

	for i: int in range(initial_pool_size):
		var instance: Node = _create_instance()
		if is_instance_valid(instance):
			_available.append(instance)


## Instantiates a single node from [member template_scene] and prepares it.
func _create_instance() -> Node:
	print("[ObjectPool] Instantiating new entity from template scene.")
	if template_scene == null:
		return null

	var instance: Node = template_scene.instantiate()
	pool_container.add_child(instance)

	if instance is Node3D:
		var node_3d: Node3D = instance if instance is Node3D else null
		node_3d.global_position = DORMANT_POSITION_3D
		node_3d.visible = false
	elif instance is CanvasItem:
		(instance as CanvasItem).visible = false

	instance.process_mode = Node.PROCESS_MODE_DISABLED
	return instance


## Retrieves an idle instance, repositions it, and activates it.
func spawn(global_pos: Vector3 = Vector3.ZERO, rot_euler: Vector3 = Vector3.ZERO) -> Node:
	print("[ObjectPool] Spawning instance at: ", global_pos)
	var instance: Node = _obtain_instance()
	if not is_instance_valid(instance):
		return null

	if instance is Node3D:
		var node_3d: Node3D = instance if instance is Node3D else null
		node_3d.global_position = global_pos
		node_3d.global_rotation = rot_euler

	_activate_instance(instance)
	return instance


## Retrieves an idle instance and configures its global [Transform3D].
func spawn_with_transform(global_xform: Transform3D) -> Node:
	print("[ObjectPool] Spawning instance with transform at: ", global_xform.origin)
	var instance: Node = _obtain_instance()
	if not is_instance_valid(instance):
		return null

	if instance is Node3D:
		(instance as Node3D).global_transform = global_xform

	_activate_instance(instance)
	return instance


## Fetches an available instance or instantiates one if expansion is allowed.
func _obtain_instance() -> Node:
	print("[ObjectPool] Obtaining instance from available pool.")
	var instance: Node = null

	if not _available.is_empty():
		instance = _available.pop_back()
	elif can_grow:
		print("[ObjectPool] Pool exhausted. Growing pool by 1 instance.")
		instance = _create_instance()
	else:
		push_warning("[ObjectPool] Pool exhausted and can_grow is false on: " + name)
		return null

	return instance


## Activates an instance, setting its visibility and process mode.
func _activate_instance(instance: Node) -> void:
	print("[ObjectPool] Activating instance: ", instance.name)
	_active.append(instance)
	_active_ids[instance.get_instance_id()] = true

	if instance is Node3D:
		var node_3d: Node3D = instance if instance is Node3D else null
		node_3d.visible = true

		if instance is RigidBody3D:
			var rb: RigidBody3D = instance if instance is RigidBody3D else null
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			rb.sleeping = false
		elif instance is CharacterBody3D:
			(instance as CharacterBody3D).velocity = Vector3.ZERO

	elif instance is CanvasItem:
		(instance as CanvasItem).visible = true

	instance.process_mode = Node.PROCESS_MODE_INHERIT

	if instance.has_method(&"on_spawn"):
		instance.call(&"on_spawn")
	elif instance.has_method(&"reset"):
		instance.call(&"reset")

	object_spawned.emit(instance)


## Deactivates an active instance and returns it to the available pool.
func recycle(instance: Node) -> void:
	if not is_instance_valid(instance):
		return

	var inst_id: int = instance.get_instance_id()
	if not _active_ids.has(inst_id):
		print("[ObjectPool] Instance already recycled or not in pool: ", instance.name)
		return

	print("[ObjectPool] Recycling instance: ", instance.name)
	_active_ids.erase(inst_id)
	_active.erase(instance)

	if instance.has_method(&"on_recycle"):
		instance.call(&"on_recycle")

	instance.process_mode = Node.PROCESS_MODE_DISABLED

	if instance is Node3D:
		var node_3d: Node3D = instance if instance is Node3D else null
		node_3d.visible = false
		node_3d.global_position = DORMANT_POSITION_3D

		if instance is RigidBody3D:
			var rb: RigidBody3D = instance if instance is RigidBody3D else null
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			rb.sleeping = true
		elif instance is CharacterBody3D:
			(instance as CharacterBody3D).velocity = Vector3.ZERO

	elif instance is CanvasItem:
		(instance as CanvasItem).visible = false

	_available.append(instance)
	object_recycled.emit(instance)


## Deactivates and recycles all currently active pooled instances.
func recycle_all() -> void:
	print("[ObjectPool] Recycling all active instances.")
	for i: int in range(_active.size() - 1, -1, -1):
		recycle(_active[i])


## Returns the number of currently active instances in the game world.
func get_active_count() -> int:
	print("[ObjectPool] Active count queried: ", _active.size())
	return _active.size()


## Returns the number of idle instances remaining in the pool.
func get_available_count() -> int:
	print("[ObjectPool] Available count queried: ", _available.size())
	return _available.size()


## Destroys all active and idle instances, resetting the entire pool.
func clear_pool() -> void:
	print("[ObjectPool] Clearing and freeing all instances from pool.")
	recycle_all()

	for node: Node in _available:
		if is_instance_valid(node):
			node.queue_free()

	_available.clear()
	_active.clear()
	_active_ids.clear()
