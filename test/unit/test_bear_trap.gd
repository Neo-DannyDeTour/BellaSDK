## Unit tests verifying bear trap trigger interactions, damage, and immobilization timers.
class_name TestBearTrap
extends GutTest

## The [BearTrap] instance under test.
var bear_trap: BearTrap = null

## The mock player instance.
var mock_player: InnerMockPlayer = null


## Mock implementation of [Player] tracking damage and holding mock components.
class InnerMockPlayer:
	extends Player

	## Tracks the last damage value applied.
	var last_damage: int = 0

	## Initializes mock components for testing.
	func _init() -> void:
		locomotion_component = InnerMockLocomotion.new()
		system_menu = InnerMockMenu.new()

	## Simulates player damage.
	func take_damage(amount: int) -> void:
		print("TestBearTrap: InnerMockPlayer take_damage() called with: ", amount)
		last_damage = amount


## Mock locomotion component tracking sprint flags.
class InnerMockLocomotion:
	extends PlayerLocomotionComponent

	## Initializes default locomotion sprint state.
	func _init() -> void:
		can_sprint = true


## Mock system menu controller tracking stun status.
class InnerMockMenu:
	extends SystemMenuController

	## Initializes default menu stun state.
	func _init() -> void:
		is_stunned = false


## Sets up the bear trap and typed mock dependencies before each test.
func before_each() -> void:
	print("TestBearTrap: before_each() setup started.")

	var bear_trap_scene: PackedScene = load("res://enemies/bear_trap.tscn")
	bear_trap = bear_trap_scene.instantiate() as BearTrap
	add_child_autoqfree(bear_trap)

	mock_player = InnerMockPlayer.new()
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
