class_name StateFastRope
extends PlayerState


func enter(_msg: Dictionary = {}) -> void:
	# 1. Kill all momentum instantly
	player.velocity = Vector3.ZERO
	player.direction = Vector3.ZERO

	# 2. Drop anything heavy we are holding so the animation doesn't break
	if player.interaction_scanner.is_heavy_lifting:
		player.interaction_scanner.drop_heavy_object_safely()


func physics_update(delta: float) -> void:
	# Notice we do NOT apply gravity, accept WASD input, or call move_and_slide().
	# The FastRope Node in the world is taking complete control of player.global_position.

	# We fake a "sprinting forward" input specifically for the CameraController
	# to trigger the aggressive, high-speed headbobting effect while sliding!
	var fake_input := Vector2(0.0, 1.0)

	player.camera_controller.update_camera(delta, fake_input, true, false, false, 20.0)  # is_sprinting (forces maximum headbob speed)  # is_crouching  # is_grounded  # Fake high velocity to scale the bob intensity
