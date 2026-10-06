## Handles high-speed descent along fast-ropes with headbob VFX in [StateFastRope].
class_name StateFastRope
extends PlayerState

## Cached input vector simulating sprint forward motion for camera headbob.
var _fake_input: Vector2 = Vector2(0.0, 1.0)


## Halts momentum, disables stair snapping, and forces dropping heavy items.
func enter(_msg: Dictionary = {}) -> void:
	print("StateFastRope: enter() - Attaching to fast rope descent.")
	var p: Player = player as Player
	if not is_instance_valid(p):
		return

	p.velocity = Vector3.ZERO
	if "direction" in p:
		p.set(&"direction", Vector3.ZERO)

	var loco: PlayerLocomotionComponent = p.locomotion_component as PlayerLocomotionComponent
	if is_instance_valid(loco):
		if "direction" in loco:
			loco.set(&"direction", Vector3.ZERO)
		if is_instance_valid(loco.stair_controller):
			loco.stair_controller.set(&"is_enabled", false)

	var interact: PlayerInteractionComponent = p.interaction_component as PlayerInteractionComponent
	if is_instance_valid(interact) and is_instance_valid(interact.interaction_scanner):
		if bool(interact.interaction_scanner.get(&"is_heavy_lifting")):
			interact.interaction_scanner.call(&"drop_heavy_object_safely")


## Re-enables stair snapping controller on state exit.
func exit() -> void:
	print("StateFastRope: exit() - Detached from fast rope.")
	var p: Player = player as Player
	if not is_instance_valid(p):
		return

	var loco: PlayerLocomotionComponent = p.locomotion_component as PlayerLocomotionComponent
	if is_instance_valid(loco) and is_instance_valid(loco.stair_controller):
		loco.stair_controller.set(&"is_enabled", true)


## Simulates sprinting forward camera motion during fast-rope descent.
func physics_update(delta: float) -> void:
	print("StateFastRope: physics_update() - Simulating headbob camera descent.")
	var p: Player = player as Player
	if is_instance_valid(p) and is_instance_valid(p.camera_controller):
		p.camera_controller.update_camera(delta, _fake_input, true, false, false, 20.0)
