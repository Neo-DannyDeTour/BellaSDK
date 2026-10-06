## Manages mid-air movement, variable gravity, coyote time, and jump buffering in [StateAir].
class_name StateAir
extends PlayerState

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

## Reusable transition payload dictionary to eliminate runtime heap allocations.
var _transition_msg: Dictionary = {}


## Returns the owning player cast to concrete [Player] or null if invalid.
func _get_player() -> Player:
	return player as Player


## Initializes airborne state, processes knockback impulses, and sets timers.
func enter(msg: Dictionary = {}) -> void:
	print("StateAir: enter() called. Initializing air state.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	has_jumped = bool(msg.get(&"jump", false))

	if msg.has(&"knockback_force"):
		var force: Variant = msg[&"knockback_force"]
		if force is Vector3:
			p.velocity = force
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		print("StateAir: Knockback applied with force: ", p.velocity)

	is_launched = bool(msg.get(&"jump_pad", false))
	if is_launched:
		print("StateAir: Player launched via jump pad.")
		launch_gravity = float(msg.get(&"launch_gravity", 9.8))
		launch_fall_gravity = float(msg.get(&"launch_fall_gravity", 9.8))

	var loco: PlayerLocomotionComponent = p.locomotion_component

	if msg.has(&"release_dir"):
		var raw_release: Variant = msg[&"release_dir"]
		if raw_release is Vector3:
			var r_dir: Vector3 = raw_release
			loco.set_direction(Vector3(r_dir.x, 0.0, r_dir.z).normalized())
			print("StateAir: Inherited momentum direction from previous state.")

	var has_coyote: bool = bool(msg.get(&"coyote_time", false))
	if has_coyote and not msg.has(&"knockback_force"):
		coyote_timer = loco.coyote_time_duration
	elif not msg.has(&"knockback_force"):
		coyote_timer = 0.0

	jump_buffer_timer = 0.0


## Applies gravity, mid-air steering, collision checks, and transitions.
func physics_update(delta: float) -> void:
	print("StateAir: physics_update() processing mid-air frame.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	var loco: PlayerLocomotionComponent = p.locomotion_component
	var env: PlayerEnvironmentComponent = p.environment_component

	_handle_gravity(p, loco, env, delta)
	_handle_timers(delta)

	if not is_launched:
		_handle_jump_input(p, loco)

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	if env.in_updraft:
		loco.sprint_active = false
		loco.crouching = false

	_apply_air_movement(p, loco, delta, input_dir)

	if env.in_updraft and input_dir != Vector2.ZERO and not is_launched:
		var basis_dir: Vector3 = p.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
		var walk_dir: Vector3 = basis_dir.normalized()
		p.velocity.x += walk_dir.x * 15.0 * delta
		p.velocity.z += walk_dir.z * 15.0 * delta

	loco.last_velocity = p.velocity
	p.move_and_slide()

	if is_launched and p.get_slide_collision_count() > 0:
		if not p.is_on_floor():
			is_launched = false
			print("StateAir: Collision detected mid-launch. Restoring air control.")

	_check_transitions(p, loco, env)
	_update_components(p, loco, delta, input_dir)
	_check_monkey_bar_grab(env)


## Applies gravity or updraft forces based on environment context via [MathUtils].
func _handle_gravity(
	p: Player, loco: PlayerLocomotionComponent, env: PlayerEnvironmentComponent, delta: float
) -> void:
	print("StateAir: _handle_gravity() applying vertical acceleration.")
	if is_launched:
		if p.velocity.y < 0.0:
			p.velocity.y -= launch_fall_gravity * delta
		else:
			p.velocity.y -= launch_gravity * delta
		return

	if env.in_updraft:
		if p.is_on_ceiling():
			p.velocity.y = -0.1
		else:
			p.velocity.y = MathUtils.damp(p.velocity.y, env.updraft_strength, 4.0, delta)
	elif p.velocity.y < 0.0:
		p.velocity.y -= loco.gravity * loco.fall_gravity_multiplier * delta
	else:
		p.velocity.y -= loco.gravity * delta


## Decays coyote time and jump buffer timers by [param delta].
func _handle_timers(delta: float) -> void:
	print("StateAir: _handle_timers() ticking countdowns.")
	if coyote_timer > 0.0:
		coyote_timer -= delta
	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta


## Processes mid-air jump inputs, enforcing heavy carrying restrictions.
func _handle_jump_input(p: Player, loco: PlayerLocomotionComponent) -> void:
	print("StateAir: _handle_jump_input() checking airborne jump requests.")
	var interact: PlayerInteractionComponent = p.interaction_component
	var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

	if GestureInputManager.is_action_just_pressed(&"jump"):
		print("StateAir: Jump input detected.")
		if is_holding_heavy:
			print("StateAir: Jump rejected. Object is too heavy (>= 10kg).")
			Events.hint_requested.emit("Cannot jump while carrying a heavy object.", 2.0)
			return

		if coyote_timer > 0.0 and not has_jumped:
			_perform_coyote_jump(p, loco)
		else:
			print("StateAir: Jump input buffered.")
			jump_buffer_timer = loco.jump_buffer_duration


## Executes upward jump impulse when coyote time is active.
func _perform_coyote_jump(p: Player, loco: PlayerLocomotionComponent) -> void:
	print("StateAir: Executing coyote jump.")
	has_jumped = true
	coyote_timer = 0.0

	if loco.sprint_active:
		p.velocity.y = SPRINT_JUMP_VELOCITY
	elif loco.crouching:
		p.velocity.y = CROUCH_JUMP_VELOCITY
	else:
		p.velocity.y = JUMP_VELOCITY


## Computes horizontal air steering and momentum damping via [MathUtils].
func _apply_air_movement(
	p: Player, loco: PlayerLocomotionComponent, delta: float, input_dir: Vector2
) -> void:
	print("StateAir: _apply_air_movement() calculating horizontal air steering.")
	if is_launched:
		return

	var interact: PlayerInteractionComponent = p.interaction_component
	var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

	var target_dir: Vector3 = (
		(p.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	)
	var h_velocity: Vector2 = Vector2(p.velocity.x, p.velocity.z)
	var current_speed: float = h_velocity.length()

	var speed_mult: float = loco.heavy_carry_speed_mult if is_holding_heavy else 1.0
	var max_air_speed: float = loco.walking_speed * speed_mult
	var steer_rate: float = loco.air_lerp_speed * 0.5 if is_holding_heavy else loco.air_lerp_speed

	if current_speed > max_air_speed:
		var air_drag: float = 1.2
		h_velocity = MathUtils.damp_v2(h_velocity, Vector2.ZERO, air_drag, delta)

		if input_dir != Vector2.ZERO:
			var steer_vec: Vector2 = Vector2(target_dir.x, target_dir.z) * (max_air_speed * delta)
			h_velocity += steer_vec
			var blended_dir: Vector3 = MathUtils.damp_v3(
				loco.get_direction(), target_dir, steer_rate, delta
			)
			loco.set_direction(blended_dir)

		p.velocity.x = h_velocity.x
		p.velocity.z = h_velocity.y
		return

	if input_dir != Vector2.ZERO:
		var target_blended: Vector3 = MathUtils.damp_v3(
			loco.get_direction(), target_dir, steer_rate, delta
		)
		loco.set_direction(target_blended)
		if current_speed < max_air_speed:
			current_speed = MathUtils.damp(current_speed, max_air_speed, steer_rate, delta)
	else:
		current_speed = MathUtils.damp(current_speed, 0.0, steer_rate, delta)

	p.velocity.x = loco.get_direction().x * current_speed
	p.velocity.z = loco.get_direction().z * current_speed


## Polls surface contacts, landing conditions, water, and ledge vaults.
func _check_transitions(
	p: Player, loco: PlayerLocomotionComponent, env: PlayerEnvironmentComponent
) -> void:
	print("StateAir: _check_transitions() checking state handoffs.")
	var interact: PlayerInteractionComponent = p.interaction_component

	if p.is_on_floor() and p.velocity.y <= 0.0:
		_handle_landing(p, loco)
		return

	if is_instance_valid(env.current_water_node) and p.velocity.y < -1.0:
		print("StateAir: Entering deep water.")
		state_machine.transition_to(&"Swim")
		return

	var is_holding_item: bool = (
		is_instance_valid(interact) and is_instance_valid(interact.held_item)
	)
	var is_pressing_forward: bool = GestureInputManager.is_action_pressed(&"forward")

	var vault_ctrl: VaultController = (
		env.vault_controller as VaultController if is_instance_valid(env.vault_controller) else null
	)

	if (
		is_pressing_forward
		and p.velocity.y < 2.0
		and is_instance_valid(vault_ctrl)
		and not vault_ctrl.is_vaulting
		and env.ladder_cooldown <= 0.2
	):
		if not is_holding_item:
			vault_ctrl.process_vault_scan()
			var jump_req: bool = (
				GestureInputManager.is_action_just_pressed(&"jump") or jump_buffer_timer > 0.0
			)
			if jump_req and vault_ctrl.can_vault_current_ledge:
				if vault_ctrl.try_vault(loco.crouching):
					jump_buffer_timer = 0.0
					print("StateAir: Vaulting ledge on jump input.")
					state_machine.transition_to(&"Vault")
					return

	if is_holding_item and interact.held_item is GliderItem and p.velocity.y < 0.0:
		print("StateAir: Player holding GliderItem falling. Transition to Glide.")
		state_machine.transition_to(&"Glide")
		return


## Processes ground collision, evaluates fall damage, and triggers landing.
func _handle_landing(p: Player, loco: PlayerLocomotionComponent) -> void:
	print("StateAir: _handle_landing() called. Processing ground impact.")
	var stats: Node = p.get(&"stats_component") as Node

	var impact_fall_speed: float = loco.last_velocity.y
	var is_safe_landing: bool = false
	var is_slide_surface: bool = false

	var slide_count: int = p.get_slide_collision_count()
	for i: int in range(slide_count):
		var collision: KinematicCollision3D = p.get_slide_collision(i)
		var collider: Object = collision.get_collider()

		if not collider is Node:
			continue

		if collision.get_normal().y > 0.1:
			var node_col: Node = collider as Node
			if node_col.is_in_group(&"safe_landing"):
				is_safe_landing = true

			var current_is_slide: bool = node_col.is_in_group(&"slide_surface")
			if not current_is_slide:
				var parent_node: Node = node_col.get_parent()
				if is_instance_valid(parent_node):
					current_is_slide = parent_node.is_in_group(&"slide_surface")

			if current_is_slide:
				is_slide_surface = true

	var health_comp: Node = (
		stats.get(&"health_component") as Node if is_instance_valid(stats) else null
	)
	if impact_fall_speed <= -20.0 and is_instance_valid(health_comp):
		if is_safe_landing:
			print("StateAir: Impact neutralized by safe landing material.")
		else:
			print("StateAir: Heavy impact detected. Applying fall damage.")
			var max_hp_var: Variant = health_comp.get(&"max_health")
			var max_hp: int = int(max_hp_var) if max_hp_var != null else 0
			health_comp.call(&"take_damage", max_hp)

	_transition_msg.clear()
	_transition_msg[&"landing_speed"] = impact_fall_speed

	if is_slide_surface:
		print("StateAir: Slide surface detected. Transitioning to Slide.")
		state_machine.transition_to(&"Slide", _transition_msg)
		return

	print("StateAir: Standard ground detected. Transitioning to Ground.")
	if jump_buffer_timer > 0.0:
		var interact: PlayerInteractionComponent = p.interaction_component
		var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying
		if not is_holding_heavy:
			_transition_msg[&"jump_buffered"] = true

	state_machine.transition_to(&"Ground", _transition_msg)


## Updates camera transforms and interaction scanner raycasts.
func _update_components(
	p: Player, loco: PlayerLocomotionComponent, delta: float, input_dir: Vector2
) -> void:
	print("StateAir: _update_components() polling camera and scanner.")
	var interact: PlayerInteractionComponent = p.interaction_component
	var cam: CameraController = p.camera_controller as CameraController

	if is_instance_valid(cam):
		cam.update_camera(delta, input_dir, false, loco.crouching, false, p.velocity.length())

	if is_instance_valid(interact) and is_instance_valid(interact.interaction_scanner):
		interact.interaction_scanner.process_interaction(delta)


## Checks for nearby monkey bar handles and transitions to [StateMonkeyBars].
func _check_monkey_bar_grab(env: PlayerEnvironmentComponent) -> void:
	print("StateAir: _check_monkey_bar_grab() checking grab targets.")
	if not is_instance_valid(env):
		return

	if is_instance_valid(env.available_monkey_bar) and env.monkey_bar_cooldown <= 0.0:
		print("StateAir: Grabbed monkey bar.")
		_transition_msg.clear()
		_transition_msg[&"volume_node"] = env.available_monkey_bar
		state_machine.transition_to(&"MonkeyBars", _transition_msg)
