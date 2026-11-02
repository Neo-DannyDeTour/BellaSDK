## Handles overhead hanging, camera-projected traversal, and bar swinging on [TimberJibCrane].
class_name StateJibCrane
extends PlayerState

# --------------------------------------
# CONSTANTS
# --------------------------------------

## Target state name when dismounting into the air.
const STATE_AIR: StringName = &"Air"

## Transition dictionary key holding the [TimberJibCrane] instance.
const KEY_CRANE: StringName = &"crane"

## Transition dictionary key holding the initial 1D offset along the jib rail.
const KEY_RAIL_OFFSET: StringName = &"rail_offset"

## Transition dictionary key indicating a jump dismount occurred.
const KEY_JUMP: StringName = &"jump"

## Transition dictionary key carrying the horizontal release direction vector.
const KEY_RELEASE_DIR: StringName = &"release_dir"

## Base horizontal speed (m/s) applied along flat camera forward on stationary jump dismount.
const JUMP_HORIZONTAL_SPEED: float = 6.2

## Maximum horizontal speed (m/s) applied when launching at the apex of a bar swing.
const SWING_LAUNCH_MAX_HORIZ_SPEED: float = 9.2

## Base upward velocity (m/s) applied when jumping off the jib rail.
const JUMP_VERTICAL_SPEED: float = 4.8

## Additional upward velocity (m/s) added at full bar swing momentum.
const SWING_LAUNCH_BONUS_UP: float = 1.4

## Downward velocity (m/s) applied when dropping off the jib rail via crouch/interact.
const DROP_VERTICAL_SPEED: float = -1.5

## Effective pendulum arm length (m) from the overhead grab bar to player center of mass.
const SWING_ARM_LENGTH: float = 1.35

## Gravity multiplier for snappy Mirror's Edge pendulum bar swinging.
const SWING_GRAVITY_SCALE: float = 1.75

## Angular pump acceleration (rad/s^2) when driving a perpendicular bar swing with WASD.
const SWING_PUMP_ACCEL: float = 9.5

## Maximum pendulum swing angle in radians (~52 degrees).
const MAX_SWING_ANGLE_RAD: float = 0.9075712

## Active angular damping rate while pumping a bar swing.
const SWING_ACTIVE_DAMPING: float = 0.55

## Idle angular damping rate when no perpendicular swing input is held.
const SWING_IDLE_DAMPING: float = 3.2

## Maximumvertical lift (m) allowed from pendulum swing arc so head stays below boom.
const MAX_SWING_VERTICAL_LIFT: float = 0.48

## Exponential snap rate pulling the player onto the moving jib rail anchor.
const RAIL_SNAP_SPEED: float = 22.0

## Speed threshold (m/s) below which the player is stationary enough to fire weapons.
const FIRE_STILL_SPEED_THRESHOLD: float = 0.15

## Maximum camera roll tilt in degrees while shimmying or swinging on the jib rail.
const MAX_SHIMMY_ROLL_DEG: float = 3.5

## Maximum camera pitch offset in degrees during perpendicular pendulum swings.
const MAX_SWING_PITCH_DEG: float = 5.0

## Exponential smoothing rate for camera roll interpolation.
const CAMERA_ROLL_LERP_SPEED: float = 10.0

## Minimum elapsed time in seconds after mounting before interact key can dismount.
const INTERACT_DISMOUNT_GRACE: float = 0.25

## Re-grab cooldown in seconds applied to the crane upon dismounting.
const DISMOUNT_REGRAB_COOLDOWN: float = 0.45

# --------------------------------------
# PRIVATE VARIABLES
# --------------------------------------

## Currently mounted [TimberJibCrane] instance.
var _crane: TimberJibCrane = null

## Current 1D distance in meters along the jib grab rail from the mast pivot.
var _current_rail_offset: float = 5.5

## Current smoothed 1D speed (m/s) along the jib grab rail.
var _current_rail_speed: float = 0.0

## Current pendulum swing angle in radians perpendicular to the jib rail.
var _swing_angle_rad: float = 0.0

## Current pendulum angular velocity in radians per second.
var _swing_angular_vel: float = 0.0

## Previous physics frame global yaw (radians) of the crane's rotating pivot.
var _last_crane_yaw_rad: float = 0.0

