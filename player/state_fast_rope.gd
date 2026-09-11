## A player state that handles sliding down a fast rope.
##
## This state disables normal locomotion and gravity, allowing the player to slide down
## a fast rope while faking camera input for visual effects.
class_name StateFastRope
extends PlayerState


## Called by the [PlayerStateMachine] upon changing the active state.
##
## [param _msg] is a dictionary with arbitrary data the state can use to initialize itself.
## Kills momentum, disables the stair controller to prevent ground snapping, and forces
## dropping of heavy items.
func enter(_msg: Dictionary = {}) -> void:
	print("StateFastRope: enter() called. Entered fast rope state. Disabling StairController.")
	# 1. Kill all momentum instantly
	player.velocity = Vector3.ZERO
	player.direction = Vector3.ZERO

	# Disable StairController to prevent ground snapping
	if (
		is_instance_valid(player.locomotion_component)
		and is_instance_valid(player.locomotion_component.stair_controller)
	):
		player.locomotion_component.stair_controller.is_enabled = false

	# 2. Drop anything heavy we are holding so the animation doesn't break
	if player.interaction_scanner.is_heavy_lifting:
		player.interaction_scanner.drop_heavy_object_safely()


## Called by the [PlayerStateMachine] before changing the active state. Use this function
## to clean up the state.
##
## Restores the stair controller.
func exit() -> void:
	print("StateFastRope: exit() called. Exited fast rope state. Enabling StairController.")
	if (
		is_instance_valid(player.locomotion_component)
		and is_instance_valid(player.locomotion_component.stair_controller)
	):
		player.locomotion_component.stair_controller.is_enabled = true


## Corresponds to the [method _physics_process] callback.
##
## [param delta] The physics frame delta time.
## Notice we do NOT apply gravity, accept WASD input, or call [method move_and_slide].
## The [FastRope] Node in the world is taking complete control of [member global_position].
func physics_update(delta: float) -> void:
	# We fake a "sprinting forward" input specifically for the CameraController
	# to trigger the aggressive, high-speed headbobbing effect while sliding!
	var fake_input: Vector2 = Vector2(0.0, 1.0)

	player.camera_controller.update_camera(delta, fake_input, true, false, false, 20.0)
