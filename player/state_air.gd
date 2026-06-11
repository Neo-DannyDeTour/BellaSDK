class_name StateAir
extends PlayerState

# --------------------------------------
# CONSTANTS & VARIABLES
# --------------------------------------
const JUMP_VELOCITY: float = 4.5
const SPRINT_JUMP_VELOCITY: float = 5.0
const CROUCH_JUMP_VELOCITY: float = 3.5

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var has_jumped: bool = false


func enter(msg: Dictionary = {}) -> void:
	print("StateAir: Entered air state.")
	has_jumped = msg.has("jump") and msg["jump"] == true

	# Inherit momentum direction from swinging ropes or fast-movement states
	if msg.has("release_dir"):
		var r_dir: Vector3 = msg["release_dir"]
		player.direction = Vector3(r_dir.x, 0.0, r_dir.z).normalized()
		print("StateAir: Inherited momentum direction from previous state.")

	# Only grant Coyote Time if the player fell off a ledge (didn't jump)
	if msg.has("coyote_time") and msg["coyote_time"] == true:
		coyote_timer = player.coyote_time_duration
	else:
		coyote_timer = 0.0

	jump_buffer_timer = 0.0


func physics_update(delta: float) -> void:
	_handle_gravity(delta)
	_handle_timers(delta)
	_handle_jump_input()

	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	if player.in_updraft:
		player.sprint_active = false
		player.crouching = false

	# 1. Process standard or high-momentum air movement
	_apply_air_movement(delta, input_dir)

	# 2. THE STEERING BOOST
	if player.in_updraft and input_dir != Vector2.ZERO:
		var walk_dir := (
			(player.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		)
		player.velocity.x += walk_dir.x * 15.0 * delta
		player.velocity.z += walk_dir.z * 15.0 * delta

	player.last_velocity = player.velocity
	player.move_and_slide()

	_check_transitions()
	_update_components(delta, input_dir)
	_check_monkey_bar_grab()


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _handle_gravity(delta: float) -> void:
	if player.in_updraft:
		if player.is_on_ceiling():
			player.velocity.y = -0.1
		else:
			player.velocity.y = lerpf(player.velocity.y, player.updraft_strength, delta * 4.0)

	elif player.velocity.y < 0.0:
		player.velocity.y -= player.gravity * player.fall_gravity_multiplier * delta
	else:
		player.velocity.y -= player.gravity * delta


func _handle_timers(delta: float) -> void:
	if coyote_timer > 0.0:
		coyote_timer -= delta
	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta


func _handle_jump_input() -> void:
	if Input.is_action_just_pressed("jump"):
		if coyote_timer > 0.0 and not has_jumped:
			_perform_coyote_jump()
		else:
			jump_buffer_timer = player.jump_buffer_duration


func _perform_coyote_jump() -> void:
	print("StateAir: Executing coyote jump.")
	has_jumped = true
	coyote_timer = 0.0

	if player.sprint_active:
		player.velocity.y = SPRINT_JUMP_VELOCITY
	elif player.crouching:
		player.velocity.y = CROUCH_JUMP_VELOCITY
	else:
		player.velocity.y = JUMP_VELOCITY


func _apply_air_movement(delta: float, input_dir: Vector2) -> void:
	var target_dir: Vector3 = (
		(player.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	)
	var horizontal_velocity := Vector2(player.velocity.x, player.velocity.z)
	var current_speed: float = horizontal_velocity.length()

	# 1. High Momentum Handling (Rope / Swing Dismount)
	if current_speed > player.walking_speed:
		var air_drag: float = 1.2
		horizontal_velocity = horizontal_velocity.lerp(Vector2.ZERO, air_drag * delta)
		
		# Allow slight air-steering influence while retaining momentum
		if input_dir != Vector2.ZERO:
			var steer_vec: Vector2 = Vector2(target_dir.x, target_dir.z) * (player.walking_speed * delta)
			horizontal_velocity += steer_vec
			player.direction = player.direction.lerp(target_dir, delta * player.air_lerp_speed)
			
		player.velocity.x = horizontal_velocity.x
		player.velocity.z = horizontal_velocity.y
		return

	# 2. Standard Air Movement
	if input_dir != Vector2.ZERO:
		player.direction = player.direction.lerp(target_dir, delta * player.air_lerp_speed)
		if current_speed < player.walking_speed:
			current_speed = lerpf(
				current_speed, player.walking_speed, delta * player.air_lerp_speed
			)
	else:
		# Smoothly slow down horizontal drift if inputs are released
		current_speed = lerpf(current_speed, 0.0, delta * player.air_lerp_speed)

	player.velocity.x = player.direction.x * current_speed
	player.velocity.z = player.direction.z * current_speed


func _check_transitions() -> void:
	if player.is_on_floor() and player.velocity.y <= 0.0:
		_handle_landing()
		return

	if player.current_water_node != null and player.velocity.y < -1.0:
		print("StateAir: Entering deep water.")
		state_machine.transition_to("Swim")
		return

	if player.velocity.y < 2.0 and not player.vault_controller.is_vaulting:
		player.vault_controller.process_vault_scan()
		if player.vault_controller.can_vault_current_ledge:
			if player.vault_controller.try_vault(player.crouching):
				print("StateAir: Vaulting ledge mid-air.")
				state_machine.transition_to("Vault")
				return
	
	# Transition to Glide if holding the glider and falling
	if player.held_item is GliderItem and player.velocity.y < 0.0:
		print("StateAir: Player is holding a GliderItem and falling. Transitioning to Glide.")
		state_machine.transition_to("Glide")
		return

func _handle_landing() -> void:
	print("StateAir: Player landed. Impact velocity: ", player.last_velocity.y)
	
	if player.last_velocity.y <= -20.0:
		player.health_component.take_damage(player.health_component.max_health)

	# 1. Intercept the landing to check for a slide surface
	for i: int in range(player.get_slide_collision_count()):
		var collision: KinematicCollision3D = player.get_slide_collision(i)
		var collider: Object = collision.get_collider()
		
		# ADD THIS DEBUG PRINT:
		print("Debug - Collided with node: ", collider.name, " | Groups: ", collider.get_groups())
		
		if collider is Node and collider.is_in_group("slide_surface"):
			print("StateAir: Slide surface detected on landing. Transitioning to StateSlide.")
			state_machine.transition_to("Slide")
			return

	# 2. If no slide surface is found, proceed to Ground normally
	var msg: Dictionary = {}
	if jump_buffer_timer > 0.0:
		msg["jump_buffered"] = true

	state_machine.transition_to("Ground", msg)


func _update_components(delta: float, input_dir: Vector2) -> void:
	player.camera_controller.update_camera(
		delta, input_dir, false, player.crouching, false, player.velocity.length()
	)
	player.interaction_scanner.process_interaction(delta)


func _check_monkey_bar_grab() -> void:
	if not "available_monkey_bar" in player or not "monkey_bar_cooldown" in player:
		return

	if player.available_monkey_bar != null and player.monkey_bar_cooldown <= 0.0:
		print("StateAir: Grabbed monkey bar.")
		state_machine.transition_to("MonkeyBars", {"volume_node": player.available_monkey_bar})
