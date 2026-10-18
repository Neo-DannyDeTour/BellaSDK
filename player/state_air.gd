## Manages mid-air movement, gravity, double jumps, and buffering.
class_name StateAir
extends PlayerState

## Upward velocity applied when executing a standard jump.
const JUMP_VELOCITY: float = 4.5

## Upward velocity applied when jumping while sprinting.
const SPRINT_JUMP_VELOCITY: float = 5.0

## Upward velocity applied when jumping from crouched stance.
const CROUCH_JUMP_VELOCITY: float = 3.5

## Upward velocity applied when executing wolf double jump.
const WOLF_DOUBLE_JUMP_VELOCITY: float = 7.0

## Group identifier for wolf climbable surfaces.
const GROUP_WOLF_CLIMBABLE: StringName = &"wolf_climbable"

## Group identifier for fall-damage-negating surfaces.
const GROUP_SAFE_LANDING: StringName = &"safe_landing"

## Group identifier for slide surfaces.
const GROUP_SLIDE: StringName = &"slide_surface"

## State identifier for grounded movement.
const STATE_GROUND: StringName = &"Ground"

## State identifier for sliding.
const STATE_SLIDE: StringName = &"Slide"

## State identifier for swimming.
const STATE_SWIM: StringName = &"Swim"

## State identifier for ledge vaulting.
const STATE_VAULT: StringName = &"Vault"

## State identifier for gliding.
const STATE_GLIDE: StringName = &"Glide"

## State identifier for monkey bar traversal.
const STATE_MONKEY_BARS: StringName = &"MonkeyBars"

## State identifier for wolf climbing.
const STATE_WOLF_CLIMB: StringName = &"WolfClimb"

## Remaining time in seconds where ledge jump is still allowed.
var coyote_timer: float = 0.0

## Remaining time in seconds where jump input is cached for landing.
var jump_buffer_timer: float = 0.0

## Coyote time remaining after running off a wall run surface.
var wall_coyote_timer: float = 0.0

## Normal vector cached from wall dismount for late jumps.
var cached_wall_normal: Vector3 = Vector3.ZERO

## Heading vector cached from wall dismount for late jumps.
var cached_wall_run_dir: Vector3 = Vector3.ZERO

## Indicates whether jump impulse has executed in current air phase.
var has_jumped: bool = false

## Tracks whether wolf mid-air double jump has been consumed.
var has_wolf_double_jumped: bool = false

## Indicates whether airborne trajectory originated from a launch.
var is_launched: bool = false

## Countdown timer preserving high-speed launch momentum.
var launch_timer: float = 0.0

## Specialized ascent gravity scalar applied during launches.
var launch_gravity: float = 9.8

## Specialized descent gravity scalar applied during launches.
var launch_fall_gravity: float = 9.8

## Reusable transition payload dictionary.
var _transition_msg: Dictionary = {}

## Cached player RID exclusion array for forward wall raycasts.
var _exclude_rids: Array[RID] = []


