class_name StateAir
extends PlayerState

# --------------------------------------
# CONSTANTS & VARIABLES
# --------------------------------------
## The upward velocity applied when executing a standard jump.
const JUMP_VELOCITY: float = 4.5

## The upward velocity applied when jumping while sprinting.
const SPRINT_JUMP_VELOCITY: float = 5.0

## The upward velocity applied when jumping from a crouched position.
const CROUCH_JUMP_VELOCITY: float = 3.5

## Tracks the remaining time the player is allowed to jump after walking off a ledge.
var coyote_timer: float = 0.0

## Tracks the remaining time a jump input is cached while falling towards the ground.
var jump_buffer_timer: float = 0.0

## Flags whether a jump has already been executed during this air phase to prevent double jumps.
var has_jumped: bool = false

## Flags whether the airborne trajectory was initiated by a jump pad or external force.
var is_launched: bool = false

## The specialized upward gravity force applied while ascending during a jump pad launch.
var launch_gravity: float = 9.8

## The specialized downward gravity force applied while descending during a jump pad launch.
var launch_fall_gravity: float = 9.8


func enter(msg: Dictionary = {}) -> void:
	print("StateAir: Entered air state.")
	has_jumped = msg.has("jump") and msg["jump"] == true

	# 1. Catch the knockback force and apply it immediately
	if msg.has("knockback_force"):
		player.velocity = msg["knockback_force"] as Vector3
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		print("StateAir: Knockback applied with force: ", player.velocity)

	is_launched = msg.has("jump_pad") and msg["jump_pad"] == true
	if is_launched:
		print("StateAir: Player is caught in a jump pad trajectory.")
		launch_gravity = msg.get("launch_gravity", 9.8) as float
		launch_fall_gravity = msg.get("launch_fall_gravity", 9.8) as float

	var loco: Node = player.locomotion_component

	# Inherit momentum direction from swinging ropes or fast-movement states
	if msg.has("release_dir"):
		var r_dir: Vector3 = msg["release_dir"]
		loco.set_direction(Vector3(r_dir.x, 0.0, r_dir.z).normalized())
		print("StateAir: Inherited momentum direction from previous state.")

	# Only grant Coyote Time if the player fell off a ledge AND wasn't knocked back
	if msg.has("coyote_time") and msg["coyote_time"] == true and not msg.has("knockback_force"):
		coyote_timer = loco.coyote_time_duration
	elif not msg.has("knockback_force"):
		coyote_timer = 0.0

	jump_buffer_timer = 0.0


