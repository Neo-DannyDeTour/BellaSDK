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
	# 0. Slide Surface Detection
	for i: int in range(player.get_slide_collision_count()):
		var collision: KinematicCollision3D = player.get_slide_collision(i)
		var collider: Object = collision.get_collider()
		
		if collider is Node and collider.is_in_group("slide_surface"):
			print("StateGround: Slide surface detected via collision. Transitioning to Slide.")
			state_machine.transition_to("Slide")
			return
			
	# 1. State Transitions (Leaving the Ground)
	var is_recently_stepped: bool = player.stair_controller.time_since_step_up < 0.2
	
	# We ignore false negatives from is_on_floor if we are in the middle of a step traversal
	if not player.is_on_floor() and not player.stair_controller._snapped_to_stairs_last_frame and not is_recently_stepped:
		if player.current_water_node != null:
			print("StateGround: Transitioning to Swim.")
			state_machine.transition_to("Swim")
			return
			
		print("StateGround: Floor lost. Transitioning to Air.")
		state_machine.transition_to("Air", {"coyote_time": true})
		return

	# 2. Read Inputs FIRST
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	if Input.is_action_pressed("zoom"):
		input_dir = Vector2.ZERO

	# 3. Handle Jump / Vault Logic
	if Input.is_action_just_pressed("jump"):
		var is_on_stairs: bool = player.stair_controller._snapped_to_stairs_last_frame
		
		# Hard requirement: MUST be actively holding the forward action mapped key (W). 
		# Walking backwards (S) will completely bypass vault checks.
		var is_pressing_forward: bool = Input.is_action_pressed("forward")
		
		if is_pressing_forward and not is_on_stairs and player.vault_controller.try_vault(player.crouching):
			print("StateGround: Valid vault detected. Transitioning.")
			state_machine.transition_to("Vault")
			return
		else:
			_perform_jump()
			return

	# 4. Determine Speed State
	_calculate_target_speed(delta, input_dir)

	# 5. Apply Physics (Momentum & Friction)
	_apply_movement(delta, input_dir)
	player.last_velocity = player.velocity

	# 6. Try snapping UP stairs
	# Pass the sprint state to physically reach further and throttle camera shake
	player.stair_controller.snap_up_stairs_check(delta, player.sprint_active)

	# Move the Character (Normal movement)
	player.move_and_slide()

	# 7. Try snapping DOWN to keep the player grounded on descending stairs
	player.stair_controller.snap_down_to_stairs_check()
	
	# 8. Keep track of floor timing for the next frame
	player.stair_controller.track_floor_state()

	# 9. Update our decoupled components
	_update_components(delta, input_dir)


func _perform_jump() -> void:
	if player.sprint_active:
		player.velocity.y = SPRINT_JUMP_VELOCITY
	elif player.crouching:
		player.velocity.y = CROUCH_JUMP_VELOCITY
	else:
		player.velocity.y = JUMP_VELOCITY

	print("StateGround: Executing jump. Velocity Y set to ", player.velocity.y)

	# Force a physics update right now so the engine registers we left the ground
	player.move_and_slide() 
	
	# Send the jump dictionary so StateAir knows this was intentional
	state_machine.transition_to("Air", {"jump": true})


func _calculate_target_speed(delta: float, input_dir: Vector2) -> void:
	var previous_crouch: bool = player.crouching
	# Track if we are currently ascending stairs
	var is_recently_stepped: bool = player.stair_controller.time_since_step_up < 0.2

	if Input.is_action_pressed("crouch"):
		player.crouching = true
		player.standing_collision.disabled = true
		player.crouching_collision.disabled = false
		player.head.position.y = lerpf(
			player.head.position.y, player.vault_controller.crouching_depth, delta * 15.0
		)
	elif not player.crouch_cast_check.is_colliding():  
		player.crouching = false
		player.standing_collision.disabled = false
		player.crouching_collision.disabled = true
		
		# THE FIX: Use a relaxed lerp (4.0) on stairs to glide, and standard (15.0) for flat ground
		var head_lerp: float = 4.0 if is_recently_stepped else 15.0
		player.head.position.y = lerpf(player.head.position.y, 1.8, delta * head_lerp)

	if previous_crouch != player.crouching:
		Events.player_crouch_changed.emit(player.crouching)
		print("StateGround: Player crouch state changed to ", player.crouching)

	var is_moving: bool = input_dir.length() > 0.1
	player.sprint_active = (
		Input.is_action_pressed("sprint")
		and not player.crouching
		and is_moving
		and player.can_sprint
	)

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

	# THE FIX: Enforce floor stickiness so the State Machine doesn't thrash.
	if player.is_on_floor():
		player.velocity.y = -0.1
	else:
		player.velocity.y -= player.gravity * delta

	if input_dir != Vector2.ZERO or player.on_ice:
		player.velocity.x = player.direction.x * current_speed
		player.velocity.z = player.direction.z * current_speed
	else:
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
