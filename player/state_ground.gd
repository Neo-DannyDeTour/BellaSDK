## Handles ground locomotion, friction, crouching, sprinting, and jump transitions.
class_name StateGround
extends PlayerState

# --------------------------------------
# CONSTANTS & VARIABLES
# --------------------------------------
## Upward velocity applied when executing a standard jump.
const JUMP_VELOCITY: float = 4.5

## Upward velocity applied when jumping from crouched stance.
const CROUCH_JUMP_VELOCITY: float = 3.5

## Upward velocity applied when jumping while sprinting.
const SPRINT_JUMP_VELOCITY: float = 5.0

## Ground friction applied to decelerate the player without input.
const GROUND_FRICTION: float = 25.0

## Current interpolated movement speed of the player.
var current_speed: float = 0.0

## Preference flag indicating if crouching toggles on and off.
var _toggle_crouch_enabled: bool = false

## Preference flag indicating if sprinting toggles on and off.
var _toggle_sprint_enabled: bool = false

## Preference flag indicating if jumping cancels crouch stance.
var _cancel_crouch_on_jump: bool = false


## Configures velocities, reads accessibility settings, and executes landing crater.
func enter(msg: Dictionary = {}) -> void:
	print("StateGround: enter() called. Resetting Y velocity and current speed.")
	var fall_speed: float = msg.get("landing_speed", 0.0)

	player.velocity.y = 0.0
	current_speed = 0.0

	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	if is_instance_valid(loco) and is_instance_valid(loco.footstep_manager):
		var fm: FootstepManager = loco.footstep_manager as FootstepManager
		fm.stamp_landing_crater(fall_speed)

	_toggle_crouch_enabled = (
		GlobalSettings.get_setting("Accessibility", "toggle_crouch", false) as bool
	)
	_toggle_sprint_enabled = (
		GlobalSettings.get_setting("Accessibility", "toggle_sprint", false) as bool
	)
	_cancel_crouch_on_jump = (
		GlobalSettings.get_setting("Accessibility", "cancel_crouch_on_jump", false) as bool
	)

	if msg.has("jump_buffered") and msg["jump_buffered"] == true:
		var interact: PlayerInteractionComponent = (
			player.interaction_component as PlayerInteractionComponent
		)
		var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

		if is_holding_heavy:
			print("StateGround: Buffered jump rejected due to heavy carry.")
			Events.hint_requested.emit("Cannot jump while carrying a heavy object.", 2.0)
			return

		_perform_jump()
		return


