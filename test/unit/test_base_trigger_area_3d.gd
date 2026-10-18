## Unit tests for [BaseTriggerArea3D] validating bounds, layer masks, and player detection.
class_name TestBaseTriggerArea3D
extends GutTest

## The [BaseTriggerArea3D] instance under test.
var _trigger: BaseTriggerArea3D = null

## The mock player node instance.
var _player: Node3D = null

## Number of times player_entered signal fired.
var _entered_count: int = 0

## Number of times player_exited signal fired.
var _exited_count: int = 0

## Node reference received by player_entered signal.
var _last_entered_node: Node3D = null

## Node reference received by player_exited signal.
var _last_exited_node: Node3D = null


## Listener recording player entry events.
func _on_player_entered(node: Node3D) -> void:
	_entered_count += 1
	_last_entered_node = node


## Listener recording player exit events.
func _on_player_exited(node: Node3D) -> void:
	_exited_count += 1
	_last_exited_node = node


## Prepares test nodes and wiring before each test execution.
func before_each() -> void:
	print("TestBaseTriggerArea3D: Setting up test environment.")
	_trigger = BaseTriggerArea3D.new()

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	_trigger.add_child(col)
	add_child_autoqfree(_trigger)

	_player = Node3D.new()
	_player.name = "Player"
	add_child_autoqfree(_player)

	_entered_count = 0
	_exited_count = 0
	_last_entered_node = null
	_last_exited_node = null

	_trigger.player_entered.connect(_on_player_entered)
	_trigger.player_exited.connect(_on_player_exited)


## Clears local instance references after each test execution.
func after_each() -> void:
	print("TestBaseTriggerArea3D: Tearing down test environment.")
	_trigger = null
	_player = null
	_last_entered_node = null
	_last_exited_node = null


## Verifies collision layers and mask initialization according to project conventions.
func test_collision_layers_and_mask_initialized() -> void:
	print("TestBaseTriggerArea3D: test_collision_layers_and_mask_initialized() executing.")
	assert_eq(
		_trigger.collision_layer,
		CollisionLayers.MASK_NONE,
		"Base trigger volume should not occupy any collision layer."
	)
	assert_eq(
		_trigger.collision_mask,
		CollisionLayers.MASK_PLAYER,
		"Base trigger volume must scan for player physics layer only."
	)


## Verifies player identification by name prefix.
func test_player_identified_by_name() -> void:
	print("TestBaseTriggerArea3D: test_player_identified_by_name() executing.")
	assert_true(
		_trigger._is_player(_player), "Node with name prefix 'Player' must be identified as player."
	)


## Verifies player identification by group membership.
func test_player_identified_by_group() -> void:
	print("TestBaseTriggerArea3D: test_player_identified_by_group() executing.")
	var group_player: Node3D = Node3D.new()
	group_player.name = "CharacterRoot"
	group_player.add_to_group(&"player")
	add_child_autoqfree(group_player)

	assert_true(
		_trigger._is_player(group_player),
		"Node belonging to &group 'player' must be identified as player."
	)


## Verifies non-player bodies are rejected without dispatching signals.
func test_non_player_rejected() -> void:
	print("TestBaseTriggerArea3D: test_non_player_rejected() executing.")
	var npc: Node3D = Node3D.new()
	npc.name = "EnemyDrone"
	add_child_autoqfree(npc)

	assert_false(_trigger._is_player(npc), "Foreign entity must not be recognized as a player.")

	_trigger._on_body_entered(npc)
	assert_eq(_entered_count, 0, "player_entered signal must not fire for non-player bodies.")


## Verifies signal dispatching upon player entry and exit.
func test_player_entry_and_exit_signals() -> void:
	print("TestBaseTriggerArea3D: test_player_entry_and_exit_signals() executing.")
	_trigger.trigger_once = false

	_trigger._on_body_entered(_player)
	assert_eq(_entered_count, 1, "player_entered signal should fire once.")
	assert_eq(_last_entered_node, _player, "player_entered payload should match player node.")

	_trigger._on_body_exited(_player)
	assert_eq(_exited_count, 1, "player_exited signal should fire once.")
	assert_eq(_last_exited_node, _player, "player_exited payload should match player node.")


## Verifies single execution policy when trigger_once is enabled.
func test_trigger_once_blocks_reentry() -> void:
	print("TestBaseTriggerArea3D: test_trigger_once_blocks_reentry() executing.")
	_trigger.trigger_once = true

	_trigger._on_body_entered(_player)
	assert_eq(_entered_count, 1, "First entry should emit player_entered.")

	_trigger._on_body_exited(_player)
	assert_eq(_exited_count, 1, "Exit should emit player_exited.")

	_trigger._on_body_entered(_player)
	assert_eq(_entered_count, 1, "Re-entry must be blocked when trigger_once is true.")


## Verifies repeated execution when trigger_once is disabled.
func test_trigger_reentry_when_trigger_once_false() -> void:
	print("TestBaseTriggerArea3D: test_trigger_reentry_when_trigger_once_false() executing.")
	_trigger.trigger_once = false

	_trigger._on_body_entered(_player)
	_trigger._on_body_exited(_player)
	_trigger._on_body_entered(_player)

	assert_eq(
		_entered_count, 2, "Re-entry must emit player_entered again when trigger_once is false."
	)


## Verifies collision shape updating upon dimension modifications.
func test_shape_bounds_synchronization() -> void:
	print("TestBaseTriggerArea3D: test_shape_bounds_synchronization() executing.")
	_trigger.shape_type = EditorTriggerVisualizer.ShapeType.BOX
	_trigger.trigger_size = Vector3(4.0, 6.0, 8.0)

	var box_shape: BoxShape3D = _trigger._get_collision_shape().shape as BoxShape3D
	assert_not_null(box_shape, "Collision shape should be BoxShape3D.")
	assert_eq(box_shape.size, Vector3(4.0, 6.0, 8.0), "Box dimensions should match trigger_size.")

	_trigger.shape_type = EditorTriggerVisualizer.ShapeType.SPHERE
	_trigger.trigger_size = Vector3(10.0, 10.0, 10.0)

	var sphere_shape: SphereShape3D = _trigger._get_collision_shape().shape as SphereShape3D
	assert_not_null(sphere_shape, "Collision shape should be SphereShape3D.")
	assert_eq(sphere_shape.radius, 5.0, "Sphere radius should match half of trigger_size.x.")
