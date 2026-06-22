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
	print("StateGround: enter() called. Resetting Y velocity and current speed.")
	player.velocity.y = 0.0
	current_speed = 0.0 

	# Consume the buffer from StateAir and immediately jump!
	if msg.has("jump_buffered") and msg["jump_buffered"] == true:
		_perform_jump()
		return

func physics_update(delta: float) -> void:
	var loco: Node = player.locomotion_component
	var env: Node = player.environment_component

	if is_instance_valid(env.vault_controller) and env.vault_controller.get("is_vaulting"):
		return
		
	# 0. Slide Surface Detection
	for i: int in range(player.get_slide_collision_count()):
		var collision: KinematicCollision3D = player.get_slide_collision(i)
		var collider: Object = collision.get_collider()
		
		if collider is Node and collider.is_in_group("slide_surface"):
			print("StateGround: Slide surface detected via collision. Transitioning to Slide.")
			state_machine.transition_to("Slide")
			return
			
	# 1. State Transitions (Leaving the Ground)
	var is_recently_stepped: bool = loco.stair_controller.get("time_since_step_up") < 0.2
	var snapped_last_frame: bool = loco.stair_controller.get("_snapped_to_stairs_last_frame")
	
	# We ignore false negatives from is_on_floor if we are in the middle of a step traversal
	if not player.is_on_floor() and not snapped_last_frame and not is_recently_stepped:
		if env.current_water_node != null:
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
		var is_pressing_forward: bool = Input.is_action_pressed("forward")
		
		# Hard requirement: MUST be actively holding W. S bypasses vault.
		if is_pressing_forward and not snapped_last_frame and is_instance_valid(env.vault_controller) and env.vault_controller.try_vault(loco.crouching):
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
	loco.last_velocity = player.velocity

	# 6. Try snapping UP stairs
	loco.stair_controller.snap_up_stairs_check(delta, loco.sprint_active)

	# Move the Character (Normal movement)
	player.move_and_slide()

	# 7. Try snapping DOWN to keep the player grounded on descending stairs
	loco.stair_controller.snap_down_to_stairs_check()
	
	# 8. Keep track of floor timing for the next frame
	loco.stair_controller.track_floor_state()

	# 9. Update our decoupled components
	_update_components(delta, input_dir)


func _perform_jump() -> void:
	var loco: Node = player.locomotion_component
	
	if loco.sprint_active:
		player.velocity.y = SPRINT_JUMP_VELOCITY
	elif loco.crouching:
		player.velocity.y = CROUCH_JUMP_VELOCITY
	else:
		player.velocity.y = JUMP_VELOCITY

	print("StateGround: Executing jump. Velocity Y set to ", player.velocity.y)

	# Force a physics update right now so the engine registers we left the ground
	player.move_and_slide() 
	
	# Send the jump dictionary so StateAir knows this was intentional
	state_machine.transition_to("Air", {"jump": true})


func _calculate_target_speed(delta: float, input_dir: Vector2) -> void:
	var loco: Node = player.locomotion_component
	var env: Node = player.environment_component
	var interact: Node = player.interaction_component
	
	var previous_crouch: bool = loco.crouching
	var is_recently_stepped: bool = loco.stair_controller.get("time_since_step_up") < 0.2

	if Input.is_action_pressed("crouch"):
		loco.crouching = true
		loco.standing_collision.disabled = true
		loco.crouching_collision.disabled = false
		
		var target_depth: float = env.vault_controller.get("crouching_depth") if is_instance_valid(env.vault_controller) else 1.0
		loco.head.position.y = lerpf(loco.head.position.y, target_depth, delta * 15.0)
		
	elif not loco.crouch_cast_check.is_colliding():  
		loco.crouching = false
		loco.standing_collision.disabled = false
		loco.crouching_collision.disabled = true
		
		# THE FIX: Use a relaxed lerp (4.0) on stairs to glide, and standard (15.0) for flat ground
		var head_lerp: float = 4.0 if is_recently_stepped else 15.0
		loco.head.position.y = lerpf(loco.head.position.y, 1.8, delta * head_lerp)

	if previous_crouch != loco.crouching:
		Events.player_crouch_changed.emit(loco.crouching)
		print("StateGround: Player crouch state changed to ", loco.crouching)

	var is_moving: bool = input_dir.length() > 0.1
	loco.sprint_active = (
		Input.is_action_pressed("sprint")
		and not loco.crouching
		and is_moving
		and loco.can_sprint
	)

	var target_speed: float = loco.walking_speed
	if loco.sprint_active:
		target_speed = loco.sprinting_speed
	elif loco.crouching or interact.is_heavy_lifting:
		target_speed = loco.crouching_speed

	current_speed = lerpf(current_speed, target_speed, delta * 15.0)


func _apply_movement(delta: float, input_dir: Vector2) -> void:
	var loco: Node = player.locomotion_component
	var active_lerp: float = loco.ice_lerp_speed if loco.on_ice else loco.default_lerp_speed
	var target_dir: Vector3 = (
		(player.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	)

	loco.direction = loco.direction.lerp(target_dir, delta * active_lerp)

	# THE FIX: Enforce floor stickiness so the State Machine doesn't thrash.
	if player.is_on_floor():
		player.velocity.y = -0.1
	else:
		player.velocity.y -= loco.gravity * delta

	if input_dir != Vector2.ZERO or loco.on_ice:
		player.velocity.x = loco.direction.x * current_speed
		player.velocity.z = loco.direction.z * current_speed
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, current_speed)
		player.velocity.z = move_toward(player.velocity.z, 0.0, current_speed)
		loco.direction = Vector3.ZERO


func _update_components(delta: float, input_dir: Vector2) -> void:
	var loco: Node = player.locomotion_component
	var interact: Node = player.interaction_component

	# Tell the camera to handle headbobbing and FOV changes
	player.camera_controller.update_camera(
		delta, input_dir, loco.sprint_active, loco.crouching, true, player.velocity.length()
	)

	# Tell the audio manager to play footsteps
	loco.footstep_manager.process_surface_and_footsteps(
		delta, true, player.velocity.length(), loco.sprint_active, loco.crouching
	)
	loco.on_ice = loco.footstep_manager.get("is_on_ice")

	# Run the interaction raycast while on the ground
	if is_instance_valid(interact.interaction_scanner):
		interact.interaction_scanner.process_interaction(delta)

	# Push physical objects out of the way
	if is_instance_valid(loco.physics_pusher):
		loco.physics_pusher.process_pushes(
			interact.held_item, loco.last_velocity, loco.sprinting_speed
		)