## Processes surfaces, stair snapping, inputs, and ground movement momentum.
## [param delta] The physics frame delta time in seconds.
func physics_update(delta: float) -> void:
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	var env: Node = player.environment_component

	if is_instance_valid(env.get("vault_controller")) and env.vault_controller.get("is_vaulting"):
		return

	# 0. Slide Surface, Sand & Safe Landing Detection
	loco.on_sand = false
	loco.on_safe_landing = false

	var slide_count: int = player.get_slide_collision_count()
	for i: int in range(slide_count):
		var collision: KinematicCollision3D = player.get_slide_collision(i)
		var collider: Object = collision.get_collider()

		if collider is Node:
			if (collider as Node).is_in_group("slide_surface"):
				print("StateGround: Slide surface detected. Transitioning to Slide.")
				state_machine.transition_to("Slide")
				return
			if (collider as Node).is_in_group("sand"):
				loco.on_sand = true
			if (collider as Node).is_in_group("safe_landing"):
				loco.on_safe_landing = true
				print("StateGround: Safe landing material detected. Fall damage neutralized.")

	# 1. State Transitions (Leaving the Ground)
	var is_recently_stepped: bool = loco.stair_controller.get("time_since_step_up") < 0.2
	var snapped_last_frame: bool = loco.stair_controller.get("_snapped_to_stairs_last_frame")

	if not player.is_on_floor() and not snapped_last_frame and not is_recently_stepped:
		if env.get("current_water_node") != null:
			print("StateGround: Transitioning to Swim.")
			state_machine.transition_to("Swim")
			return

		print("StateGround: Floor lost. Transitioning to Air.")
		state_machine.transition_to("Air", {"coyote_time": true})
		return

	# 2. Read Inputs FIRST
	var input_dir: Vector2 = GestureInputManager.get_vector("left", "right", "forward", "backward")
	if GestureInputManager.is_action_pressed("zoom"):
		input_dir = Vector2.ZERO

	# 3. Handle Jump / Vault Logic via GestureInputManager
	if GestureInputManager.is_action_just_triggered("jump"):
		var interact: PlayerInteractionComponent = (
			player.interaction_component as PlayerInteractionComponent
		)
		var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

		if is_holding_heavy:
			print("StateGround: Object is too heavy to jump (>= 10kg).")
			Events.hint_requested.emit("Cannot jump while carrying a heavy object.", 2.0)
			return

		var is_pressing_forward: bool = GestureInputManager.is_action_active("forward")
		if (
			is_pressing_forward
			and not snapped_last_frame
			and is_instance_valid(env.get("vault_controller"))
			and env.vault_controller.try_vault(loco.crouching)
		):
			print("StateGround: Valid vault detected. Transitioning.")
			state_machine.transition_to("Vault")
			return
		_perform_jump()
		return

	# 4. Determine Speed State
	_calculate_target_speed(delta, input_dir)

	# 5. Apply Physics (Momentum & Friction)
	_apply_movement(delta, input_dir)
	loco.last_velocity = player.velocity

	# 6. Try snapping UP stairs
	loco.stair_controller.snap_up_stairs_check(delta, loco.sprint_active)

	player.move_and_slide()

	# 7. Try snapping DOWN stairs
	loco.stair_controller.snap_down_to_stairs_check()

	# 8. Keep track of floor timing
	loco.stair_controller.track_floor_state()

	# 9. Update decoupled components
	_update_components(delta, input_dir)


## Applies upward vertical jump impulse and transitions to [StateAir].
func _perform_jump() -> void:
	print("StateGround: _perform_jump() called.")
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent

	if loco.sprint_active:
		player.velocity.y = SPRINT_JUMP_VELOCITY
	elif loco.crouching:
		player.velocity.y = CROUCH_JUMP_VELOCITY
		if _cancel_crouch_on_jump and not loco.crouch_cast_check.is_colliding():
			print("StateGround: Jumping while crouched. Canceling crouch state.")
			loco.crouching = false
			loco.standing_collision.disabled = false
			loco.crouching_collision.disabled = true
			Events.player_crouch_changed.emit(false)
	else:
		player.velocity.y = JUMP_VELOCITY

	print("StateGround: Executing jump. Velocity Y set to ", player.velocity.y)
	state_machine.transition_to("Air", {"jump": true})


