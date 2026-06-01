class_name StateGround
extends PlayerState

# --------------------------------------
# CONSTANTS & VARIABLES
# --------------------------------------
const JUMP_VELOCITY: float = 4.5
const CROUCH_JUMP_VELOCITY: float = 3.5
const SPRINT_JUMP_VELOCITY: float = 5.0

var current_speed: float = 0.0


func enter(msg: Dictionary = {}) -> void:
	player.velocity.y = 0.0

	# Consume the buffer from StateAir and immediately jump!
	if msg.has("jump_buffered") and msg["jump_buffered"] == true:
		_perform_jump()
		return

	# Sync UI and animations if necessary
	# Events.player_crouch_changed.emit(player.crouching)


func physics_update(delta: float) -> void:
	# 1. State Transitions (Leaving the Ground)
	if not player.is_on_floor():
		# If we walk off a ledge while wading, let the Swim state catch us
		if player.current_water_node != null:
			state_machine.transition_to("Swim")
			return

		# Standard cliff drop
		state_machine.transition_to("Air", {"coyote_time": true})
		return

	if Input.is_action_just_pressed("jump"):
		# Check if we should vault first (handled by our component!)
		if player.vault_controller.try_vault(player.crouching):
			state_machine.transition_to("Vault")
			return
		else:
			_perform_jump()
			return  # Exit early so we don't apply ground friction while jumping

	# 2. Read Inputs
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	# Handle Zoom (which forces walking/slow speed)
	if Input.is_action_pressed("zoom"):
		input_dir = Vector2.ZERO

	# 3. Determine Speed State
	_calculate_target_speed(delta, input_dir)

	# 4. Apply Physics (Momentum & Friction)
	_apply_movement(delta, input_dir)

	# Save velocity before we slide so the PhysicsPusher knows our speed!
	player.last_velocity = player.velocity

	# 5. Move the Character
	player.move_and_slide()

	# 6. Update our decoupled components!
	_update_components(delta, input_dir)


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _perform_jump() -> void:
	# CHANGE THIS LINE from player.sprinting to player.sprint_active:
	if player.sprint_active:
		player.velocity.y = SPRINT_JUMP_VELOCITY
	elif player.crouching:
		player.velocity.y = CROUCH_JUMP_VELOCITY
	else:
		player.velocity.y = JUMP_VELOCITY

	# player.camera_anims.play("jump")
	state_machine.transition_to("Air")


func _calculate_target_speed(delta: float, input_dir: Vector2) -> void:
	# Handle Crouching
	var previous_crouch: bool = player.crouching
	if Input.is_action_pressed("crouch"):
		player.crouching = true
		player.standing_collision.disabled = true
		player.crouching_collision.disabled = false
		player.head.position.y = lerpf(
			player.head.position.y, player.vault_controller.crouching_depth, delta * 15.0
		)
	elif not player.crouch_cast_check.is_colliding():  # Ensure headroom before standing up
		player.crouching = false
		player.standing_collision.disabled = false
		player.crouching_collision.disabled = true
		player.head.position.y = lerpf(player.head.position.y, 1.8, delta * 15.0)

	if previous_crouch != player.crouching:
		Events.player_crouch_changed.emit(player.crouching)

	# Handle Sprinting
	var is_moving: bool = input_dir.length() > 0.1
	player.sprint_active = (
		Input.is_action_pressed("sprint")
		and not player.crouching
		and is_moving
		and player.can_sprint
	)

	# Lerp target speed
	var target_speed: float = player.walking_speed
	if player.sprint_active:
		target_speed = player.sprinting_speed
	elif player.crouching or player.interaction_scanner.is_heavy_lifting:
		target_speed = player.crouching_speed

	current_speed = lerpf(current_speed, target_speed, delta * 15.0)


func _apply_movement(delta: float, input_dir: Vector2) -> void:
	var active_lerp: float = player.ice_lerp_speed if player.on_ice else player.default_lerp_speed
	var target_dir: Vector3 = (
		(player.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	)

	player.direction = player.direction.lerp(target_dir, delta * active_lerp)

	if input_dir != Vector2.ZERO or player.on_ice:
		player.velocity.x = player.direction.x * current_speed
		player.velocity.z = player.direction.z * current_speed
	else:
		# Snappy FPS stop when no input is given on normal ground
		player.velocity.x = move_toward(player.velocity.x, 0.0, current_speed)
		player.velocity.z = move_toward(player.velocity.z, 0.0, current_speed)
		player.direction = Vector3.ZERO


func _update_components(delta: float, input_dir: Vector2) -> void:
	# Tell the camera to handle headbobbing and FOV changes
	player.camera_controller.update_camera(
		delta, input_dir, player.sprint_active, player.crouching, true, player.velocity.length()  # is_grounded
	)

	# Tell the audio manager to play footsteps
	player.footstep_manager.process_surface_and_footsteps(
		delta, true, player.velocity.length(), player.sprint_active, player.crouching  # is_grounded
	)
	player.on_ice = player.footstep_manager.is_on_ice

	# Run the interaction raycast while on the ground!
	player.interaction_scanner.process_interaction(delta)

	# Push physical objects out of the way
	player.physics_pusher.process_pushes(
		player.interaction_scanner.held_object, player.last_velocity, player.sprinting_speed
	)
