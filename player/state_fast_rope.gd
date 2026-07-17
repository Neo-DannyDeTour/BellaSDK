class_name StateFastRope
extends PlayerState


func enter(_msg: Dictionary = {}) -> void:
	print("StateFastRope: enter() called. Entered fast rope state. Disabling StairController.")
	# 1. Kill all momentum instantly
	player.velocity = Vector3.ZERO
	player.direction = Vector3.ZERO

	# Disable StairController to prevent ground snapping
	if player.has_node("StairController"):
		player.get_node("StairController").is_enabled = false

	# 2. Drop anything heavy we are holding so the animation doesn't break
	if player.interaction_scanner.is_heavy_lifting:
		player.interaction_scanner.drop_heavy_object_safely()


# Add the exit function to re-enable stair handling
func exit() -> void:
	print("StateFastRope: exit() called. Exited fast rope state. Enabling StairController.")
	if player.has_node("StairController"):
		player.get_node("StairController").is_enabled = true


func physics_update(delta: float) -> void:
	# Notice we do NOT apply gravity, accept WASD input, or call move_and_slide().
	# The FastRope Node in the world is taking complete control of player.global_position.

	# We fake a "sprinting forward" input specifically for the CameraController
	# to trigger the aggressive, high-speed headbobting effect while sliding!
	var fake_input := Vector2(0.0, 1.0)

	player.camera_controller.update_camera(delta, fake_input, true, false, false, 20.0)
