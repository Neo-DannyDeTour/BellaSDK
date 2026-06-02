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
	has_jumped = msg.has("jump") and msg["jump"] == true

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

	# 1. Process your standard air movement first
	_apply_air_movement(delta, input_dir)

	# ---> 2. THE STEERING BOOST <---
	# If we are in the updraft and pressing WASD, give us extra horizontal push!
	if player.in_updraft and input_dir != Vector2.ZERO:
		# Get the direction the player is trying to walk based on where they are facing
		var walk_dir := (
			(player.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		)

		# Gently but firmly accelerate the player horizontally (15.0 is the push strength)
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
		# ---> CEILING FIX: Don't get friction-locked to the roof! <---
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
			# If we are too late for coyote time, save the input for a landing buffer!
			jump_buffer_timer = player.jump_buffer_duration


func _perform_coyote_jump() -> void:
	has_jumped = true
	coyote_timer = 0.0

	if player.sprint_active:
		player.velocity.y = SPRINT_JUMP_VELOCITY
	elif player.crouching:
		player.velocity.y = CROUCH_JUMP_VELOCITY
	else:
		player.velocity.y = JUMP_VELOCITY

	# player.camera_anims.play("jump")


func _apply_air_movement(delta: float, input_dir: Vector2) -> void:
	var target_dir: Vector3 = (
		(player.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	)

	# Only allow the player to steer if they are pressing keys
	if input_dir != Vector2.ZERO:
		player.direction = player.direction.lerp(target_dir, delta * player.air_lerp_speed)

	# Calculate the current flat speed (X and Z)
	var current_flat_speed: float = Vector2(player.velocity.x, player.velocity.z).length()

	# THE FIX: If the player is trying to move but has no speed (e.g., jumping from a standstill),
	# smoothly accelerate them up to their base walking speed mid-air.
	if input_dir != Vector2.ZERO and current_flat_speed < player.walking_speed:
		current_flat_speed = lerpf(
			current_flat_speed, player.walking_speed, delta * player.air_lerp_speed
		)

	player.velocity.x = player.direction.x * current_flat_speed
	player.velocity.z = player.direction.z * current_flat_speed


func _check_transitions() -> void:
	# 1. Landing on the floor
	# FIX: Ensure we are actively falling (velocity.y <= 0) before forcing a land.
	# This prevents instant jump-cancels from single-frame collision overlaps.
	if player.is_on_floor() and player.velocity.y <= 0.0:
		_handle_landing()
		return

	# 2. Catching deep water falls
	if player.current_water_node != null and player.velocity.y < -1.0:
		state_machine.transition_to("Swim")
		return

	# 3. Vaulting mid-air
	if player.velocity.y < 2.0 and not player.vault_controller.is_vaulting:
		player.vault_controller.process_vault_scan()
		if player.vault_controller.can_vault_current_ledge:
			if player.vault_controller.try_vault(player.crouching):
				state_machine.transition_to("Vault")
				return


func _handle_landing() -> void:
	# Calculate fall damage or landing animations based on impact speed
	if player.last_velocity.y <= -20.0:
		player.health_component.take_damage(player.health_component.max_health)
	elif player.last_velocity.y < -2.0:
		# CHANGE THIS LINE:
		if player.sprint_active:
			# player.camera_anims.play("jump_landing")
			pass
		else:
			# player.camera_anims.play("landing")
			pass

	# Package up our buffered jump to send back to StateGround
	var msg: Dictionary = {}
	if jump_buffer_timer > 0.0:
		msg["jump_buffered"] = true

	state_machine.transition_to("Ground", msg)


func _update_components(delta: float, input_dir: Vector2) -> void:
	player.camera_controller.update_camera(
		delta, input_dir, false, player.crouching, false, player.velocity.length()  # Can't trigger new sprint FOV in air  # is_grounded
	)

	# Keep scanning for interactables even while falling
	player.interaction_scanner.process_interaction(delta)


func _check_monkey_bar_grab() -> void:
	# 1. First, make sure the variables even exist on the player
	if not "available_monkey_bar" in player or not "monkey_bar_cooldown" in player:
		return

	# 2. Check if a bar is in reach, and our cooldown has finished ticking down
	if player.available_monkey_bar != null and player.monkey_bar_cooldown <= 0.0:
		# Optional: You can add height/velocity checks here later,
		# but for now, if we touch the box, we GRAB IT!
		state_machine.transition_to("MonkeyBars", {"volume_node": player.available_monkey_bar})