## Time in seconds elapsed since entering [StateJibCrane].
var _elapsed_time: float = 0.0

## Current smoothed camera roll angle in radians applied to the eyes pivot.
var _current_roll_rad: float = 0.0

## Current smoothed camera pitch offset in radians applied to the eyes pivot during swing.
var _current_swing_pitch_rad: float = 0.0

## Tween easing the camera roll back to zero on state exit.
var _roll_reset_tween: Tween = null

## Cached [AnimationPlayer] driving first-person camera animations.
var _camera_anims: AnimationPlayer = null

## Reusable transition dictionary to avoid per-dismount heap allocations.
var _transition_msg: Dictionary = {}

# --------------------------------------
# LIFECYCLE & STATE HOOKS
# --------------------------------------


## Attaches player below the crane jib rail, disables vaulting, and syncs initial yaw.
func enter(msg: Dictionary = {}) -> void:
	print("StateJibCrane: enter() called. Player mounting crane jib.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	var raw_crane: Object = msg.get(KEY_CRANE)
	var crane_candidate: TimberJibCrane = raw_crane as TimberJibCrane
	if not is_instance_valid(crane_candidate):
		state_machine.transition_to(STATE_AIR)
		return

	_crane = crane_candidate
	_elapsed_time = 0.0
	_current_rail_speed = 0.0
	_swing_angle_rad = 0.0
	_swing_angular_vel = 0.0
	_current_roll_rad = 0.0
	_current_swing_pitch_rad = 0.0

	if not is_instance_valid(_camera_anims):
		_camera_anims = p.get_node_or_null("%CameraAnims") as AnimationPlayer

	Utilities.safe_kill_tween(_roll_reset_tween)
	_roll_reset_tween = null

	_drop_heavy_items_if_needed(p)
	_set_crane_collision_exceptions(p, true)
	_set_vault_controller_enabled(p, false)

	var raw_offset: float = _crane.project_world_pos_to_rail_offset(p.global_position)
	if msg.has(KEY_RAIL_OFFSET):
		var msg_offset: Variant = msg[KEY_RAIL_OFFSET]
		if msg_offset is float:
			raw_offset = msg_offset
	_current_rail_offset = _crane.clamp_rail_offset(raw_offset)
	_last_crane_yaw_rad = _crane.get_pivot_global_yaw_rad()

	var loco: PlayerLocomotionComponent = p.locomotion_component
	if is_instance_valid(loco):
		loco.crouching = false
		loco.sprint_active = false
		loco.set_direction(Vector3.ZERO)
		if is_instance_valid(loco.stair_controller):
			loco.stair_controller.set(&"is_enabled", false)

	if is_instance_valid(p.camera_controller):
		p.camera_controller.disable_sprint_fov = true

	if is_instance_valid(_camera_anims) and _camera_anims.has_animation(&"monkey_bar_idle"):
		_camera_anims.play(&"monkey_bar_idle")

	var mount_pos: Vector3 = _crane.get_rail_world_position(_current_rail_offset)
	mount_pos.y += _crane.hang_vertical_offset
	p.global_position = mount_pos
	p.velocity = Vector3.ZERO
	_set_weapon_can_fire(p, true)
	_crane.notify_jib_player_mounted(p)


## Restores camera roll, weapon state, stair/vault controllers, and crane cooldown on exit.
func exit() -> void:
	print("StateJibCrane: exit() called. Player dismounting crane jib.")
	var p: Player = _get_player()
	if is_instance_valid(p):
		_set_weapon_can_fire(p, true)
		_set_crane_collision_exceptions(p, false)
		_set_vault_controller_enabled(p, true)

		var loco: PlayerLocomotionComponent = p.locomotion_component
		if is_instance_valid(loco):
			if is_instance_valid(loco.stair_controller):
				loco.stair_controller.set(&"is_enabled", true)
			if is_instance_valid(loco.footstep_manager):
				if loco.footstep_manager.has_method(&"stop_looping_sounds"):
					loco.footstep_manager.call(&"stop_looping_sounds")

		if is_instance_valid(p.camera_controller):
			p.camera_controller.disable_sprint_fov = false

		if is_instance_valid(_camera_anims) and _camera_anims.has_animation(&"idle"):
			_camera_anims.play(&"idle", 0.2)

		_ease_camera_roll_to_zero(p)

	if is_instance_valid(_crane):
		_crane.notify_jib_player_dismounted(p, DISMOUNT_REGRAB_COOLDOWN)
	_crane = null


## Processes camera-projected bar traversal, pendulum swinging, yaw sync, and dismounts.
func physics_update(delta: float) -> void:
	var p: Player = _get_player()
	if not is_instance_valid(p) or not is_instance_valid(_crane) or p.is_dead:
		state_machine.transition_to(STATE_AIR)
		return

	_elapsed_time += delta

	if _check_dismount_inputs(p):
		return

	# 1. Sync player yaw with live crane rotation while preserving full mouse freelook
	var current_crane_yaw: float = _crane.get_pivot_global_yaw_rad()
	var delta_yaw: float = angle_difference(_last_crane_yaw_rad, current_crane_yaw)
	_last_crane_yaw_rad = current_crane_yaw
	if not is_zero_approx(delta_yaw):
		p.rotation.y += delta_yaw

	# 2. Project 3D flat camera wish vector onto parallel (bar) and perpendicular (swing) axes
	var input_dir: Vector2 = GestureInputManager.get_vector(
		String(ACTION_LEFT), String(ACTION_RIGHT), String(ACTION_FORWARD), String(ACTION_BACKWARD)
	)
	var rail_dir: Vector3 = _crane.get_rail_world_direction()
	var rail_perp: Vector3 = Vector3(-rail_dir.z, 0.0, rail_dir.x)
	var flat_fwd: Vector3 = _get_flat_camera_forward(p)
	var flat_right: Vector3 = _get_flat_camera_right(p)
	var wish_dir: Vector3 = (flat_fwd * (-input_dir.y)) + (flat_right * input_dir.x)

	var raw_along: float = wish_dir.dot(rail_dir)
	var along_input: float = 0.0
	if absf(raw_along) > 0.15:
		along_input = clampf(raw_along / 0.7071068, -1.0, 1.0)

	var target_speed: float = along_input * _crane.jib_traverse_speed
	var accel_rate: float = 16.0 if absf(target_speed) > 0.01 else 20.0
	_current_rail_speed = move_toward(_current_rail_speed, target_speed, accel_rate * delta)

	var prev_offset: float = _current_rail_offset
	_current_rail_offset = _crane.clamp_rail_offset(
		_current_rail_offset + (_current_rail_speed * delta)
	)
	var actual_rail_speed: float = (_current_rail_offset - prev_offset) / maxf(delta, 0.0001)
	if is_zero_approx(actual_rail_speed) and absf(target_speed) > 0.01:
		_current_rail_speed = 0.0

	# 3. Update perpendicular Mirror's Edge bar swing pendulum
	var perp_input: float = clampf(wish_dir.dot(rail_perp), -1.0, 1.0)
	_update_pendulum_swing(perp_input, delta)

	# 4. Compute world position strictly below the bar (never step/climb onto boom)
	var rail_world_pos: Vector3 = _crane.get_rail_world_position(_current_rail_offset)
	var swing_horiz_offset: Vector3 = rail_perp * (sin(_swing_angle_rad) * SWING_ARM_LENGTH)
	var swing_vert_lift: float = minf(
		(1.0 - cos(_swing_angle_rad)) * SWING_ARM_LENGTH, MAX_SWING_VERTICAL_LIFT
	)
	var max_allowed_y: float = (
		rail_world_pos.y + _crane.hang_vertical_offset + MAX_SWING_VERTICAL_LIFT
	)
	var target_pos: Vector3 = Vector3(
		rail_world_pos.x + swing_horiz_offset.x,
		minf(rail_world_pos.y + _crane.hang_vertical_offset + swing_vert_lift, max_allowed_y),
		rail_world_pos.z + swing_horiz_offset.z
	)

	var snap_weight: float = 1.0 - exp(-RAIL_SNAP_SPEED * delta)
	p.global_position = p.global_position.lerp(target_pos, snap_weight)
	p.global_position.y = minf(p.global_position.y, max_allowed_y)
	p.velocity = Vector3.ZERO

	# 5. Stationary weapon firing gate & shimmy audio
	var speed_abs: float = absf(actual_rail_speed)
	var swing_speed_abs: float = absf(_swing_angular_vel) * SWING_ARM_LENGTH
	var is_stationary: bool = (
		speed_abs < FIRE_STILL_SPEED_THRESHOLD
		and swing_speed_abs < FIRE_STILL_SPEED_THRESHOLD * 2.5
	)
	_set_weapon_can_fire(p, is_stationary)
	_crane.set_shimmy_audio(speed_abs > 0.1 or swing_speed_abs > 0.35)

	# 6. Footstep/hand-step audio & camera feedback
	var loco: PlayerLocomotionComponent = p.locomotion_component
	if is_instance_valid(loco) and is_instance_valid(loco.footstep_manager):
		if loco.footstep_manager.has_method(&"process_surface_and_footsteps"):
			loco.footstep_manager.call(
				&"process_surface_and_footsteps",
				delta,
				false,
				maxf(speed_abs, swing_speed_abs * 0.65),
				false,
				false,
				false,
				true
			)

	if is_instance_valid(p.camera_controller):
		p.camera_controller.update_camera(
			delta, input_dir, false, false, false, _crane.jib_traverse_speed
		)

	_update_camera_feedback(p, along_input, delta)


# --------------------------------------
# PRIVATE HELPERS
# --------------------------------------


## Advances the analytic pendulum swing perpendicular to the jib bar.
func _update_pendulum_swing(perp_input: float, delta: float) -> void:
	var gravity_restore: float = (
		-(9.8 * SWING_GRAVITY_SCALE / SWING_ARM_LENGTH) * sin(_swing_angle_rad)
	)
	var pump_accel: float = 0.0
	var is_pumping: bool = absf(perp_input) > 0.15

	if is_pumping and absf(_swing_angle_rad) < MAX_SWING_ANGLE_RAD:
		var pump_dir: float = signf(perp_input)
		# Auto-phase continuous W hold with backswing so holding W builds a full swing
		if absf(_swing_angular_vel) > 0.35 and signf(_swing_angular_vel) != pump_dir:
			pump_dir = signf(_swing_angular_vel)
		var apex_atten: float = clampf(
			1.0 - (absf(_swing_angle_rad) / MAX_SWING_ANGLE_RAD) * 0.5, 0.25, 1.0
		)
		pump_accel = pump_dir * (SWING_PUMP_ACCEL / SWING_ARM_LENGTH) * apex_atten

	_swing_angular_vel += (gravity_restore + pump_accel) * delta
	var damp_rate: float = SWING_ACTIVE_DAMPING if is_pumping else SWING_IDLE_DAMPING
	_swing_angular_vel *= exp(-damp_rate * delta)
	_swing_angle_rad += _swing_angular_vel * delta

	if absf(_swing_angle_rad) > MAX_SWING_ANGLE_RAD:
		_swing_angle_rad = clampf(_swing_angle_rad, -MAX_SWING_ANGLE_RAD, MAX_SWING_ANGLE_RAD)
		if signf(_swing_angular_vel) == signf(_swing_angle_rad):
			_swing_angular_vel = 0.0


## Checks Jump, Crouch, or Interact inputs to trigger a dismount from the jib rail.
func _check_dismount_inputs(p: Player) -> bool:
	if GestureInputManager.is_action_just_pressed(String(ACTION_JUMP)):
		_perform_dismount(p, true)
		return true

	if GestureInputManager.is_action_just_pressed(String(ACTION_CROUCH)):
		_perform_dismount(p, false)
		return true

	if (
		_elapsed_time >= INTERACT_DISMOUNT_GRACE
		and GestureInputManager.is_action_just_pressed(String(ACTION_INTERACT))
	):
		_perform_dismount(p, false)
		return true

	return false


## Launches or drops the player into [StateAir], combining swing, rail, and crane momentum.
func _perform_dismount(p: Player, is_jump: bool) -> void:
	print("StateJibCrane: Dismounting from crane jib (jump=", is_jump, ").")
	var crane_tangential_vel: Vector3 = Vector3.ZERO
	var rail_dir: Vector3 = Vector3.FORWARD
	if is_instance_valid(_crane):
		crane_tangential_vel = _crane.get_rail_point_velocity(_current_rail_offset)
		rail_dir = _crane.get_rail_world_direction()

	var rail_perp: Vector3 = Vector3(-rail_dir.z, 0.0, rail_dir.x)
	var rail_linear_vel: Vector3 = rail_dir * _current_rail_speed
	var swing_linear_speed: float = _swing_angular_vel * SWING_ARM_LENGTH * cos(_swing_angle_rad)
	var swing_vel_world: Vector3 = rail_perp * swing_linear_speed
	var release_dir: Vector3 = Vector3.ZERO

	if is_jump:
		var flat_fwd: Vector3 = _get_flat_camera_forward(p)
		var swing_energy: float = clampf(
			(absf(_swing_angle_rad) / MAX_SWING_ANGLE_RAD) + (absf(_swing_angular_vel) / 3.2),
			0.0,
			1.0
		)
		var launch_horiz_speed: float = lerpf(
			JUMP_HORIZONTAL_SPEED, SWING_LAUNCH_MAX_HORIZ_SPEED, swing_energy
		)
		var forward_aligned_swing: Vector3 = swing_vel_world
		if forward_aligned_swing.dot(flat_fwd) < 0.0:
			forward_aligned_swing = flat_fwd * (swing_vel_world.length() * 0.65)

		var horiz_vel: Vector3 = (
			crane_tangential_vel
			+ (rail_linear_vel * 0.35)
			+ (forward_aligned_swing * 0.55)
			+ (flat_fwd * launch_horiz_speed)
		)
		var horiz_flat: Vector3 = Vector3(horiz_vel.x, 0.0, horiz_vel.z)
		if horiz_flat.length() > SWING_LAUNCH_MAX_HORIZ_SPEED:
			horiz_flat = horiz_flat.normalized() * SWING_LAUNCH_MAX_HORIZ_SPEED

		p.velocity.x = horiz_flat.x
		p.velocity.z = horiz_flat.z
		p.velocity.y = JUMP_VERTICAL_SPEED + (SWING_LAUNCH_BONUS_UP * swing_energy)
		release_dir = flat_fwd
	else:
		p.velocity.x = (
			crane_tangential_vel.x + (rail_linear_vel.x * 0.5) + (swing_vel_world.x * 0.5)
		)
		p.velocity.z = (
			crane_tangential_vel.z + (rail_linear_vel.z * 0.5) + (swing_vel_world.z * 0.5)
		)
		p.velocity.y = DROP_VERTICAL_SPEED
		var combined_flat: Vector3 = Vector3(p.velocity.x, 0.0, p.velocity.z)
		if combined_flat.length_squared() > 0.01:
			release_dir = combined_flat.normalized()

	_transition_msg.clear()
	_transition_msg[KEY_JUMP] = is_jump
	if release_dir.length_squared() > 0.001:
		_transition_msg[KEY_RELEASE_DIR] = release_dir
	state_machine.transition_to(STATE_AIR, _transition_msg)


## Toggles collision exceptions between [param p] and the crane bodies while hanging.
func _set_crane_collision_exceptions(p: Player, ignore: bool) -> void:
	if not is_instance_valid(_crane) or not is_instance_valid(p):
		return
	var wheel_body: PhysicsBody3D = _crane.wheel as PhysicsBody3D
	if is_instance_valid(wheel_body):
		if ignore:
			wheel_body.add_collision_exception_with(p)
		else:
			wheel_body.remove_collision_exception_with(p)
	if is_instance_valid(_crane._jib_grab_body):
		if ignore:
			_crane._jib_grab_body.add_collision_exception_with(p)
		else:
			_crane._jib_grab_body.remove_collision_exception_with(p)


## Enables or disables the player's [VaultController] while mounted on the jib rail.
func _set_vault_controller_enabled(p: Player, enabled: bool) -> void:
	if not is_instance_valid(p):
		return
	var vc: VaultController = (
		NodeQuery.find_first_child_of_type(p, VaultController) as VaultController
	)
	if not is_instance_valid(vc):
		return
	vc.auto_scan = enabled
	if not enabled:
		vc.can_vault_current_ledge = false
		if is_instance_valid(Events):
			Events.vault_prompt_updated.emit(false, Vector3.ZERO)


## Applies subtle camera roll and swing pitch feedback to the player's eyes node.
func _update_camera_feedback(p: Player, along_input: float, delta: float) -> void:
	var cam_ctrl: CameraController = p.camera_controller
	if not is_instance_valid(cam_ctrl) or not is_instance_valid(cam_ctrl.eyes):
		return
	var eyes_node: Node3D = cam_ctrl.eyes
	var target_roll: float = deg_to_rad(-along_input * MAX_SHIMMY_ROLL_DEG)
	var weight: float = 1.0 - exp(-CAMERA_ROLL_LERP_SPEED * delta)
	_current_roll_rad = lerpf(_current_roll_rad, target_roll, weight)
	eyes_node.rotation.z = _current_roll_rad

	var target_pitch: float = deg_to_rad(
		(sin(_swing_angle_rad) / sin(MAX_SWING_ANGLE_RAD)) * MAX_SWING_PITCH_DEG
	)
	var prev_pitch: float = _current_swing_pitch_rad
	_current_swing_pitch_rad = lerpf(_current_swing_pitch_rad, target_pitch, weight)
	eyes_node.rotation.x += (_current_swing_pitch_rad - prev_pitch)


## Smoothly eases any residual camera roll and swing pitch back to zero on exit.
func _ease_camera_roll_to_zero(p: Player) -> void:
	var cam_ctrl: CameraController = p.camera_controller
	if not is_instance_valid(cam_ctrl) or not is_instance_valid(cam_ctrl.eyes):
		return
	var eyes_node: Node3D = cam_ctrl.eyes
	eyes_node.rotation.x -= _current_swing_pitch_rad
	_current_swing_pitch_rad = 0.0
	if is_zero_approx(eyes_node.rotation.z):
		return
	_roll_reset_tween = Utilities.reset_tween_ext(p, _roll_reset_tween)
	if is_instance_valid(_roll_reset_tween):
		(
			_roll_reset_tween
			. tween_property(eyes_node, "rotation:z", 0.0, 0.18)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)


## Updates [member WeaponInventoryComponent.can_fire] on the player's inventory.
func _set_weapon_can_fire(p: Player, allowed: bool) -> void:
	var inv: WeaponInventoryComponent = p.weapon_inventory_component
	if not is_instance_valid(inv) and is_instance_valid(p.interaction_component):
		inv = p.interaction_component.weapon_inventory
	if is_instance_valid(inv):
		inv.can_fire = allowed


## Drops heavy carried objects before mounting the overhead crane jib.
func _drop_heavy_items_if_needed(p: Player) -> void:
	var interact_comp: PlayerInteractionComponent = p.interaction_component
	if not is_instance_valid(interact_comp):
		return
	if (
		is_instance_valid(interact_comp.interaction_scanner)
		and interact_comp.interaction_scanner.is_heavy_lifting
	):
		interact_comp.interaction_scanner.drop_heavy_object_safely()
	elif is_instance_valid(interact_comp.held_item):
		interact_comp.drop_held_item()


## Returns the horizontal unit vector of the player's camera forward direction.
func _get_flat_camera_forward(p: Player) -> Vector3:
	if is_instance_valid(p.camera_controller):
		var fwd: Vector3 = p.camera_controller.get_camera_look_dir()
		var flat: Vector3 = Vector3(fwd.x, 0.0, fwd.z)
		if flat.length_squared() > 0.0001:
			return flat.normalized()
	var body_fwd: Vector3 = -p.global_transform.basis.z
	return Vector3(body_fwd.x, 0.0, body_fwd.z).normalized()


## Returns the horizontal unit vector of the player's camera right direction.
func _get_flat_camera_right(p: Player) -> Vector3:
	if is_instance_valid(p.camera_controller):
		var right: Vector3 = p.camera_controller.get_camera_right_dir()
		var flat: Vector3 = Vector3(right.x, 0.0, right.z)
		if flat.length_squared() > 0.0001:
			return flat.normalized()
	var body_right: Vector3 = p.global_transform.basis.x
	return Vector3(body_right.x, 0.0, body_right.z).normalized()


## Safely resolves the owning [Player] instance.
func _get_player() -> Player:
	return player if player is Player else null