func physics_update(delta: float) -> void:
	_handle_gravity(delta)
	_handle_timers(delta)

	if not is_launched:
		_handle_jump_input()

	var loco: Node = player.locomotion_component
	var env: Node = player.environment_component
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	if env.in_updraft:
		loco.sprint_active = false
		loco.crouching = false

	# 1. Process standard or high-momentum air movement
	_apply_air_movement(delta, input_dir)

	# 2. THE STEERING BOOST
	if env.in_updraft and input_dir != Vector2.ZERO and not is_launched:
		var walk_dir: Vector3 = (
			(player.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		)
		player.velocity.x += walk_dir.x * 15.0 * delta
		player.velocity.z += walk_dir.z * 15.0 * delta

	loco.last_velocity = player.velocity
	player.move_and_slide()

	# If launched and we hit a wall, break the launch lock to restore air control
	if is_launched and player.get_slide_collision_count() > 0:
		if not player.is_on_floor():
			is_launched = false
			print("StateAir: Collision detected mid-launch. Restoring air control.")

	_check_transitions()
	_update_components(delta, input_dir)
	_check_monkey_bar_grab()


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _handle_gravity(delta: float) -> void:
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


func _handle_timers(delta: float) -> void:
	if coyote_timer > 0.0:
		coyote_timer -= delta
	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta


func _handle_jump_input() -> void:
	var loco: Node = player.locomotion_component

	if Input.is_action_just_pressed("jump"):
		print("StateAir: Jump input detected.")
		if coyote_timer > 0.0 and not has_jumped:
			_perform_coyote_jump()
		else:
			print("StateAir: Jump input buffered.")
			jump_buffer_timer = loco.jump_buffer_duration


func _perform_coyote_jump() -> void:
	print("StateAir: Executing coyote jump.")
	has_jumped = true
	coyote_timer = 0.0

	var loco: Node = player.locomotion_component

	if loco.sprint_active:
		player.velocity.y = SPRINT_JUMP_VELOCITY
	elif loco.crouching:
		player.velocity.y = CROUCH_JUMP_VELOCITY
	else:
		player.velocity.y = JUMP_VELOCITY


func _apply_air_movement(delta: float, input_dir: Vector2) -> void:
	# Skip air drag and steering if we are locked in a jump pad arc
	if is_launched:
		return

	var loco: Node = player.locomotion_component
	var target_dir: Vector3 = (
		(player.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	)
	var horizontal_velocity: Vector2 = Vector2(player.velocity.x, player.velocity.z)
	var current_speed: float = horizontal_velocity.length()

	# 1. High Momentum Handling (Rope / Swing Dismount)
	if current_speed > loco.walking_speed:
		var air_drag: float = 1.2
		horizontal_velocity = horizontal_velocity.lerp(Vector2.ZERO, air_drag * delta)

		# Allow slight air-steering influence while retaining momentum
		if input_dir != Vector2.ZERO:
			var steer_vec: Vector2 = (
				Vector2(target_dir.x, target_dir.z) * (loco.walking_speed * delta)
			)
			horizontal_velocity += steer_vec
			loco.set_direction(loco.get_direction().lerp(target_dir, delta * loco.air_lerp_speed))

		player.velocity.x = horizontal_velocity.x
		player.velocity.z = horizontal_velocity.y
		return

	# 2. Standard Air Movement
	if input_dir != Vector2.ZERO:
		loco.set_direction(loco.get_direction().lerp(target_dir, delta * loco.air_lerp_speed))
		if current_speed < loco.walking_speed:
			current_speed = lerpf(current_speed, loco.walking_speed, delta * loco.air_lerp_speed)
	else:
		# Smoothly slow down horizontal drift if inputs are released
		current_speed = lerpf(current_speed, 0.0, delta * loco.air_lerp_speed)

	player.velocity.x = loco.get_direction().x * current_speed
	player.velocity.z = loco.get_direction().z * current_speed


func _check_transitions() -> void:
	var loco: Node = player.locomotion_component
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
	var is_pressing_forward: bool = Input.is_action_pressed("forward")

	# Enforce forward input requirement to prevent backwards mid-air vaulting
	if (
		is_pressing_forward
		and player.velocity.y < 2.0
		and is_instance_valid(env.vault_controller)
		and not env.vault_controller.get("is_vaulting")
		and env.ladder_cooldown <= 0.2
	):
		if not is_holding_item:
			env.vault_controller.process_vault_scan()
			if env.vault_controller.get("can_vault_current_ledge"):
				if env.vault_controller.try_vault(loco.crouching):
					print("StateAir: Vaulting ledge mid-air.")
					state_machine.transition_to("Vault")
					return

	if is_holding_item and interact.held_item is GliderItem and player.velocity.y < 0.0:
		print("StateAir: Player is holding a GliderItem and falling. Transitioning to Glide.")
		state_machine.transition_to("Glide")
		return


func _handle_landing() -> void:
	print("StateAir: _handle_landing() called. Processing ground impact.")
	var loco: Node = player.locomotion_component
	var stats: Node = player.stats_component

	var is_safe_landing: bool = false
	var is_slide_surface: bool = false

	# 1. Inspect the surface we just landed on
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

	# 2. Process Fall Damage
	if loco.last_velocity.y <= -20.0 and is_instance_valid(stats.health_component):
		if is_safe_landing:
			print(
				"StateAir: Heavy impact detected, but safe landing material neutralized fall damage."
			)
		else:
			print("StateAir: Heavy impact detected. Applying fall damage.")
			var max_hp: int = stats.health_component.get("max_health") as int
			stats.health_component.take_damage(max_hp)

	# 3. Transition State
	if is_slide_surface:
		print("StateAir: Slide surface detected. Transitioning to Slide.")
		state_machine.transition_to("Slide")
		return

	print("StateAir: Standard ground detected. Transitioning to Ground.")
	var msg: Dictionary = {}
	if jump_buffer_timer > 0.0:
		msg["jump_buffered"] = true

	state_machine.transition_to("Ground", msg)


func _update_components(delta: float, input_dir: Vector2) -> void:
	var loco: Node = player.locomotion_component
	var interact: Node = player.interaction_component

	if is_instance_valid(player.camera_controller):
		player.camera_controller.update_camera(
			delta, input_dir, false, loco.crouching, false, player.velocity.length()
		)

	if is_instance_valid(interact.interaction_scanner):
		interact.interaction_scanner.process_interaction(delta)


func _check_monkey_bar_grab() -> void:
	var env: Node = player.environment_component

	if not is_instance_valid(env):
		return

	if is_instance_valid(env.available_monkey_bar) and env.monkey_bar_cooldown <= 0.0:
		print("StateAir: Grabbed monkey bar.")
		state_machine.transition_to("MonkeyBars", {"volume_node": env.available_monkey_bar})
