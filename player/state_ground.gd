## Handles ground locomotion, friction, crouching, sprinting, and jump transitions.
class_name StateGround
extends PlayerState

## Upward velocity applied when executing a standard jump.
const JUMP_VELOCITY: float = 4.5

## Upward velocity applied when jumping from crouched stance.
const CROUCH_JUMP_VELOCITY: float = 3.5

## Upward velocity applied when jumping while sprinting.
const SPRINT_JUMP_VELOCITY: float = 5.0

## Ground friction applied to decelerate the player without input.
const GROUND_FRICTION: float = 25.0

## Group identifier for slide surfaces.
const GROUP_SLIDE: StringName = &"slide_surface"

## Group identifier for sand surfaces.
const GROUP_SAND: StringName = &"sand"

## Group identifier for fall-damage-negating surfaces.
const GROUP_SAFE_LANDING: StringName = &"safe_landing"

## State identifier for sliding.
const STATE_SLIDE: StringName = &"Slide"

## State identifier for swimming.
const STATE_SWIM: StringName = &"Swim"

## State identifier for airborne movement.
const STATE_AIR: StringName = &"Air"

## State identifier for ledge vaulting.
const STATE_VAULT: StringName = &"Vault"

## Input action identifier for moving left.
const ACTION_LEFT: StringName = &"left"

## Input action identifier for moving right.
const ACTION_RIGHT: StringName = &"right"

## Input action identifier for moving forward.
const ACTION_FORWARD: StringName = &"forward"

## Input action identifier for moving backward.
const ACTION_BACKWARD: StringName = &"backward"

## Input action identifier for camera zoom.
const ACTION_ZOOM: StringName = &"zoom"

## Input action identifier for jumping.
const ACTION_JUMP: StringName = &"jump"

## Input action identifier for crouching.
const ACTION_CROUCH: StringName = &"crouch"

## Input action identifier for sprinting.
const ACTION_SPRINT: StringName = &"sprint"

## Current interpolated movement speed of the player character.
var current_speed: float = 0.0

## Preference flag indicating if crouching toggles on and off.
var _toggle_crouch_enabled: bool = false

## Preference flag indicating if sprinting toggles on and off.
var _toggle_sprint_enabled: bool = false

## Preference flag indicating if jumping cancels crouch stance.
var _cancel_crouch_on_jump: bool = false

## Reusable transition payload dictionary to avoid runtime allocations.
var _transition_msg: Dictionary = {}


