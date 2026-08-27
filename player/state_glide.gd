## A player state that handles mid-air gliding mechanics.
##
## This state overrides typical air locomotion to provide forward thrust, slow falling,
## and banking rotation based on input, while stowing heavy objects.
class_name StateGlide
extends PlayerState

# --------------------------------------
# EXPORTS
# --------------------------------------
## Security variable: Indicates if debug commands (updraft) are allowed.
var is_debug_allowed: bool = OS.has_feature("debug")
## Base forward speed when gliding.
@export var forward_speed: float = 12.0
## Maximum downward velocity permitted while the glider is active.
@export var max_fall_speed: float = 2.5
## Upward impulse applied when jumping mid-glide (useful for debugging/testing).
@export var debug_updraft_force: float = 15.0
## Rotation speed scaler when turning the glider.
@export var turn_speed: float = 2.0
## Maximum visual banking angle (in degrees) when steering left or right.
@export var max_bank_angle: float = 15.0
## Speed at which the visual banking angle interpolates.
@export var bank_lerp_speed: float = 5.0

# --------------------------------------
# STATE METHODS
# --------------------------------------


## Activates the glider visuals and locks out heavy item interactions.
func enter(_msg: Dictionary = {}) -> void:
	print("StateGlide: enter() called. Deploying glider.")
	if player.has_method("set_glider_visible"):
		player.call("set_glider_visible", true)

	player.interaction_component.is_heavy_lifting = true


## Cleans up glider visuals, restores weapon transforms, and enables interactions.
func exit() -> void:
	print("StateGlide: exit() called. Stowing glider.")
	if player.has_method("set_glider_visible"):
		player.call("set_glider_visible", false)

	var interact: Node = player.interaction_component
	interact.is_heavy_lifting = false

	# FIXED: Route weapon_holder through InteractionComponent
	if is_instance_valid(interact.get("weapon_holder") as Node3D):
		var weapon_holder: Node3D = interact.get("weapon_holder") as Node3D
		weapon_holder.rotation_degrees.z = 0.0
		weapon_holder.rotation.x = 0.0
		weapon_holder.rotation.y = 0.0

	# FIXED: Route head reset through CameraController
	if is_instance_valid(player.camera_controller):
		player.camera_controller.camera.rotation.y = 0.0
		player.camera_controller.camera.rotation.z = 0.0


## Corresponds to `_physics_process()`. Applies glide physics and updates locomotion state.
func physics_update(delta: float) -> void:
	# Separating logic into tightly scoped functions to maintain 60 FPS performance
	_apply_glide_physics(delta)
	_handle_debug_updraft()

	# FIXED: Route last_velocity to LocomotionComponent
	if is_instance_valid(player.locomotion_component):
		player.locomotion_component.set("last_velocity", player.velocity)

	player.move_and_slide()

	_check_transitions()
	_update_components(delta)


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------


## Applies bespoke glide gravity, banking rotation, and forward momentum.
func _apply_glide_physics(delta: float) -> void:
	var loco: Node = player.locomotion_component
	var interact: Node = player.interaction_component

	# FIXED: Route gravity to LocomotionComponent
	var gravity: float = loco.get("gravity") if loco.get("gravity") != null else 9.8
	player.velocity.y = move_toward(player.velocity.y, -max_fall_speed, gravity * delta)

	var input_dir: Vector2 = GestureInputManager.get_vector("left", "right", "forward", "backward")

	# 1. Visually bank the glider
	_bank_glider(input_dir.x, delta)

	# 2. Steer the physical character body. This is what carves the circle!
	if input_dir.x != 0.0:
		player.rotate_y(-input_dir.x * turn_speed * delta)

	# 3. Lock the glider model to the body's rotation so it ignores the head's free-look
	# FIXED: Route weapon_holder through InteractionComponent
	if is_instance_valid(interact.get("weapon_holder") as Node3D):
		var weapon_holder: Node3D = interact.get("weapon_holder") as Node3D
		weapon_holder.global_rotation.x = player.global_rotation.x
		weapon_holder.global_rotation.y = player.global_rotation.y

	# 4. Always fly straight relative to the newly rotated body
	var forward_dir: Vector3 = -player.global_transform.basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	var target_vel: Vector3 = forward_dir * forward_speed

	# FIXED: Route air_lerp_speed to LocomotionComponent
	var air_lerp: float = loco.get("air_lerp_speed") if loco.get("air_lerp_speed") != null else 1.0
	player.velocity.x = lerpf(player.velocity.x, target_vel.x, delta * air_lerp)
	player.velocity.z = lerpf(player.velocity.z, target_vel.z, delta * air_lerp)


## Updates the visual Z-axis tilt of the weapon holder to simulate aerodynamic banking.
func _bank_glider(input_x: float, delta: float) -> void:
	var interact: Node = player.interaction_component

	# FIXED: Route weapon_holder through InteractionComponent
	if is_instance_valid(interact.get("weapon_holder") as Node3D):
		var weapon_holder: Node3D = interact.get("weapon_holder") as Node3D
		var target_bank: float = -input_x * max_bank_angle
		weapon_holder.rotation_degrees.z = lerpf(
			weapon_holder.rotation_degrees.z, target_bank, delta * bank_lerp_speed
		)


## Listens for the jump input to manually apply upward velocity.
func _handle_debug_updraft() -> void:
	if not is_debug_allowed:
		return

	if GestureInputManager.is_action_just_pressed("jump"):
		print("StateGlide: _handle_debug_updraft() triggered. Applying vertical force.")
		player.velocity.y = debug_updraft_force


## Evaluates floor collisions or cancel inputs to transition out of the glide state.
func _check_transitions() -> void:
	if player.is_on_floor():
		print("StateGlide: _check_transitions() detected floor. Transitioning to Ground.")
		state_machine.transition_to("Ground")
		return

	# Allow the player to cancel the glide and drop normally
	if GestureInputManager.is_action_just_pressed("crouch"):
		print("StateGlide: _check_transitions() detected crouch input. Cancelling glide.")
		state_machine.transition_to("Air")


## Ticks peripheral components like camera shaking and interaction scanning while gliding.
func _update_components(delta: float) -> void:
	var input_dir: Vector2 = GestureInputManager.get_vector("left", "right", "forward", "backward")

	player.camera_controller.update_camera(
		delta, input_dir, false, false, false, player.velocity.length()
	)

	# Safely route the interaction processing based on where the method currently lives
	var interact: Node = player.interaction_component
	if interact.has_method("process_interaction"):
		interact.call("process_interaction", delta)
	elif (
		interact.get("interaction_scanner")
		and interact.get("interaction_scanner").has_method("process_interaction")
	):
		interact.get("interaction_scanner").call("process_interaction", delta)
