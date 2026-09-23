## Manages mid-air movement, variable gravity, coyote time, and jump buffering.
class_name StateAir
extends PlayerState

# --------------------------------------
# CONSTANTS & VARIABLES
# --------------------------------------
## Upward velocity applied when executing a standard jump.
const JUMP_VELOCITY: float = 4.5

## Upward velocity applied when jumping while sprinting.
const SPRINT_JUMP_VELOCITY: float = 5.0

## Upward velocity applied when jumping from crouched stance.
const CROUCH_JUMP_VELOCITY: float = 3.5

## Remaining time in seconds where ledge jump is still allowed.
var coyote_timer: float = 0.0

## Remaining time in seconds where jump input is cached for landing.
var jump_buffer_timer: float = 0.0

## Indicates whether jump impulse has executed in current air phase.
var has_jumped: bool = false

## Indicates whether airborne trajectory originated from a jump pad.
var is_launched: bool = false

## Specialized ascent gravity scalar applied during jump pad launches.
var launch_gravity: float = 9.8

## Specialized descent gravity scalar applied during jump pad launches.
var launch_fall_gravity: float = 9.8


## Initializes airborne state, processes knockback impulses, and sets timers.
## [param msg] Initialization data dictionary passed from the previous state.
func enter(msg: Dictionary = {}) -> void:
	print("StateAir: enter() called. Initializing air state.")
	has_jumped = msg.has("jump") and msg["jump"] == true

	if msg.has("knockback_force"):
		player.velocity = msg["knockback_force"] as Vector3
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		print("StateAir: Knockback applied with force: ", player.velocity)

	is_launched = msg.has("jump_pad") and msg["jump_pad"] == true
	if is_launched:
		print("StateAir: Player launched via jump pad.")
		launch_gravity = msg.get("launch_gravity", 9.8) as float
		launch_fall_gravity = msg.get("launch_fall_gravity", 9.8) as float

	var loco: Node = player.locomotion_component

	if msg.has("release_dir"):
		var r_dir: Vector3 = msg["release_dir"]
		loco.set_direction(Vector3(r_dir.x, 0.0, r_dir.z).normalized())
		print("StateAir: Inherited momentum direction from previous state.")

	if msg.has("coyote_time") and msg["coyote_time"] == true and not msg.has("knockback_force"):
		coyote_timer = loco.coyote_time_duration
	elif not msg.has("knockback_force"):
		coyote_timer = 0.0

	jump_buffer_timer = 0.0


## Applies gravity, mid-air steering, collision checks, and transitions.
## [param delta] The physics frame delta time in seconds.
func physics_update(delta: float) -> void:
	print("StateAir: physics_update() processing mid-air frame.")
	_handle_gravity(delta)
	_handle_timers(delta)

	if not is_launched:
		_handle_jump_input()

	var loco: Node = player.locomotion_component
	var env: Node = player.environment_component
	var input_dir: Vector2 = GestureInputManager.get_vector("left", "right", "forward", "backward")

	if env.in_updraft:
		loco.sprint_active = false
		loco.crouching = false

	# 1. Process standard or high-momentum air movement
	_apply_air_movement(delta, input_dir)

	# 2. Updraft steering boost
	if env.in_updraft and input_dir != Vector2.ZERO and not is_launched:
		var walk_dir: Vector3 = (
			(player.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		)
		player.velocity.x += walk_dir.x * 15.0 * delta
		player.velocity.z += walk_dir.z * 15.0 * delta

	loco.last_velocity = player.velocity
	player.move_and_slide()

	if is_launched and player.get_slide_collision_count() > 0:
		if not player.is_on_floor():
			is_launched = false
			print("StateAir: Collision detected mid-launch. Restoring air control.")

	_check_transitions()
	_update_components(delta, input_dir)
	_check_monkey_bar_grab()


## Applies gravity or updraft forces based on player state.
## [param delta] The physics frame delta time in seconds.
func _handle_gravity(delta: float) -> void:
	print("StateAir: _handle_gravity() applying vertical acceleration.")
	var loco: Node = player.locomotion_component
	var env: Node = player.environment_component

	if is_launched:
		if player.velocity.y < 0.0:
			player.velocity.y -= launch_fall_gravity * delta
		else:
			player.velocity.y -= launch_gravity * delta
		return

	if env.in_updraft:
		if player.is_on_ceiling():
			player.velocity.y = -0.1
		else:
			player.velocity.y = lerpf(player.velocity.y, env.updraft_strength, delta * 4.0)
	elif player.velocity.y < 0.0:
		player.velocity.y -= loco.gravity * loco.fall_gravity_multiplier * delta
	else:
		player.velocity.y -= loco.gravity * delta


## Decays coyote time and jump buffer timers.
## [param delta] The physics frame delta time in seconds.
func _handle_timers(delta: float) -> void:
	print("StateAir: _handle_timers() ticking countdowns.")
	if coyote_timer > 0.0:
		coyote_timer -= delta
	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta


## Processes mid-air jump inputs, enforcing heavy carry restrictions.
func _handle_jump_input() -> void:
	print("StateAir: _handle_jump_input() checking airborne jump requests.")
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)
	var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

	if GestureInputManager.is_action_just_pressed("jump"):
		print("StateAir: Jump input detected.")
		if is_holding_heavy:
			print("StateAir: Jump rejected. Object is too heavy (>= 10kg).")
			Events.hint_requested.emit("Cannot jump while carrying a heavy object.", 2.0)
			return

		if coyote_timer > 0.0 and not has_jumped:
			_perform_coyote_jump()
		else:
			print("StateAir: Jump input buffered.")
			jump_buffer_timer = loco.jump_buffer_duration