## Configures velocities, reads accessibility settings, and stamps landing crater.
func enter(msg: Dictionary = {}) -> void:
	print("StateGround: enter() called. Resetting Y velocity and current speed.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	var fall_speed: float = msg.get(&"landing_speed", 0.0) as float
	p.velocity.y = 0.0
	current_speed = 0.0

	var loco: PlayerLocomotionComponent = p.locomotion_component
	if is_instance_valid(loco):
		var fm: FootstepManager = loco.footstep_manager as FootstepManager
		if is_instance_valid(fm):
			fm.stamp_landing_crater(fall_speed)

	_toggle_crouch_enabled = GlobalSettings.get_setting_bool(
		"Accessibility", "toggle_crouch", false
	)
	_toggle_sprint_enabled = GlobalSettings.get_setting_bool(
		"Accessibility", "toggle_sprint", false
	)
	_cancel_crouch_on_jump = GlobalSettings.get_setting_bool(
		"Accessibility", "cancel_crouch_on_jump", false
	)

	if msg.get(&"jump_buffered", false) == true:
		var interact: PlayerInteractionComponent = p.interaction_component
		var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

		if is_holding_heavy:
			print("StateGround: Buffered jump rejected due to heavy carry.")
			Events.hint_requested.emit("Cannot jump while carrying a heavy object.", 2.0)
			return

		_perform_jump(p, loco)


## Processes surfaces, stair snapping, inputs, and ground momentum via [MathUtils].
func physics_update(delta: float) -> void:
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	var loco: PlayerLocomotionComponent = p.locomotion_component
	var env: PlayerEnvironmentComponent = p.environment_component
	var interact: PlayerInteractionComponent = p.interaction_component

	if (
		is_instance_valid(env)
		and is_instance_valid(env.vault_controller)
		and env.vault_controller.get(&"is_vaulting") == true
	):
		return

	if not is_instance_valid(loco):
		return

	loco.on_sand = false
	loco.on_safe_landing = false

	var slide_count: int = p.get_slide_collision_count()
	for i: int in range(slide_count):
		var collision: KinematicCollision3D = p.get_slide_collision(i)
		var node_col: Node = collision.get_collider() as Node
		if not is_instance_valid(node_col):
			continue

		if _is_collider_in_group(node_col, GROUP_SLIDE):
			print("StateGround: Slide surface detected. Transitioning to Slide.")
			state_machine.transition_to(STATE_SLIDE)
			return
		if _is_collider_in_group(node_col, GROUP_SAND):
			loco.on_sand = true
		if _is_collider_in_group(node_col, GROUP_SAFE_LANDING):
			loco.on_safe_landing = true

	var is_recently_stepped: bool = (
		(loco.stair_controller.get(&"time_since_step_up") as float) < 0.2
	)
	var snapped_last_frame: bool = (
		loco.stair_controller.get(&"_snapped_to_stairs_last_frame") == true
	)

	if not p.is_on_floor() and not snapped_last_frame and not is_recently_stepped:
		if is_instance_valid(env) and is_instance_valid(env.current_water_node):
			print("StateGround: Transitioning to Swim.")
			state_machine.transition_to(STATE_SWIM)
			return

		print("StateGround: Floor lost. Transitioning to Air.")
		_transition_msg.clear()
		_transition_msg[&"coyote_time"] = true
		state_machine.transition_to(STATE_AIR, _transition_msg)
		return

	var input_dir: Vector2 = GestureInputManager.get_vector(
		ACTION_LEFT, ACTION_RIGHT, ACTION_FORWARD, ACTION_BACKWARD
	)
	if GestureInputManager.is_action_pressed(ACTION_ZOOM):
		input_dir = Vector2.ZERO

	if GestureInputManager.is_action_just_triggered(ACTION_JUMP):
		var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying
		if is_holding_heavy:
			print("StateGround: Object is too heavy to jump (>= 10kg).")
			Events.hint_requested.emit("Cannot jump while carrying a heavy object.", 2.0)
			return

		var is_pressing_forward: bool = GestureInputManager.is_action_active(ACTION_FORWARD)
		if (
			is_pressing_forward
			and not snapped_last_frame
			and is_instance_valid(env)
			and is_instance_valid(env.vault_controller)
			and env.vault_controller.call(&"try_vault", loco.crouching) == true
		):
			print("StateGround: Valid vault detected. Transitioning.")
			state_machine.transition_to(STATE_VAULT)
			return
		_perform_jump(p, loco)
		return

	_calculate_target_speed(loco, interact, delta, input_dir)
	_apply_movement(p, loco, interact, delta, input_dir)
	loco.last_velocity = p.velocity

	loco.stair_controller.call(&"snap_up_stairs_check", delta, loco.sprint_active)
	p.move_and_slide()
	loco.stair_controller.call(&"snap_down_to_stairs_check")
	loco.stair_controller.call(&"track_floor_state")
	_update_components(p, loco, interact, delta, input_dir)


## Returns owning player as concrete [Player] instance.
func _get_player() -> Player:
	return player as Player


## Checks if [param node] or its immediate parent belongs to [param group_name].
func _is_collider_in_group(node: Node, group_name: StringName) -> bool:
	if node.is_in_group(group_name):
		return true
	var parent_node: Node = node.get_parent()
	return is_instance_valid(parent_node) and parent_node.is_in_group(group_name)


## Applies upward vertical jump impulse and transitions to [StateAir].
func _perform_jump(p: Player, loco: PlayerLocomotionComponent) -> void:
	print("StateGround: _perform_jump() called.")
	if (
		_cancel_crouch_on_jump
		and loco.crouching
		and is_instance_valid(loco.crouch_cast_check)
		and not loco.crouch_cast_check.is_colliding()
	):
		loco.crouching = false
		loco.standing_collision.disabled = false
		loco.crouching_collision.disabled = true
		Events.player_crouch_changed.emit(false)

	var is_wolf: bool = p.is_wolf_mode
	var is_pressing_fwd: bool = GestureInputManager.is_action_active(ACTION_FORWARD)

	if is_wolf and loco.sprint_active and is_pressing_fwd:
		print("StateGround: Executing high-speed wolf pounce leap!")
		var fwd_dir: Vector3 = -p.global_transform.basis.z.normalized()
		p.velocity.x = fwd_dir.x * (loco.sprinting_speed * 1.6)
		p.velocity.z = fwd_dir.z * (loco.sprinting_speed * 1.6)
		p.velocity.y = SPRINT_JUMP_VELOCITY * 1.35
	elif loco.sprint_active:
		p.velocity.y = SPRINT_JUMP_VELOCITY * (1.25 if is_wolf else 1.0)
	elif loco.crouching:
		p.velocity.y = CROUCH_JUMP_VELOCITY
	else:
		p.velocity.y = JUMP_VELOCITY * (1.3 if is_wolf else 1.0)

	print("StateGround: Executing jump. Velocity Y set to ", p.velocity.y)
	_transition_msg.clear()
	_transition_msg[&"jump"] = true
	state_machine.transition_to(STATE_AIR, _transition_msg)


## Calculates target movement speed based on stance, heavy carrying, and terrain.
func _calculate_target_speed(
	loco: PlayerLocomotionComponent,
	interact: PlayerInteractionComponent,
	delta: float,
	input_dir: Vector2
) -> void:
	var previous_crouch: bool = loco.crouching
	var is_moving: bool = input_dir.length_squared() > 0.01

	var wants_to_crouch: bool = loco.crouching
	if _toggle_crouch_enabled:
		if GestureInputManager.is_action_just_triggered(ACTION_CROUCH):
			wants_to_crouch = not loco.crouching
	else:
		wants_to_crouch = GestureInputManager.is_action_active(ACTION_CROUCH)

	var wants_to_sprint: bool = loco.sprint_active
	if _toggle_sprint_enabled:
		if GestureInputManager.is_action_just_triggered(ACTION_SPRINT):
			wants_to_sprint = not loco.sprint_active
	else:
		wants_to_sprint = GestureInputManager.is_action_active(ACTION_SPRINT)

	if wants_to_sprint and wants_to_crouch:
		if GestureInputManager.is_action_just_triggered(ACTION_CROUCH):
			print("StateGround: Crouch requested. Prioritizing crouch state.")
			wants_to_sprint = false
		elif GestureInputManager.is_action_just_triggered(ACTION_SPRINT) or loco.sprint_active:
			if not loco.crouch_cast_check.is_colliding():
				print("StateGround: Sprint requested. Prioritizing sprint state.")
				wants_to_crouch = false
			else:
				wants_to_sprint = false
		else:
			wants_to_sprint = false

	var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

	if GestureInputManager.is_action_just_triggered(ACTION_SPRINT) and is_holding_heavy:
		print("StateGround: Sprint rejected. Object is too heavy.")
		Events.hint_requested.emit("Cannot sprint while carrying a heavy object.", 2.0)

	if not is_moving or wants_to_crouch or loco.on_sand or not loco.can_sprint or is_holding_heavy:
		wants_to_sprint = false

	loco.sprint_active = wants_to_sprint

	if wants_to_crouch:
		loco.crouching = true
	elif loco.crouching and loco.crouch_cast_check.is_colliding():
		loco.crouching = true
	else:
		loco.crouching = false

	loco.standing_collision.disabled = loco.crouching
	loco.crouching_collision.disabled = not loco.crouching

	if previous_crouch != loco.crouching:
		Events.player_crouch_changed.emit(loco.crouching)

	var target_speed: float = loco.walking_speed
	if loco.sprint_active:
		target_speed = loco.sprinting_speed
	elif loco.crouching or loco.on_sand:
		target_speed = loco.crouching_speed

	if is_holding_heavy:
		var base_heavy_speed: float = loco.crouching_speed if loco.crouching else loco.walking_speed
		target_speed = base_heavy_speed * loco.heavy_carry_speed_mult

	var accel_speed: float = 7.5 if is_holding_heavy else 15.0
	current_speed = MathUtils.damp(current_speed, target_speed, accel_speed, delta)


## Interpolates horizontal velocity and applies surface friction via [MathUtils].
func _apply_movement(
	p: Player,
	loco: PlayerLocomotionComponent,
	interact: PlayerInteractionComponent,
	delta: float,
	input_dir: Vector2
) -> void:
	var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying
	var active_lerp: float = loco.ice_lerp_speed if loco.on_ice else loco.default_lerp_speed
	if is_holding_heavy and not loco.on_ice:
		active_lerp *= 0.65

	var target_dir: Vector3 = (
		(p.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	)

	loco.set_direction(MathUtils.damp_v3(loco.get_direction(), target_dir, active_lerp, delta))

	if p.is_on_floor():
		p.velocity.y = -0.1
	else:
		p.velocity.y -= loco.gravity * delta

	if input_dir != Vector2.ZERO or loco.on_ice:
		p.velocity.x = loco.get_direction().x * current_speed
		p.velocity.z = loco.get_direction().z * current_speed
	else:
		var friction_val: float = GROUND_FRICTION * 0.7 if is_holding_heavy else GROUND_FRICTION
		var friction_step: float = friction_val * delta
		p.velocity.x = move_toward(p.velocity.x, 0.0, friction_step)
		p.velocity.z = move_toward(p.velocity.z, 0.0, friction_step)

		if p.velocity.length_squared() < 0.0001:
			loco.set_direction(Vector3.ZERO)


## Updates camera position, footsteps, scanners, and physics pushers.
func _update_components(
	p: Player,
	loco: PlayerLocomotionComponent,
	interact: PlayerInteractionComponent,
	delta: float,
	input_dir: Vector2
) -> void:
	var cam_ctrl: CameraController = p.camera_controller
	var vel_len: float = p.velocity.length()

	if is_instance_valid(cam_ctrl):
		cam_ctrl.update_camera(delta, input_dir, loco.sprint_active, loco.crouching, true, vel_len)

	var fm: FootstepManager = loco.footstep_manager as FootstepManager
	if is_instance_valid(fm):
		fm.process_surface_and_footsteps(delta, true, vel_len, loco.sprint_active, loco.crouching)
		loco.on_ice = fm.is_on_ice

	if is_instance_valid(interact) and is_instance_valid(interact.interaction_scanner):
		interact.interaction_scanner.process_interaction(delta)

	if is_instance_valid(loco.physics_pusher):
		loco.physics_pusher.call(
			&"process_pushes",
			interact.held_item if is_instance_valid(interact) else null,
			loco.last_velocity,
			loco.sprinting_speed
		)
