## Unit tests verifying bear trap trigger interactions, damage, and immobilization timers.
class_name TestBearTrap
extends GutTest

## The [BearTrap] instance under test.
var bear_trap: BearTrap = null

## The mock [Player] instance.
var mock_player: MockPlayer = null


## Mock implementation of [Player] tracking damage and holding mock components.
class MockPlayer:
	extends Player

	## Tracks the last damage value applied.
	var last_damage: int = 0

	## Simulates player damage.
	func take_damage(amount: int) -> void:
		print("TestBearTrap: MockPlayer take_damage() called with: ", amount)
		last_damage = amount


## Mock locomotion component tracking sprint flags.
class MockLocomotion:
	extends PlayerLocomotionComponent

	## Tracks sprint capability flag.
	var can_sprint: bool = true


## Mock system menu controller tracking stun status.
class MockMenu:
	extends SystemMenuController

	## Tracks stun status flag.
	var is_stunned: bool = false


## Stub component to satisfy missing [Player] dependencies.
class DummyComponent:
	extends Node

	## Empty initialization stub.
	func initialize(_p: Node) -> void:
		pass


## Sets up the bear trap and typed mock dependencies before each test.
func before_each() -> void:
	print("TestBearTrap: before_each() setup started.")

	var bear_trap_scene: PackedScene = load("res://enemies/bear_trap.tscn")
	bear_trap = bear_trap_scene.instantiate() as BearTrap
	add_child_autoqfree(bear_trap)

	mock_player = MockPlayer.new()
	var loco: MockLocomotion = MockLocomotion.new()
	var menu: MockMenu = MockMenu.new()
	var dummy_interact: DummyComponent = DummyComponent.new()
	var dummy_env: DummyComponent = DummyComponent.new()
	var dummy_stat: DummyComponent = DummyComponent.new()

	mock_player.locomotion_component = loco
	mock_player.system_menu = menu
	mock_player.interaction_component = dummy_interact
	mock_player.environment_component = dummy_env
	mock_player.stats_component = dummy_stat

	mock_player.add_child(loco)
	mock_player.add_child(menu)
	mock_player.add_child(dummy_interact)
	mock_player.add_child(dummy_env)
	mock_player.add_child(dummy_stat)

	var components_node: Node = Node.new()
	components_node.name = "Components"
	mock_player.add_child(components_node)

	var health_node: HealthComponent = HealthComponent.new()
	health_node.name = "HealthComponent"
	components_node.add_child(health_node)

	add_child_autoqfree(mock_player)
	await get_tree().process_frame


## Validates initial trap state is set to OPEN.
func test_initial_state() -> void:
	print("TestBearTrap: test_initial_state() called.")
	assert_eq(
		bear_trap.current_state, BearTrap.TrapState.OPEN, "BearTrap should start in OPEN state."
	)


## Validates snapping logic, damage application, and state flags are correctly applied to player.
func test_snap_shut() -> void:
	print("TestBearTrap: test_snap_shut() called.")
	bear_trap.snap_shut(mock_player)

	assert_eq(
		bear_trap.current_state,
		BearTrap.TrapState.CLOSED,
		"BearTrap should be CLOSED after snapping."
	)
	assert_eq(mock_player.last_damage, 150, "Player should take 150 damage.")
	assert_not_null(mock_player.system_menu, "System menu must not be null.")
	assert_true(mock_player.system_menu.is_stunned, "Player should be stunned.")
	assert_false(mock_player.locomotion_component.can_sprint, "Player sprint should be disabled.")
	assert_true(bear_trap.immobilize_timer.time_left > 0.0, "Immobilize timer should be started.")
	assert_true(
		bear_trap.sprint_block_timer.time_left > 0.0, "Sprint block timer should be started."
	)


## Validates timeouts resetting player state correctly after trap duration expires.
func test_timer_timeouts() -> void:
	print("TestBearTrap: test_timer_timeouts() called.")
	bear_trap.snap_shut(mock_player)

	bear_trap._on_immobilize_timeout()
	assert_not_null(mock_player.system_menu, "System menu must not be null.")
	assert_false(
		mock_player.system_menu.is_stunned, "Player should not be stunned after immobilize timeout."
	)

	bear_trap._on_sprint_block_timeout()
	assert_not_null(mock_player.locomotion_component, "Locomotion component must not be null.")
	assert_true(
		mock_player.locomotion_component.can_sprint,
		"Player sprint should be enabled after sprint block timeout."
	)
	assert_null(bear_trap.trapped_player, "Trapped player reference should be cleared.")
