## Unit tests verifying bear trap trigger interactions, damage, and immobilization timers.
class_name TestBearTrap
extends GutTest

## The [BearTrap] instance under test.
var bear_trap: BearTrap = null

## The mock player instance.
var mock_player: MockPlayer = null


## Sets up the bear trap and typed mock dependencies before each test.
func before_each() -> void:
	print("TestBearTrap: before_each() setup started.")
	bear_trap = BearTrap.new()

	var left_pivot: Node3D = Node3D.new()
	left_pivot.name = "LeftJawPivot"
	bear_trap.add_child(left_pivot)

	var right_pivot: Node3D = Node3D.new()
	right_pivot.name = "RightJawPivot"
	bear_trap.add_child(right_pivot)

	var immob_timer: Timer = Timer.new()
	immob_timer.name = "ImmobilizeTimer"
	bear_trap.add_child(immob_timer)

	var sprint_timer: Timer = Timer.new()
	sprint_timer.name = "SprintBlockTimer"
	bear_trap.add_child(sprint_timer)

	add_child_autofree(bear_trap)

	mock_player = MockPlayer.new()
	add_child_autofree(mock_player)
	await get_tree().process_frame


## Validates initial trap state is set to OPEN.
func test_initial_state() -> void:
	print("TestBearTrap: test_initial_state() called.")
	assert_eq(
		bear_trap.current_state, BearTrap.TrapState.OPEN, "BearTrap should start in OPEN state."
	)


## Validates snapping logic, damage application, and state flags applied to player.
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

	var is_stunned_val: Variant = mock_player.system_menu.get("is_stunned")
	var is_stunned: bool = is_stunned_val is bool and is_stunned_val
	assert_true(is_stunned, "Player should be stunned.")

	assert_false(mock_player.locomotion_component.can_sprint, "Player sprint should be disabled.")
	assert_true(bear_trap.immobilize_timer.time_left > 0.0, "Immobilize timer should be started.")
	assert_true(
		bear_trap.sprint_block_timer.time_left > 0.0, "Sprint block timer should be started."
	)


## Validates timeouts resetting player state correctly after trap duration expires.
func test_timer_timeouts() -> void:
	print("TestBearTrap: test_timer_timeouts() called.")
	assert_not_null(bear_trap, "BearTrap instance must exist.")
	assert_not_null(mock_player, "MockPlayer instance must exist.")

	bear_trap.snap_shut(mock_player)
	assert_eq(bear_trap.trapped_player, mock_player, "Trapped player reference should be set.")

	bear_trap._on_immobilize_timeout()
	assert_not_null(mock_player.system_menu, "System menu must not be null.")

	var is_stunned_val: Variant = mock_player.system_menu.get("is_stunned")
	var is_stunned: bool = is_stunned_val is bool and is_stunned_val
	assert_false(is_stunned, "Player should not be stunned after immobilize timeout.")

	bear_trap._on_sprint_block_timeout()
	assert_not_null(mock_player.locomotion_component, "Locomotion component must not be null.")
	assert_true(
		mock_player.locomotion_component.can_sprint,
		"Player sprint should be enabled after sprint block timeout."
	)
	assert_null(bear_trap.trapped_player, "Trapped player reference should be cleared.")
