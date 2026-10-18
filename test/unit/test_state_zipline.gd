## Unit test suite validating StateZipline payload verification, metrics, and dismount kinematics.
class_name TestStateZipline
extends GutTest

const STATE_ZIPLINE_SCRIPT: GDScript = preload("res://player/state_zipline.gd")

## The zipline state instance under test.
var state_zipline: StateZipline = null

## The mock player instance.
var mock_player: MockPlayer = null

## The player state machine coordinator.
var state_machine: PlayerStateMachine = null

## Mock destination state for Air fallback.
var air_state: MockAirState = null

## Mock zipline 3D node.
var mock_zip_node: Node3D = null


## Mock airborne state recording transitions from StateZipline.
class MockAirState:
	extends PlayerState

	## Records whether enter was invoked on this target state.
	var entered: bool = false

	## Marks state as entered.
	func enter(_msg: Dictionary = {}) -> void:
		print("MockAirState: enter() called.")
		entered = true


## Sets up an isolated MockPlayer and StateZipline instance before each test.
func before_each() -> void:
	print("TestStateZipline: before_each() setup started.")
	mock_player = MockPlayer.new()
	add_child_autofree(mock_player)

	mock_zip_node = Node3D.new()
	add_child_autofree(mock_zip_node)

	state_machine = PlayerStateMachine.new()
	mock_player.add_child(state_machine)

	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	state_zipline = STATE_ZIPLINE_SCRIPT.new() as StateZipline
	state_zipline.name = "Zipline"
	state_machine.add_child(state_zipline)

	air_state = MockAirState.new()
	air_state.name = "Air"
	state_machine.add_child(air_state)

	state_zipline.state_machine = state_machine
	state_zipline.player = mock_player
	state_machine.owner = mock_player

	state_machine._collect_states()


## Verifies default tuning constants for traverse speed, hang offset, and dismount boost.
func test_constants() -> void:
	print("TestStateZipline: test_constants() called.")
	assert_eq(StateZipline.ZIPLINE_SLIDE_SPEED, 8.0, "Slide speed constant must equal 8.0.")
	assert_eq(StateZipline.ZIPLINE_HANG_OFFSET, 2.0, "Hang offset constant must equal 2.0.")
	assert_eq(StateZipline.DETACH_MOMENTUM_MULTIPLIER, 1.1, "Detach boost constant must equal 1.1.")


## Verifies that entering with missing payload fields falls back immediately to Air.
func test_enter_missing_payload_transitions_to_air() -> void:
	print("TestStateZipline: test_enter_missing_payload_transitions_to_air() called.")
	state_zipline.enter({})

	assert_true(air_state.entered, "Incomplete payload must trigger fallback transition to Air.")


## Verifies that a valid payload calculates correct cable length and direction vectors.
func test_enter_valid_payload_configures_kinematics() -> void:
	print("TestStateZipline: test_enter_valid_payload_configures_kinematics() called.")
	var start_pt: Vector3 = Vector3(0.0, 10.0, 0.0)
	var end_pt: Vector3 = Vector3(0.0, 0.0, 20.0)
	var expected_len: float = start_pt.distance_to(end_pt)
	var expected_dir: Vector3 = (end_pt - start_pt).normalized()

	(
		state_zipline
		. enter(
			{
				&"zipline_node": mock_zip_node,
				&"start_pos": start_pt,
				&"end_pos": end_pt,
			}
		)
	)

	assert_eq(state_zipline.current_zipline, mock_zip_node, "Zipline node reference must match.")
	assert_almost_eq(state_zipline.zipline_length, expected_len, 0.001, "Length must be accurate.")
	assert_almost_eq(state_zipline.zipline_dir.x, expected_dir.x, 0.001, "Direction X must match.")
	assert_almost_eq(state_zipline.zipline_dir.y, expected_dir.y, 0.001, "Direction Y must match.")
	assert_almost_eq(state_zipline.zipline_dir.z, expected_dir.z, 0.001, "Direction Z must match.")
	assert_true(state_zipline.is_zipline_transitioning, "Must be in transitioning state.")


## Verifies that exiting state resets scaling, active node, and flags.
func test_exit_cleans_up_state() -> void:
	print("TestStateZipline: test_exit_cleans_up_state() called.")
	var start_pt: Vector3 = Vector3(0.0, 5.0, 0.0)
	var end_pt: Vector3 = Vector3(0.0, 0.0, 10.0)

	(
		state_zipline
		. enter(
			{
				&"zipline_node": mock_zip_node,
				&"start_pos": start_pt,
				&"end_pos": end_pt,
			}
		)
	)
	state_zipline.exit()

	assert_null(state_zipline.current_zipline, "Zipline node should be cleared on exit.")
	assert_false(state_zipline.is_zipline_transitioning, "Transition flag should be reset.")
	assert_eq(mock_player.scale, Vector3.ONE, "Player scale should be reset to Vector3.ONE.")