## Executes upward jump impulse when coyote time is active.
func _perform_coyote_jump() -> void:
	print("StateAir: Executing coyote jump.")
	has_jumped = true
	coyote_timer = 0.0

	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent

	if loco.sprint_active:
		player.velocity.y = SPRINT_JUMP_VELOCITY
	elif loco.crouching:
		player.velocity.y = CROUCH_JUMP_VELOCITY
	else:
		player.velocity.y = JUMP_VELOCITY


## Computes horizontal air steering and momentum damping.
## [param delta] The physics frame delta time in seconds.
## [param input_dir] Normalized 2D movement input vector.
func _apply_air_movement(delta: float, input_dir: Vector2) -> void:
	print("StateAir: _apply_air_movement() calculating horizontal air steering.")
	if is_launched:
		return

	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)
	var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

	var target_dir: Vector3 = (
		(player.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	)
	var horizontal_velocity: Vector2 = Vector2(player.velocity.x, player.velocity.z)
	var current_speed: float = horizontal_velocity.length()

	var max_air_speed: float = (
		loco.walking_speed * loco.heavy_carry_speed_mult if is_holding_heavy else loco.walking_speed
	)
	var steer_rate: float = loco.air_lerp_speed * 0.5 if is_holding_heavy else loco.air_lerp_speed

	# 1. High Momentum Handling (Rope / Swing Dismount)
	if current_speed > max_air_speed:
		var air_drag: float = 1.2
		horizontal_velocity = horizontal_velocity.lerp(Vector2.ZERO, air_drag * delta)

		if input_dir != Vector2.ZERO:
			var steer_vec: Vector2 = Vector2(target_dir.x, target_dir.z) * (max_air_speed * delta)
			horizontal_velocity += steer_vec
			loco.set_direction(loco.get_direction().lerp(target_dir, delta * steer_rate))

		player.velocity.x = horizontal_velocity.x
		player.velocity.z = horizontal_velocity.y
		return

	# 2. Standard Air Movement
	if input_dir != Vector2.ZERO:
		loco.set_direction(loco.get_direction().lerp(target_dir, delta * steer_rate))
		if current_speed < max_air_speed:
			current_speed = lerpf(current_speed, max_air_speed, delta * steer_rate)
	else:
		current_speed = lerpf(current_speed, 0.0, delta * steer_rate)

	player.velocity.x = loco.get_direction().x * current_speed
	player.velocity.z = loco.get_direction().z * current_speed


## Polls surface contacts, landing conditions, and ledge vaults.
func _check_transitions() -> void:
	print("StateAir: _check_transitions() checking state handoffs.")
	var env: Node = player.environment_component
	var interact: Node = player.interaction_component

	if player.is_on_floor() and player.velocity.y <= 0.0:
		_handle_landing()
		return

	if is_instance_valid(env.current_water_node) and player.velocity.y < -1.0:
		print("StateAir: Entering deep water.")
		state_machine.transition_to("Swim")
		return

	var is_holding_item: bool = is_instance_valid(interact.held_item)
	var is_pressing_forward: bool = GestureInputManager.is_action_pressed("forward")

	if (
		is_pressing_forward
		and player.velocity.y < 2.0
		and is_instance_valid(env.vault_controller)
		and not env.vault_controller.get("is_vaulting")
		and env.ladder_cooldown <= 0.2
	):
		if not is_holding_item:
			env.vault_controller.process_vault_scan()
			var jump_requested: bool = (
				GestureInputManager.is_action_just_pressed("jump") or jump_buffer_timer > 0.0
			)
			if jump_requested and env.vault_controller.get("can_vault_current_ledge"):
				var loco: PlayerLocomotionComponent = (
					player.locomotion_component as PlayerLocomotionComponent
				)
				if env.vault_controller.try_vault(loco.crouching):
					jump_buffer_timer = 0.0
					print("StateAir: Vaulting ledge on jump input.")
					state_machine.transition_to("Vault")
					return

	if is_holding_item and interact.held_item is GliderItem and player.velocity.y < 0.0:
		print("StateAir: Player is holding a GliderItem and falling. Transitioning to Glide.")
		state_machine.transition_to("Glide")
		return


## Processes ground collision, evaluates fall damage, and transitions.
func _handle_landing() -> void:
	print("StateAir: _handle_landing() called. Processing ground impact.")
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	var stats: Node = player.stats_component

	var impact_fall_speed: float = loco.last_velocity.y

	var is_safe_landing: bool = false
	var is_slide_surface: bool = false

	var slide_count: int = player.get_slide_collision_count()
	for i: int in range(slide_count):
		var collision: KinematicCollision3D = player.get_slide_collision(i)
		var collider: Object = collision.get_collider()

		if not collider is Node:
			continue

		if collision.get_normal().y > 0.1:
			if collider.is_in_group("safe_landing"):
				is_safe_landing = true

			var current_is_slide: bool = collider.is_in_group("slide_surface")
			if not current_is_slide:
				var parent_node: Node = collider.get_parent()
				if is_instance_valid(parent_node):
					current_is_slide = parent_node.is_in_group("slide_surface")

			if current_is_slide:
				is_slide_surface = true

	if impact_fall_speed <= -20.0 and is_instance_valid(stats.health_component):
		if is_safe_landing:
			print("StateAir: Impact neutralized by safe landing material.")
		else:
			print("StateAir: Heavy impact detected. Applying fall damage.")
			var max_hp: int = stats.health_component.get("max_health") as int
			stats.health_component.take_damage(max_hp)

	var msg: Dictionary = {"landing_speed": impact_fall_speed}

	if is_slide_surface:
		print("StateAir: Slide surface detected. Transitioning to Slide.")
		state_machine.transition_to("Slide", msg)
		return

	print("StateAir: Standard ground detected. Transitioning to Ground.")
	if jump_buffer_timer > 0.0:
		var interact: PlayerInteractionComponent = (
			player.interaction_component as PlayerInteractionComponent
		)
		var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying
		if not is_holding_heavy:
			msg["jump_buffered"] = true

	state_machine.transition_to("Ground", msg)


## Updates camera transforms and interaction scanner raycasts.
## [param delta] The physics frame delta time in seconds.
## [param input_dir] Normalized 2D movement input vector.
func _update_components(delta: float, input_dir: Vector2) -> void:
	print("StateAir: _update_components() polling camera and scanner.")
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)

	if is_instance_valid(player.camera_controller):
		player.camera_controller.update_camera(
			delta, input_dir, false, loco.crouching, false, player.velocity.length()
		)

	if is_instance_valid(interact.interaction_scanner):
		interact.interaction_scanner.process_interaction(delta)


## Checks for nearby monkey bar handles and transitions to [StateMonkeyBars].
func _check_monkey_bar_grab() -> void:
	print("StateAir: _check_monkey_bar_grab() checking grab targets.")
	var env: Node = player.environment_component

	if not is_instance_valid(env):
		return

	if is_instance_valid(env.available_monkey_bar) and env.monkey_bar_cooldown <= 0.0:
		print("StateAir: Grabbed monkey bar.")
		state_machine.transition_to("MonkeyBars", {"volume_node": env.available_monkey_bar})
