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
		
	# Tell the camera to detach from the body and go into free-look mode
	player.interaction_scanner.is_heavy_lifting = true

func exit() -> void:
	print("StateGlide: exit() called. Stowing glider.")
	if player.has_method("set_glider_visible"):
		player.set_glider_visible(false)
		
	player.interaction_scanner.is_heavy_lifting = false
		
	if is_instance_valid(player.weapon_holder):
		player.weapon_holder.rotation_degrees.z = 0.0
		player.weapon_holder.rotation.x = 0.0
		player.weapon_holder.rotation.y = 0.0
		
	# Snap the head back to a perfectly leveled center
	if is_instance_valid(player.head):
		player.head.rotation.y = 0.0
		player.head.rotation.z = 0.0 # Force clear any residual tilt

func physics_update(delta: float) -> void:
	# Separating logic into tightly scoped functions to maintain 60 FPS performance
	_apply_glide_physics(delta)
	_handle_debug_updraft()
	
	player.last_velocity = player.velocity
	player.move_and_slide()
	
	_check_transitions()
	_update_components(delta)

# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _apply_glide_physics(delta: float) -> void:
	player.velocity.y = move_toward(player.velocity.y, -max_fall_speed, player.gravity * delta)
	
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	
	# 1. Visually bank the glider
	_bank_glider(input_dir.x, delta)
	
	# 2. Steer the physical character body. This is what carves the circle!
	if input_dir.x != 0.0:
		player.rotate_y(-input_dir.x * turn_speed * delta)
	
	# 3. Lock the glider model to the body's rotation so it ignores the head's free-look
	if is_instance_valid(player.weapon_holder):
		player.weapon_holder.global_rotation.x = player.global_rotation.x
		player.weapon_holder.global_rotation.y = player.global_rotation.y
	
	# 4. Always fly straight relative to the newly rotated body
	var forward_dir: Vector3 = -player.global_transform.basis.z
	forward_dir.y = 0.0 
	forward_dir = forward_dir.normalized()
	
	# Notice we removed the "lateral" strafing math here. Gliders don't strafe, they steer!
	var target_vel: Vector3 = forward_dir * forward_speed
	
	player.velocity.x = lerpf(player.velocity.x, target_vel.x, delta * player.air_lerp_speed)
	player.velocity.z = lerpf(player.velocity.z, target_vel.z, delta * player.air_lerp_speed)


func _bank_glider(input_x: float, delta: float) -> void:
	if is_instance_valid(player.weapon_holder):
		var target_bank: float = -input_x * max_bank_angle
		player.weapon_holder.rotation_degrees.z = lerpf(
			player.weapon_holder.rotation_degrees.z, 
			target_bank, 
			delta * bank_lerp_speed
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
	player.interaction_scanner.process_interaction(delta)
