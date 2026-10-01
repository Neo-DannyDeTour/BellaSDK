## Handles high-speed descent along fast-ropes with headbob VFX in [StateFastRope].
class_name StateFastRope
extends PlayerState

## Cached input vector simulating sprint forward motion for camera headbob.
var _fake_input: Vector2 = Vector2(0.0, 1.0)


## Halts momentum, disables stair snapping, and forces dropping heavy items.
func enter(_msg: Dictionary = {}) -> void:
	print("StateFastRope: enter() called. Player attaching to fast rope descent.")
	player.velocity = Vector3.ZERO
	player.direction = Vector3.ZERO

	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	if is_instance_valid(loco) and is_instance_valid(loco.stair_controller):
		loco.stair_controller.set(&"is_enabled", false)

	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)
	if is_instance_valid(interact) and is_instance_valid(interact.interaction_scanner):
		if bool(interact.interaction_scanner.get(&"is_heavy_lifting")):
			interact.interaction_scanner.call(&"drop_heavy_object_safely")


## Re-enables stair snapping controller on state exit.
func exit() -> void:
	print("StateFastRope: exit() called. Player detached from fast rope.")
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	if is_instance_valid(loco) and is_instance_valid(loco.stair_controller):
		loco.stair_controller.set(&"is_enabled", true)


## Simulates sprinting forward camera motion during fast-rope descent.
func physics_update(delta: float) -> void:
	print("StateFastRope: physics_update() simulating headbob camera descent.")
	player.camera_controller.update_camera(delta, _fake_input, true, false, false, 20.0)