## Calculates target movement speed based on stance, heavy carrying, and terrain.
## [param delta] The physics frame delta time in seconds.
## [param input_dir] Normalized 2D movement input vector.
func _calculate_target_speed(delta: float, input_dir: Vector2) -> void:
	# print("StateGround: _calculate_target_speed() evaluating speeds.")
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)

	var previous_crouch: bool = loco.crouching
	var is_moving: bool = input_dir.length() > 0.1

	# --- 1. GATHER INTENTIONS ---
	var wants_to_crouch: bool = loco.crouching
	if _toggle_crouch_enabled:
		if GestureInputManager.is_action_just_triggered("crouch"):
			wants_to_crouch = not loco.crouching
	else:
		wants_to_crouch = GestureInputManager.is_action_active("crouch")

	var wants_to_sprint: bool = loco.sprint_active
	if _toggle_sprint_enabled:
		if GestureInputManager.is_action_just_triggered("sprint"):
			wants_to_sprint = not loco.sprint_active
	else:
		wants_to_sprint = GestureInputManager.is_action_active("sprint")

	# --- 2. PRIORITY OVERRIDES ---
	if wants_to_sprint and wants_to_crouch:
		if GestureInputManager.is_action_just_triggered("crouch"):
			print("StateGround: Crouch requested. Prioritizing crouch state.")
			wants_to_sprint = false
		elif GestureInputManager.is_action_just_triggered("sprint") or loco.sprint_active:
			if not loco.crouch_cast_check.is_colliding():
				print("StateGround: Sprint requested. Prioritizing sprint state.")
				wants_to_crouch = false
			else:
				wants_to_sprint = false
		else:
			wants_to_sprint = false

	# --- 3. SPRINT RESTRICTIONS ---
	var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

	if GestureInputManager.is_action_just_triggered("sprint") and is_holding_heavy:
		print("StateGround: Sprint rejected. Object is too heavy.")
		Events.hint_requested.emit("Cannot sprint while carrying a heavy object.", 2.0)

	if not is_moving or wants_to_crouch or loco.on_sand or not loco.can_sprint or is_holding_heavy:
		wants_to_sprint = false

	loco.sprint_active = wants_to_sprint

	# --- 4. CROUCH LOGIC & COLLISION ---
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

	# --- 5. SPEED TARGETING ---
	var target_speed: float = loco.walking_speed
	if loco.sprint_active:
		target_speed = loco.sprinting_speed
	elif loco.crouching or loco.on_sand:
		target_speed = loco.crouching_speed

	if is_holding_heavy:
		target_speed = (
			loco.walking_speed * loco.heavy_carry_speed_mult
			if not loco.crouching
			else loco.crouching_speed * loco.heavy_carry_speed_mult
		)

	# Inertia drag: heavy objects take longer to build and bleed momentum
	var accel_speed: float = 7.5 if is_holding_heavy else 15.0
	current_speed = lerpf(current_speed, target_speed, delta * accel_speed)


## Interpolates horizontal velocity and applies surface friction.
## [param delta] The physics frame delta time in seconds.
## [param input_dir] Normalized 2D movement input vector.
func _apply_movement(delta: float, input_dir: Vector2) -> void:
	# print("StateGround: _apply_movement() applying directional momentum.")
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)
	var is_holding_heavy: bool = is_instance_valid(interact) and interact.is_heavy_carrying

	var active_lerp: float = loco.ice_lerp_speed if loco.on_ice else loco.default_lerp_speed
	if is_holding_heavy and not loco.on_ice:
		active_lerp *= 0.65

	var target_dir: Vector3 = (
		(player.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	)

	loco.set_direction(loco.get_direction().lerp(target_dir, delta * active_lerp))

	if player.is_on_floor():
		player.velocity.y = -0.1
	else:
		player.velocity.y -= loco.gravity * delta

	if input_dir != Vector2.ZERO or loco.on_ice:
		player.velocity.x = loco.get_direction().x * current_speed
		player.velocity.z = loco.get_direction().z * current_speed
	else:
		var friction_val: float = GROUND_FRICTION * 0.7 if is_holding_heavy else GROUND_FRICTION
		var friction_step: float = friction_val * delta
		player.velocity.x = move_toward(player.velocity.x, 0.0, friction_step)
		player.velocity.z = move_toward(player.velocity.z, 0.0, friction_step)

		if player.velocity.length() < 0.01:
			loco.set_direction(Vector3.ZERO)


## Updates camera position, footsteps, scanners, and physics pushers.
## [param delta] The physics frame delta time in seconds.
## [param input_dir] Normalized 2D movement input vector.
func _update_components(delta: float, input_dir: Vector2) -> void:
	# print("StateGround: _update_components() polling attached subsystems.")
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)

	if is_instance_valid(player.camera_controller):
		player.camera_controller.update_camera(
			delta, input_dir, loco.sprint_active, loco.crouching, true, player.velocity.length()
		)

	if is_instance_valid(loco.footstep_manager):
		loco.footstep_manager.process_surface_and_footsteps(
			delta, true, player.velocity.length(), loco.sprint_active, loco.crouching
		)
		loco.on_ice = loco.footstep_manager.get("is_on_ice")

	if is_instance_valid(interact.interaction_scanner):
		interact.interaction_scanner.process_interaction(delta)

	if is_instance_valid(loco.physics_pusher):
		loco.physics_pusher.process_pushes(
			interact.held_item, loco.last_velocity, loco.sprinting_speed
		)
