## Unit tests for ObjectPool verifying pre-allocation, spawning, recycling, growth, and signals.
class_name TestObjectPool
extends GutTest

const OBJECT_POOL_SCRIPT: GDScript = preload("res://core/object_pool.gd")

## Test ObjectPool node instance under test.
var pool: ObjectPool = null

## Dummy PackedScene template used for instantiating pooled 3D nodes.
var dummy_scene: PackedScene = null


## Prepares the dummy scene template and creates a fresh ObjectPool instance for each test.
func before_each() -> void:
	print("TestObjectPool: before_each() setup.")

	var dummy_script: GDScript = GDScript.new()
	dummy_script.source_code = "extends Node3D\nfunc on_spawn() -> void:\n\tpass\n"
	dummy_script.reload()

	var dummy_node: Node3D = Node3D.new()
	dummy_node.set_script(dummy_script)

	dummy_scene = PackedScene.new()
	dummy_scene.pack(dummy_node)
	dummy_node.free()

	pool = OBJECT_POOL_SCRIPT.new() as ObjectPool
	pool.template_scene = dummy_scene
	pool.initial_pool_size = 5
	pool.can_grow = false
	add_child_autofree(pool)
	pool._ready()


## Verifies initial pool pre-allocation capacity and idle count.
func test_initialization_and_preallocation() -> void:
	print("TestObjectPool: test_initialization_and_preallocation() called.")
	assert_eq(pool.get_available_count(), 5, "Pool should pre-allocate 5 idle instances.")
	assert_eq(pool.get_active_count(), 0, "Pool should have 0 active instances initially.")


## Verifies spawning and recycling an instance along with corresponding signals.
func test_spawn_and_recycle() -> void:
	print("TestObjectPool: test_spawn_and_recycle() called.")
	watch_signals(pool)

	var spawn_pos: Vector3 = Vector3(10.0, 5.0, -2.0)
	var instance: Node = pool.spawn(spawn_pos)

	assert_not_null(instance, "Spawned instance should not be null.")
	assert_eq(pool.get_available_count(), 4, "Available count should decrease to 4.")
	assert_eq(pool.get_active_count(), 1, "Active count should increase to 1.")
	assert_signal_emitted_with_parameters(pool, "object_spawned", [instance])

	var node_3d: Node3D = instance as Node3D
	assert_not_null(node_3d, "Instance should be a Node3D.")
	assert_eq(node_3d.global_position, spawn_pos, "Spawned position should match requested pos.")
	assert_true(node_3d.visible, "Spawned node should be visible.")
	assert_eq(node_3d.process_mode, Node.PROCESS_MODE_INHERIT, "Process mode should be inherit.")

	pool.recycle(instance)

	assert_eq(pool.get_available_count(), 5, "Available count should return to 5.")
	assert_eq(pool.get_active_count(), 0, "Active count should return to 0.")
	assert_signal_emitted_with_parameters(pool, "object_recycled", [instance])
	assert_false(node_3d.visible, "Recycled node should be hidden.")
	assert_eq(node_3d.process_mode, Node.PROCESS_MODE_DISABLED, "Process mode should be disabled.")


## Verifies spawning an instance with a full Transform3D.
func test_spawn_with_transform() -> void:
	print("TestObjectPool: test_spawn_with_transform() called.")
	var target_transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(3.0, 1.5, -7.0))
	var instance: Node = pool.spawn_with_transform(target_transform)

	assert_not_null(instance, "Spawned instance should not be null.")
	var node_3d: Node3D = instance as Node3D
	assert_not_null(node_3d, "Instance should be a Node3D.")
	assert_eq(
		node_3d.global_transform,
		target_transform,
		"Global transform should match requested transform."
	)


## Verifies pool behavior when capacity is exhausted with and without growth enabled.
func test_pool_growth() -> void:
	print("TestObjectPool: test_pool_growth() called.")
	var spawned_nodes: Array[Node] = []
	for i: int in range(5):
		spawned_nodes.append(pool.spawn())

	assert_eq(pool.get_active_count(), 5, "All 5 instances should be active.")
	assert_eq(pool.get_available_count(), 0, "No available instances should remain.")

	var overflow_node: Node = pool.spawn()
	assert_null(overflow_node, "Spawn should return null when pool is exhausted and cannot grow.")

	pool.can_grow = true
	var grown_node: Node = pool.spawn()
	assert_not_null(grown_node, "Spawn should return new instance when can_grow is true.")
	assert_eq(pool.get_active_count(), 6, "Active count should increase to 6 after growth.")


## Verifies recycling all currently active instances.
func test_recycle_all() -> void:
	print("TestObjectPool: test_recycle_all() called.")
	for i: int in range(3):
		pool.spawn()

	assert_eq(pool.get_active_count(), 3, "3 instances should be active.")
	assert_eq(pool.get_available_count(), 2, "2 instances should remain available.")

	pool.recycle_all()

	assert_eq(pool.get_active_count(), 0, "0 instances should be active after recycle_all.")
	assert_eq(pool.get_available_count(), 5, "5 instances should be available after recycle_all.")


## Verifies clearing and freeing all pool instances.
func test_clear_pool() -> void:
	print("TestObjectPool: test_clear_pool() called.")
	pool.spawn()
	assert_eq(pool.get_active_count(), 1, "1 instance active prior to clearing.")

	pool.clear_pool()

	assert_eq(pool.get_active_count(), 0, "Active count should be 0 after clear_pool.")
	assert_eq(pool.get_available_count(), 0, "Available count should be 0 after clear_pool.")
