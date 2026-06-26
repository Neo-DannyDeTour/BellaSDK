class_name StateGlide
extends PlayerState

# --------------------------------------
# EXPORTS
# --------------------------------------
@export var forward_speed: float = 12.0
@export var max_fall_speed: float = 2.5
@export var debug_updraft_force: float = 15.0
@export var turn_speed: float = 2.0
@export var max_bank_angle: float = 15.0
@export var bank_lerp_speed: float = 5.0


# --------------------------------------
# STATE METHODS
# --------------------------------------
func enter(_msg: Dictionary = {}) -> void:
	print("StateGlide: enter() called. Deploying glider.")
	if player.has_method("set_glider_visible"):
		player.set_glider_visible(true)

	player.interaction_component.is_heavy_lifting = true


func exit() -> void:
	print("StateGlide: exit() called. Stowing glider.")
	if player.has_method("set_glider_visible"):
		player.set_glider_visible(false)

	var interact: Node = player.interaction_component
	interact.is_heavy_lifting = false

	# FIXED: Route weapon_holder through InteractionComponent
	if is_instance_valid(interact.weapon_holder):
		interact.weapon_holder.rotation_degrees.z = 0.0
		interact.weapon_holder.rotation.x = 0.0
		interact.weapon_holder.rotation.y = 0.0

	# FIXED: Route head reset through CameraController
	if is_instance_valid(player.camera_controller):
		player.camera_controller.camera.rotation.y = 0.0
		player.camera_controller.camera.rotation.z = 0.0


func physics_update(delta: float) -> void:
	# Separating logic into tightly scoped functions to maintain 60 FPS performance
	_apply_glide_physics(delta)
	_handle_debug_updraft()

	# FIXED: Route last_velocity to LocomotionComponent
	if is_instance_valid(player.locomotion_component):
		player.locomotion_component.last_velocity = player.velocity

	player.move_and_slide()

	_check_transitions()
	_update_components(delta)


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _apply_glide_physics(delta: float) -> void:
	var loco: Node = player.locomotion_component
	var interact: Node = player.interaction_component

	# FIXED: Route gravity to LocomotionComponent
	player.velocity.y = move_toward(player.velocity.y, -max_fall_speed, loco.gravity * delta)

	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	# 1. Visually bank the glider
	_bank_glider(input_dir.x, delta)

	# 2. Steer the physical character body. This is what carves the circle!
	if input_dir.x != 0.0:
		player.rotate_y(-input_dir.x * turn_speed * delta)

	# 3. Lock the glider model to the body's rotation so it ignores the head's free-look
	# FIXED: Route weapon_holder through InteractionComponent
	if is_instance_valid(interact.weapon_holder):
		interact.weapon_holder.global_rotation.x = player.global_rotation.x
		interact.weapon_holder.global_rotation.y = player.global_rotation.y

	# 4. Always fly straight relative to the newly rotated body
	var forward_dir: Vector3 = -player.global_transform.basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	var target_vel: Vector3 = forward_dir * forward_speed

	# FIXED: Route air_lerp_speed to LocomotionComponent
	player.velocity.x = lerpf(player.velocity.x, target_vel.x, delta * loco.air_lerp_speed)
	player.velocity.z = lerpf(player.velocity.z, target_vel.z, delta * loco.air_lerp_speed)


func _bank_glider(input_x: float, delta: float) -> void:
	var interact: Node = player.interaction_component

	# FIXED: Route weapon_holder through InteractionComponent
	if is_instance_valid(interact.weapon_holder):
		var target_bank: float = -input_x * max_bank_angle
		interact.weapon_holder.rotation_degrees.z = lerpf(
			interact.weapon_holder.rotation_degrees.z, target_bank, delta * bank_lerp_speed
		)


func _handle_debug_updraft() -> void:
	if Input.is_action_just_pressed("jump"):
		print("StateGlide: _handle_debug_updraft() triggered. Applying vertical force.")
		player.velocity.y = debug_updraft_force


func _check_transitions() -> void:
	if player.is_on_floor():
		print("StateGlide: _check_transitions() detected floor. Transitioning to Ground.")
		state_machine.transition_to("Ground")
		return

	# Allow the player to cancel the glide and drop normally
	if Input.is_action_just_pressed("crouch"):
		print("StateGlide: _check_transitions() detected crouch input. Cancelling glide.")
		state_machine.transition_to("Air")


func _update_components(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	player.camera_controller.update_camera(
		delta, input_dir, false, false, false, player.velocity.length()
	)

	player.interaction_component.process_interaction(delta)
