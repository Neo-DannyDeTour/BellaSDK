## Unit test suite validating StateAir initialization, knockback, and coyote timing.
class_name TestStateAir
extends GutTest

const STATE_AIR_SCRIPT: GDScript = preload("res://player/state_air.gd")

## The airborne state instance under test.
var state_air: StateAir = null

## The mock player instance.
var mock_player: MockPlayer = null

## The player state machine coordinator.
var state_machine: PlayerStateMachine = null


## Sets up an isolated MockPlayer and StateAir instance before each test.
func before_each() -> void:
	print("TestStateAir: before_each() setup started.")
	mock_player = MockPlayer.new()
	add_child_autofree(mock_player)

	state_machine = PlayerStateMachine.new()
	mock_player.add_child(state_machine)

	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	state_air = STATE_AIR_SCRIPT.new() as StateAir
	state_machine.add_child(state_air)

	state_air.state_machine = state_machine
	state_air.player = mock_player
	state_machine.owner = mock_player


## Verifies default air state initialization when entered with an empty payload.
func test_enter_defaults() -> void:
	print("TestStateAir: test_enter_defaults() called.")
	state_air.enter({})

	assert_false(state_air.has_jumped, "Should not be marked as jumped by default.")
	assert_false(state_air.has_wolf_double_jumped, "Wolf double jump should be unconsumed.")
	assert_false(state_air.is_launched, "Launch flag should be false by default.")
	assert_eq(state_air.wall_coyote_timer, 0.0, "Wall coyote timer should default to 0.")


## Verifies that passing jump flag marks state as jumped.
func test_enter_with_jump_flag() -> void:
	print("TestStateAir: test_enter_with_jump_flag() called.")
	state_air.enter({&"jump": true})

	assert_true(state_air.has_jumped, "has_jumped should be true when jump flag passed.")


## Verifies that knockback parameters override velocity and clear coyote buffers.
func test_enter_with_knockback() -> void:
	print("TestStateAir: test_enter_with_knockback() called.")
	var knockback: Vector3 = Vector3(12.0, 6.0, -8.0)
	state_air.coyote_timer = 0.5
	state_air.jump_buffer_timer = 0.5

	state_air.enter({&"knockback_force": knockback})

	assert_eq(mock_player.velocity, knockback, "Player velocity should match knockback vector.")
	assert_eq(state_air.coyote_timer, 0.0, "Coyote timer should be cleared by knockback.")
	assert_eq(state_air.jump_buffer_timer, 0.0, "Jump buffer should be cleared by knockback.")


## Verifies that launch payloads configure timers and gravity overrides.
func test_enter_with_launch_payload() -> void:
	print("TestStateAir: test_enter_with_launch_payload() called.")
	(
		state_air
		. enter(
			{
				&"jump_pad": true,
				&"launch_duration": 1.25,
				&"launch_gravity": 14.0,
				&"launch_fall_gravity": 16.0,
			}
		)
	)

	assert_true(state_air.is_launched, "State should be marked as launched.")
	assert_eq(state_air.launch_timer, 1.25, "Launch duration timer should be armed.")
	assert_eq(state_air.launch_gravity, 14.0, "Ascent launch gravity should match payload.")
	assert_eq(state_air.launch_fall_gravity, 16.0, "Descent launch gravity should match payload.")


## Verifies that wall coyote entry caches wall normals, direction, and countdown window.
func test_enter_with_wall_coyote() -> void:
	print("TestStateAir: test_enter_with_wall_coyote() called.")
	var normal: Vector3 = Vector3.LEFT
	var heading: Vector3 = Vector3.FORWARD

	(
		state_air
		. enter(
			{
				&"wall_coyote": true,
				&"wall_normal": normal,
				&"wall_run_dir": heading,
			}
		)
	)

	assert_eq(state_air.wall_coyote_timer, 0.25, "Wall coyote timer should be set to 0.25s.")
	assert_eq(state_air.cached_wall_normal, normal, "Wall normal should be cached.")
	assert_eq(state_air.cached_wall_run_dir, heading, "Wall run direction should be cached.")


## Verifies standard coyote time initialization from locomotion component duration.
func test_enter_with_coyote_time() -> void:
	print("TestStateAir: test_enter_with_coyote_time() called.")
	mock_player.locomotion_component.coyote_time_duration = 0.2

	state_air.enter({&"coyote_time": true})

	assert_eq(state_air.coyote_timer, 0.2, "Coyote timer should initialize from locomotion.")