## Initializes airborne state, processes launches, and sets timers.
func enter(msg: Dictionary = {}) -> void:
	print("StateAir: enter() called. Initializing air state.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	if _exclude_rids.is_empty():
		_exclude_rids = [p.get_rid()]

	has_jumped = msg.get(&"jump", false) == true
	has_wolf_double_jumped = false
	wall_coyote_timer = 0.0

	if msg.get(&"wall_coyote", false) == true:
		wall_coyote_timer = 0.25
		cached_wall_normal = msg.get(&"wall_normal", Vector3.ZERO) as Vector3
		cached_wall_run_dir = msg.get(&"wall_run_dir", Vector3.ZERO) as Vector3
		print("StateAir: Wall coyote window armed for 15m jump.")

	if msg.has(&"knockback_force"):
		var force: Variant = msg[&"knockback_force"]
		if force is Vector3:
			p.velocity = force
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		print("StateAir: Knockback applied with force: ", p.velocity)

	is_launched = (
		msg.get(&"jump_pad", false) == true or msg.get(&"wall_jump_launch", false) == true
	)
	if is_launched:
		print("StateAir: Player launched with preserved high-speed arc.")
		launch_timer = msg.get(&"launch_duration", 0.85) as float
		launch_gravity = msg.get(&"launch_gravity", 9.8) as float
		launch_fall_gravity = msg.get(&"launch_fall_gravity", 9.8) as float

	var loco: PlayerLocomotionComponent = p.locomotion_component

	if msg.has(&"release_dir"):
		var raw_release: Variant = msg[&"release_dir"]
		if raw_release is Vector3:
			var r_dir: Vector3 = raw_release
			loco.set_direction(Vector3(r_dir.x, 0.0, r_dir.z).normalized())
			print("StateAir: Inherited momentum direction from previous state.")

	var has_coyote: bool = msg.get(&"coyote_time", false) == true
	if has_coyote and not msg.has(&"knockback_force"):
		coyote_timer = loco.coyote_time_duration
	elif not msg.has(&"knockback_force"):
		coyote_timer = 0.0

	jump_buffer_timer = 0.0


## Applies gravity, mid-air steering, collisions, and transitions.
func physics_update(delta: float) -> void:
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	var loco: PlayerLocomotionComponent = p.locomotion_component
	var env: PlayerEnvironmentComponent = p.environment_component

	_handle_gravity(p, loco, env, delta)
	_handle_timers(delta)
	_handle_jump_input(p, loco)

	var input_dir: Vector2 = GestureInputManager.get_vector(
		ACTION_LEFT, ACTION_RIGHT, ACTION_FORWARD, ACTION_BACKWARD
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

	if is_launched and launch_timer <= 0.0 and p.get_slide_collision_count() > 0:
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


## Decays coyote time, launch timers, and jump buffer timers.
func _handle_timers(delta: float) -> void:
	if coyote_timer > 0.0:
		coyote_timer -= delta
	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta
	if wall_coyote_timer > 0.0:
		wall_coyote_timer -= delta
	if launch_timer > 0.0:
		launch_timer -= delta
		if launch_timer <= 0.0:
			is_launched = false


## Processes mid-air jump and wolf double jump inputs.
func _handle_jump_input(p: Player, loco: PlayerLocomotionComponent) -> void:
	var interact: PlayerInteractionComponent = p.interaction_component
	var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

	var is_jump_pressed: bool = (
		GestureInputManager.is_action_just_pressed(ACTION_JUMP)
		or GestureInputManager.is_action_just_triggered(ACTION_JUMP)
	)

	if is_jump_pressed:
		print("StateAir: Jump input detected.")
		if is_holding_heavy:
			print("StateAir: Jump rejected. Object is too heavy (>= 10kg).")
			Events.hint_requested.emit("Cannot jump while carrying a heavy object.", 2.0)
			return

		if wall_coyote_timer > 0.0:
			_perform_wall_coyote_jump(p)
		elif coyote_timer > 0.0 and not has_jumped:
			_perform_coyote_jump(p, loco)
		elif p.is_wolf_mode and not has_wolf_double_jumped:
			_perform_wolf_double_jump(p, loco)
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


## Executes late wall jump when running off surface edge.
func _perform_wall_coyote_jump(p: Player) -> void:
	print("StateAir: Executing late wall run coyote dismount jump!")
	wall_coyote_timer = 0.0
	has_jumped = true
	is_launched = true
	launch_timer = 0.85

	p.global_position += cached_wall_normal * 0.35
	var kick_dir: Vector3 = (cached_wall_normal * 1.5 + cached_wall_run_dir * 0.7).normalized()
	p.velocity = kick_dir * 20.0
	p.velocity.y = 7.5


## Executes mid-air double jump leap exclusive to wolf mode.
func _perform_wolf_double_jump(p: Player, loco: PlayerLocomotionComponent) -> void:
	print("StateAir: Executing wolf form mid-air double jump!")
	has_wolf_double_jumped = true
	has_jumped = true
	is_launched = false
	launch_timer = 0.0

	p.velocity.y = WOLF_DOUBLE_JUMP_VELOCITY

	var input_dir: Vector2 = GestureInputManager.get_vector(
		ACTION_LEFT, ACTION_RIGHT, ACTION_FORWARD, ACTION_BACKWARD
	)

	var leap_dir: Vector3 = Vector3.ZERO
	if input_dir != Vector2.ZERO:
		leap_dir = (p.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	else:
		leap_dir = -p.global_transform.basis.z.normalized()

	var double_jump_speed: float = maxf(p.velocity.length(), loco.sprinting_speed * 1.25)
	p.velocity.x = leap_dir.x * double_jump_speed
	p.velocity.z = leap_dir.z * double_jump_speed
	loco.set_direction(leap_dir)


## Computes horizontal air steering and momentum damping.
func _apply_air_movement(
	p: Player, loco: PlayerLocomotionComponent, delta: float, input_dir: Vector2
) -> void:
	if is_launched and launch_timer > 0.0:
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
	if p.is_wolf_mode:
		max_air_speed = loco.sprinting_speed

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


## Casts forward physics ray to detect climbable walls ahead.
func _query_wall_in_front(p: Player, distance: float) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var start_pos: Vector3 = p.global_position + Vector3(0.0, 1.0, 0.0)
	var forward_dir: Vector3 = -p.global_transform.basis.z.normalized()
	var end_pos: Vector3 = start_pos + forward_dir * distance

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.exclude = _exclude_rids
	return space.intersect_ray(query)


## Evaluates whether collision node belongs to wolf climbables.
func _is_climbable_surface(node: Node) -> bool:
	var curr: Node = node
	while is_instance_valid(curr):
		if curr.is_in_group(GROUP_WOLF_CLIMBABLE):
			return true
		curr = curr.get_parent()
	return false


## Checks airborne collision and raycast for wall attachment.
func _check_wolf_air_climb(p: Player) -> bool:
	if not p.is_wolf_mode:
		return false

	var climb_normal: Vector3 = Vector3.ZERO
	var found_climbable: bool = false
	var hit_surface: WolfClimbSurface = null

	var slide_count: int = p.get_slide_collision_count()
	for i: int in range(slide_count):
		var col: KinematicCollision3D = p.get_slide_collision(i)
		var norm: Vector3 = col.get_normal()
		if absf(norm.y) < 0.7:
			var col_node: Node = col.get_collider() as Node
			if is_instance_valid(col_node) and _is_climbable_surface(col_node):
				hit_surface = col_node as WolfClimbSurface
				found_climbable = true
				climb_normal = norm
				break

	if not found_climbable:
		var ray_hit: Dictionary = _query_wall_in_front(p, 0.9)
		if not ray_hit.is_empty():
			var norm: Vector3 = ray_hit.get("normal", Vector3.ZERO) as Vector3
			var col_node: Node = ray_hit.get("collider") as Node
			if (
				absf(norm.y) < 0.7
				and is_instance_valid(col_node)
				and _is_climbable_surface(col_node)
			):
				hit_surface = col_node as WolfClimbSurface
				found_climbable = true
				climb_normal = norm

	if is_instance_valid(hit_surface) and hit_surface.has_dismount_cooldown(p):
		return false

	if found_climbable:
		var inward_speed: float = p.velocity.dot(-climb_normal)
		var is_pressing_fwd: bool = GestureInputManager.is_action_active(ACTION_FORWARD)
		if inward_speed <= 0.15 and not is_pressing_fwd:
			return false

		var cam_fwd: Vector3 = -p.global_transform.basis.z.normalized()
		var cam_ctrl: CameraController = p.camera_controller
		if is_instance_valid(cam_ctrl):
			cam_fwd = cam_ctrl.get_camera_look_dir().normalized()

		var dot_inward: float = cam_fwd.dot(-climb_normal)
		_transition_msg.clear()
		_transition_msg[&"wall_normal"] = climb_normal
		if is_instance_valid(hit_surface):
			_transition_msg[&"climb_surface"] = hit_surface

		var has_wall_run: bool = (
			state_machine.has_node("WolfWallRun") or state_machine.has_node("StateWolfWallRun")
		)
		var wall_run_state: StringName = (
			&"WolfWallRun" if state_machine.has_node("WolfWallRun") else &"StateWolfWallRun"
		)

		if dot_inward > 0.65:
			print("StateAir: Facing wall directly (>0.65). Transitioning to WolfClimb.")
			state_machine.transition_to(STATE_WOLF_CLIMB, _transition_msg)
			return true

		if dot_inward > -0.20 and has_wall_run:
			print("StateAir: Facing wall at angle (<=0.65). Transitioning to ", wall_run_state)
			state_machine.transition_to(wall_run_state, _transition_msg)
			return true

		print("StateAir: Fallback transition to WolfClimb.")
		state_machine.transition_to(STATE_WOLF_CLIMB, _transition_msg)
		return true

	return false


## Polls landing conditions, water, and ledge vaults.
func _check_transitions(
	p: Player, loco: PlayerLocomotionComponent, env: PlayerEnvironmentComponent
) -> void:
	var interact: PlayerInteractionComponent = p.interaction_component

	if _check_wolf_air_climb(p):
		return

	if p.is_on_floor() and p.velocity.y <= 0.0:
		_handle_landing(p, loco)
		return

	if is_instance_valid(env.current_water_node) and p.velocity.y < -1.0:
		print("StateAir: Entering deep water.")
		state_machine.transition_to(STATE_SWIM)
		return

	var is_holding_item: bool = (
		is_instance_valid(interact) and is_instance_valid(interact.held_item)
	)
	var is_pressing_forward: bool = GestureInputManager.is_action_pressed(ACTION_FORWARD)
	var vault_ctrl: VaultController = env.vault_controller as VaultController

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
				GestureInputManager.is_action_just_pressed(ACTION_JUMP) or jump_buffer_timer > 0.0
			)
			if jump_req and vault_ctrl.can_vault_current_ledge:
				if vault_ctrl.try_vault(loco.crouching):
					jump_buffer_timer = 0.0
					print("StateAir: Vaulting ledge on jump input.")
					state_machine.transition_to(STATE_VAULT)
					return

	if is_holding_item and interact.held_item is GliderItem and p.velocity.y < 0.0:
		print("StateAir: Player holding GliderItem falling. Transition to Glide.")
		state_machine.transition_to(STATE_GLIDE)
		return


## Processes ground collision and resets double jump.
func _handle_landing(p: Player, loco: PlayerLocomotionComponent) -> void:
	print("StateAir: _handle_landing() called. Processing ground impact.")
	has_wolf_double_jumped = false
	is_launched = false
	launch_timer = 0.0
	wall_coyote_timer = 0.0

	var impact_fall_speed: float = loco.last_velocity.y
	var is_safe_landing: bool = false
	var is_slide_surface: bool = false

	var slide_count: int = p.get_slide_collision_count()
	for i: int in range(slide_count):
		var collision: KinematicCollision3D = p.get_slide_collision(i)
		if collision.get_normal().y <= 0.1:
			continue

		var node_col: Node = collision.get_collider() as Node
		if not is_instance_valid(node_col):
			continue

		var parent_node: Node = node_col.get_parent()
		if (
			node_col.is_in_group(GROUP_SAFE_LANDING)
			or (is_instance_valid(parent_node) and parent_node.is_in_group(GROUP_SAFE_LANDING))
		):
			is_safe_landing = true

		if (
			node_col.is_in_group(GROUP_SLIDE)
			or (is_instance_valid(parent_node) and parent_node.is_in_group(GROUP_SLIDE))
		):
			is_slide_surface = true

	var health_comp: HealthComponent = p.health_component
	if impact_fall_speed <= -20.0 and is_instance_valid(health_comp):
		if is_safe_landing:
			print("StateAir: Impact neutralized by safe landing material.")
		else:
			print("StateAir: Heavy impact detected. Applying fall damage.")
			health_comp.take_damage(int(health_comp.max_health))

	_transition_msg.clear()
	_transition_msg[&"landing_speed"] = impact_fall_speed

	if is_slide_surface:
		print("StateAir: Slide surface detected. Transitioning to Slide.")
		state_machine.transition_to(STATE_SLIDE, _transition_msg)
		return

	print("StateAir: Standard ground detected. Transitioning to Ground.")
	if jump_buffer_timer > 0.0:
		var interact: PlayerInteractionComponent = p.interaction_component
		var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying
		if not is_holding_heavy:
			_transition_msg[&"jump_buffered"] = true

	state_machine.transition_to(STATE_GROUND, _transition_msg)


## Updates camera transforms and interaction scanner.
func _update_components(
	p: Player, loco: PlayerLocomotionComponent, delta: float, input_dir: Vector2
) -> void:
	var interact: PlayerInteractionComponent = p.interaction_component
	var cam: CameraController = p.camera_controller

	if is_instance_valid(cam):
		cam.update_camera(delta, input_dir, false, loco.crouching, false, p.velocity.length())

	if is_instance_valid(interact) and is_instance_valid(interact.interaction_scanner):
		interact.interaction_scanner.process_interaction(delta)


## Checks for nearby monkey bar handles to grab.
func _check_monkey_bar_grab(env: PlayerEnvironmentComponent) -> void:
	if not is_instance_valid(env):
		return

	if is_instance_valid(env.available_monkey_bar) and env.monkey_bar_cooldown <= 0.0:
		print("StateAir: Grabbed monkey bar.")
		_transition_msg.clear()
		_transition_msg[&"volume_node"] = env.available_monkey_bar
		state_machine.transition_to(STATE_MONKEY_BARS, _transition_msg)
