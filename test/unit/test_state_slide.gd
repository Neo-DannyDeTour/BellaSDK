## Unit test suite validating StateSlide collision swapping and downhill momentum settings.
class_name TestStateSlide
extends GutTest

const STATE_SLIDE_SCRIPT: GDScript = preload("res://player/state_slide.gd")

## The slide state instance under test.
var state_slide: StateSlide = null

## The mock player instance.
var mock_player: MockPlayer = null

## The player state machine coordinator.
var state_machine: PlayerStateMachine = null

## Standing collision shape reference.
var standing_col: CollisionShape3D = null

## Crouching collision shape reference.
var crouching_col: CollisionShape3D = null

## Ceiling check raycast reference.
var crouch_cast: RayCast3D = null


## Sets up an isolated MockPlayer and StateSlide instance before each test.
func before_each() -> void:
	print("TestStateSlide: before_each() setup started.")
	mock_player = MockPlayer.new()
	add_child_autofree(mock_player)

	standing_col = CollisionShape3D.new()
	crouching_col = CollisionShape3D.new()
	crouch_cast = RayCast3D.new()

	mock_player.add_child(standing_col)
	mock_player.add_child(crouching_col)
	mock_player.add_child(crouch_cast)

	var loco: PlayerLocomotionComponent = mock_player.locomotion_component
	loco.standing_collision = standing_col
	loco.crouching_collision = crouching_col
	loco.crouch_cast_check = crouch_cast

	standing_col.disabled = false
	crouching_col.disabled = true
	loco.crouching = false

	state_machine = PlayerStateMachine.new()
	mock_player.add_child(state_machine)

	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	state_slide = STATE_SLIDE_SCRIPT.new() as StateSlide
	state_machine.add_child(state_slide)

	state_slide.state_machine = state_machine
	state_slide.player = mock_player
	state_machine.owner = mock_player


## Verifies default slide configuration tuning parameters.
func test_default_properties() -> void:
	print("TestStateSlide: test_default_properties() called.")
	assert_eq(state_slide.slide_acceleration, 15.0, "Slide acceleration should default to 15.0.")
	assert_eq(state_slide.max_slide_speed, 25.0, "Max slide speed should default to 25.0.")
	assert_eq(state_slide.slide_steering_speed, 8.0, "Slide steering should default to 8.0.")


## Verifies that entering slide switches collision shapes to crouched stance.
func test_enter_swaps_to_crouching_collision() -> void:
	print("TestStateSlide: test_enter_swaps_to_crouching_collision() called.")
	state_slide.enter({})

	var loco: PlayerLocomotionComponent = mock_player.locomotion_component
	assert_true(loco.crouching, "Player should be crouched when sliding.")
	assert_true(standing_col.disabled, "Standing collision must be disabled in slide.")
	assert_false(crouching_col.disabled, "Crouching collision must be active in slide.")


## Verifies that exiting slide restores standing collision when headroom is clear.
func test_exit_restores_standing_collision_when_clear() -> void:
	print("TestStateSlide: test_exit_restores_standing_collision_when_clear() called.")
	state_slide.enter({})
	state_slide.exit()

	var loco: PlayerLocomotionComponent = mock_player.locomotion_component
	assert_false(loco.crouching, "Player should stand up if ceiling is clear.")
	assert_false(standing_col.disabled, "Standing collision must be restored.")
	assert_true(crouching_col.disabled, "Crouching collision must be disabled.")
