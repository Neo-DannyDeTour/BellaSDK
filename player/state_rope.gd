## Handles rigid chain climbing and analytic pendulum rope swinging in [StateRope].
class_name StateRope
extends PlayerState

# --------------------------------------
# CONSTANTS
# --------------------------------------

## Vertical climb speed along a chain in meters per second.
# shortcut: fixed constant, promote to ClimbRope3D export if per-instance speed is needed
const CHAIN_CLIMB_SPEED: float = 1.2

## Fast downward slide speed along a chain in meters per second.
const CHAIN_SLIDE_SPEED: float = 6.0

## Angular orbit speed around a chain in radians per second (~90 deg/s).
const CHAIN_ORBIT_SPEED: float = 1.5707963

## Horizontal standoff radius in meters from the chain axis to the player center.
const CHAIN_STANDOFF_RADIUS: float = 0.42

## Horizontal speed applied along flat camera forward when jumping off a chain.
const CHAIN_JUMP_HORIZONTAL: float = 7.0

## Vertical hop velocity applied when jumping off a chain.
const CHAIN_JUMP_VERTICAL: float = 4.5

## Downward slide speed along a swing rope in meters per second.
const SWING_SLIDE_SPEED: float = 4.0

## Tangential pump acceleration (m/s^2) when driving a swing with WASD.
# shortcut: fixed constant, promote to ClimbRope3D export if per-rope pump tuning is needed
const SWING_PUMP_ACCEL: float = 14.0

## Maximum swing angle in radians (75 deg) beyond which WASD pumping cuts off.
const SWING_MAX_PUMP_ANGLE_RAD: float = 1.3089969

## Passive angular velocity damping rate for the swing pendulum.
const SWING_DAMPING: float = 0.35

## Forward velocity boost added along flat camera look when launching from a swing.
const SWING_JUMP_FWD_BOOST: float = 5.5

## Base upward velocity added when launching from a swing rope.
const SWING_JUMP_BASE_UP: float = 4.2

## Additional upward velocity scaled by upward camera pitch on swing launch.
const SWING_JUMP_PITCH_UP: float = 2.8

## Maximum swing speed (m/s) below which the player is still enough to fire a weapon.
const SWING_STILL_SPEED_THRESHOLD: float = 0.75

## Maximum camera roll tilt in degrees during lateral swinging. Set 0.0 to disable.
const MAX_SWING_ROLL_DEG: float = 6.0

## Exponential smoothing rate for swing camera roll interpolation.
const CAMERA_ROLL_LERP_SPEED: float = 10.0

## Duration in seconds of holding slide at the bottom end before auto-dropping off.
const BOTTOM_HOLD_DROP_TIME: float = 0.15

## Vertical offset in meters from player origin to the hand grip point.
const HAND_HEIGHT_OFFSET: float = 1.35

## Exponential damping rate pulling the player onto the chain standoff cylinder.
const MOUNT_SNAP_SPEED: float = 18.0

## Per-rope cooldown in seconds applied when releasing or launching from a rope.
const REGRAB_COOLDOWN: float = 0.4

## Outward positional nudge in meters applied on jump dismount.
const DISMOUNT_SEPARATION: float = 0.25

## Minimum time in seconds after mounting before the interact key can dismount.
const INTERACT_DISMOUNT_GRACE: float = 0.20

## Target state name when dismounting into the air.
const STATE_AIR: StringName = &"Air"

## Transition dictionary key holding the [ClimbRope3D] instance.
const KEY_ROPE: StringName = &"rope"

## Transition dictionary key holding the initial grab distance below the anchor.
const KEY_GRAB_DISTANCE: StringName = &"grab_distance"

## Transition dictionary key indicating a jump dismount occurred.
const KEY_JUMP: StringName = &"jump"

## Transition dictionary key carrying the horizontal release direction vector.
const KEY_RELEASE_DIR: StringName = &"release_dir"

## Input action identifier for strafe left.
const ACTION_LEFT: StringName = &"left"

## Input action identifier for strafe right.
const ACTION_RIGHT: StringName = &"right"

## Input action identifier for move forward.
const ACTION_FORWARD: StringName = &"forward"

## Input action identifier for move backward.
const ACTION_BACKWARD: StringName = &"backward"

## Input action identifier for jumping off the rope.
const ACTION_JUMP: StringName = &"jump"

## Input action identifier for dropping from the rope.
const ACTION_INTERACT: StringName = &"interact"

## Input action identifier for crouching / fast sliding.
const ACTION_CROUCH: StringName = &"crouch"

## Input action identifier for sprinting (used for Sprint+S slide alias).
const ACTION_SPRINT: StringName = &"sprint"

# --------------------------------------
# PRIVATE VARIABLES
# --------------------------------------

## Currently mounted [ClimbRope3D] instance.
var _rope: ClimbRope3D = null

## Current distance in meters along the rope from the anchor to the player's hands.
var _grab_distance: float = 2.0

## Current horizontal orbit angle in radians around the chain axis.
var _orbit_angle: float = 0.0

## World-space tangential velocity of the hand grip point in SWING mode.
var _swing_velocity: Vector3 = Vector3.ZERO

## Accumulated time in seconds holding slide while clamped at the bottom end.
var _bottom_slide_timer: float = 0.0

## Time in seconds elapsed since entering [StateRope].
var _elapsed_time: float = 0.0

## Current smoothed camera roll angle in radians applied to the eyes pivot.
var _current_roll_rad: float = 0.0

## Tween easing the camera roll back to level upon exiting the state.
var _roll_reset_tween: Tween = null

## Reusable transition payload dictionary to prevent per-dismount allocations.
var _transition_msg: Dictionary = {}

# --------------------------------------
# LIFECYCLE & STATE HOOKS
# --------------------------------------


## Initializes rope attachment, drops heavy items, and seeds pendulum momentum.
func enter(msg: Dictionary = {}) -> void:
	print("StateRope: enter() called.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	var rope_candidate: ClimbRope3D = msg.get(KEY_ROPE) as ClimbRope3D
	if not is_instance_valid(rope_candidate):
		state_machine.transition_to(STATE_AIR)
		return

	_rope = rope_candidate
	_elapsed_time = 0.0
	_bottom_slide_timer = 0.0
	_current_roll_rad = 0.0

	if is_instance_valid(_roll_reset_tween):
		_roll_reset_tween.kill()
		_roll_reset_tween = null

	_drop_heavy_items_if_needed(p)

	var loco: PlayerLocomotionComponent = p.locomotion_component
	if is_instance_valid(loco):
		loco.crouching = false
		loco.sprint_active = false
		if is_instance_valid(loco.stair_controller):
			loco.stair_controller.set(&"is_enabled", false)

	var anchor: Vector3 = _rope.global_position
	var raw_dist: float = anchor.y - (p.global_position.y + HAND_HEIGHT_OFFSET)
	if msg.has(KEY_GRAB_DISTANCE):
		var msg_dist: Variant = msg[KEY_GRAB_DISTANCE]
		if msg_dist is float:
			raw_dist = msg_dist
	_grab_distance = _rope.clamp_grab_distance(raw_dist)

	if _rope.mode == ClimbRope3D.Mode.CHAIN:
		var radial: Vector3 = Vector3(
			p.global_position.x - anchor.x, 0.0, p.global_position.z - anchor.z
		)
		if radial.length_squared() > 0.001:
			_orbit_angle = atan2(radial.x, radial.z)
		else:
			var flat_back: Vector3 = -_get_flat_camera_forward(p)
			_orbit_angle = atan2(flat_back.x, flat_back.z)
		_swing_velocity = Vector3.ZERO
		p.velocity = Vector3.ZERO
		var hand_pt: Vector3 = Vector3(anchor.x, anchor.y - _grab_distance, anchor.z)
		_rope.set_hand_point(hand_pt, _grab_distance)
		_set_weapon_can_fire(p, true)
	else:
		var hand_pos: Vector3 = p.global_position + Vector3(0.0, HAND_HEIGHT_OFFSET, 0.0)
		var rel: Vector3 = hand_pos - anchor
		if rel.length_squared() < 0.001:
			rel = Vector3.DOWN * _grab_distance
		var radial_dir: Vector3 = rel.normalized()
		_swing_velocity = p.velocity - radial_dir * p.velocity.dot(radial_dir)
		p.velocity = Vector3.ZERO
		_rope.set_hand_point(anchor + radial_dir * _grab_distance, _grab_distance)
		_set_weapon_can_fire(p, _swing_velocity.length() < SWING_STILL_SPEED_THRESHOLD)


## Restores weapon firing, stair snapping, camera roll, and rope cooldown on exit.
func exit() -> void:
	print("StateRope: exit() called.")
	var p: Player = _get_player()
	if is_instance_valid(p):
		_set_weapon_can_fire(p, true)
		var loco: PlayerLocomotionComponent = p.locomotion_component
		if is_instance_valid(loco) and is_instance_valid(loco.stair_controller):
			loco.stair_controller.set(&"is_enabled", true)
		_ease_camera_roll_to_zero(p)

	if is_instance_valid(_rope):
		_rope.clear_hand_point()
		_rope.release(REGRAB_COOLDOWN)
	_rope = null


## Runs per-physics-frame dismount checks and mode-specific rope locomotion.
func physics_update(delta: float) -> void:
	var p: Player = _get_player()
	if not is_instance_valid(p) or not is_instance_valid(_rope) or p.is_dead:
		state_machine.transition_to(STATE_AIR)
		return

	_elapsed_time += delta

	var input_dir: Vector2 = GestureInputManager.get_vector(
		String(ACTION_LEFT), String(ACTION_RIGHT), String(ACTION_FORWARD), String(ACTION_BACKWARD)
	)
	var is_crouch_held: bool = GestureInputManager.is_action_pressed(String(ACTION_CROUCH))
	var is_sprint_held: bool = GestureInputManager.is_action_pressed(String(ACTION_SPRINT))
	var is_sliding: bool = is_crouch_held or (is_sprint_held and input_dir.y > 0.1)

	if _check_dismount(p):
		return

	if _rope.mode == ClimbRope3D.Mode.CHAIN:
		_update_chain_mode(p, delta, input_dir, is_sliding)
	else:
		_update_swing_mode(p, delta, input_dir, is_sliding)


# --------------------------------------
# PRIVATE METHODS: CHAIN MODE
# --------------------------------------


## Processes vertical climbing, orbiting, fast sliding, and firing gate on a chain.
func _update_chain_mode(p: Player, delta: float, input_dir: Vector2, is_sliding: bool) -> void:
	var min_dist: float = ClimbRope3D.MIN_GRAB_OFFSET
	var max_dist: float = maxf(min_dist, _rope.length - ClimbRope3D.BOTTOM_GRAB_MARGIN)
	var prev_dist: float = _grab_distance

	if is_sliding:
		_grab_distance = minf(max_dist, _grab_distance + CHAIN_SLIDE_SPEED * delta)
	elif absf(input_dir.y) > 0.05:
		_grab_distance = clampf(
			_grab_distance + input_dir.y * CHAIN_CLIMB_SPEED * delta, min_dist, max_dist
		)

	if absf(input_dir.x) > 0.05:
		_orbit_angle -= input_dir.x * CHAIN_ORBIT_SPEED * delta

	var anchor: Vector3 = _rope.global_position
	var radial_offset: Vector3 = (
		Vector3(sin(_orbit_angle), 0.0, cos(_orbit_angle)) * CHAIN_STANDOFF_RADIUS
	)
	var target_pos: Vector3 = Vector3(
		anchor.x + radial_offset.x,
		anchor.y - _grab_distance - HAND_HEIGHT_OFFSET,
		anchor.z + radial_offset.z
	)
	var smoothed_pos: Vector3 = MathUtils.damp_v3(
		p.global_position, target_pos, MOUNT_SNAP_SPEED, delta
	)
	p.velocity = (smoothed_pos - p.global_position) / maxf(delta, 0.0001)
	p.move_and_slide()
	p.velocity = Vector3.ZERO

	var moved_vertically: bool = absf(_grab_distance - prev_dist) > 0.0005
	var is_climbing_now: bool = (not is_sliding) and moved_vertically
	var is_sliding_now: bool = is_sliding and moved_vertically
	_rope.set_audio(is_climbing_now, is_sliding_now, 0.0)
	_rope.set_hand_point(Vector3(anchor.x, anchor.y - _grab_distance, anchor.z), _grab_distance)

	var is_still: bool = (
		(not is_sliding) and absf(input_dir.x) <= 0.05 and absf(input_dir.y) <= 0.05
	)
	_set_weapon_can_fire(p, is_still)

	var bob_input: Vector2 = input_dir if is_climbing_now else Vector2.ZERO
	_update_camera_and_roll(p, delta, bob_input, 0.0)

	if is_sliding and _grab_distance >= max_dist - 0.01:
		_bottom_slide_timer += delta
		if _bottom_slide_timer >= BOTTOM_HOLD_DROP_TIME:
			print("StateRope: Bottom slide hold completed on chain. Dropping off.")
			_dismount_drop(p, Vector3.ZERO)
	else:
		_bottom_slide_timer = 0.0


# --------------------------------------
# PRIVATE METHODS: SWING MODE
# --------------------------------------


## Processes analytic spherical pendulum motion, wall impacts, and camera roll.
func _update_swing_mode(p: Player, delta: float, input_dir: Vector2, is_sliding: bool) -> void:
	var min_dist: float = ClimbRope3D.MIN_GRAB_OFFSET
	var max_dist: float = maxf(min_dist, _rope.length - ClimbRope3D.BOTTOM_GRAB_MARGIN)
	var prev_dist: float = _grab_distance

	if is_sliding:
		_grab_distance = minf(max_dist, _grab_distance + SWING_SLIDE_SPEED * delta)

	var anchor: Vector3 = _rope.global_position
	var hand_offset: Vector3 = Vector3(0.0, HAND_HEIGHT_OFFSET, 0.0)
	var hand_pos: Vector3 = p.global_position + hand_offset
	var rel: Vector3 = hand_pos - anchor
	if rel.length_squared() < 0.001:
		rel = Vector3.DOWN * _grab_distance

	var radial_dir: Vector3 = rel.normalized()
	var swing_angle: float = acos(clampf(radial_dir.dot(Vector3.DOWN), -1.0, 1.0))

	var grav: float = _get_gravity(p)
	_swing_velocity.y -= grav * delta

	if (
		not is_sliding
		and input_dir.length_squared() > 0.001
		and swing_angle < SWING_MAX_PUMP_ANGLE_RAD
	):
		var cam_fwd: Vector3 = _get_flat_camera_forward(p)
		var cam_right: Vector3 = _get_flat_camera_right(p)
		var wish_dir: Vector3 = ((cam_fwd * -input_dir.y) + (cam_right * input_dir.x)).normalized()
		var tangent_wish: Vector3 = wish_dir - radial_dir * wish_dir.dot(radial_dir)
		if tangent_wish.length_squared() > 0.0001:
			_swing_velocity += tangent_wish.normalized() * (SWING_PUMP_ACCEL * delta)

	_swing_velocity *= maxf(0.0, 1.0 - (SWING_DAMPING * delta))
	_swing_velocity -= radial_dir * _swing_velocity.dot(radial_dir)

	var predicted_hand: Vector3 = hand_pos + (_swing_velocity * delta)
	var new_rel: Vector3 = predicted_hand - anchor
	if new_rel.length_squared() < 0.001:
		new_rel = Vector3.DOWN * _grab_distance

	var new_radial_dir: Vector3 = new_rel.normalized()
	if new_radial_dir.y > -0.05:
		new_radial_dir.y = -0.05
		new_radial_dir = new_radial_dir.normalized()

	var constrained_hand: Vector3 = anchor + (new_radial_dir * _grab_distance)
	var target_player_pos: Vector3 = constrained_hand - hand_offset

	p.velocity = (target_player_pos - p.global_position) / maxf(delta, 0.0001)
	p.move_and_slide()

	var col_count: int = p.get_slide_collision_count()
	if col_count > 0:
		for i: int in range(col_count):
			var col: KinematicCollision3D = p.get_slide_collision(i)
			if is_instance_valid(col):
				var n: Vector3 = col.get_normal()
				var into_wall: float = _swing_velocity.dot(n)
				if into_wall < 0.0:
					_swing_velocity -= n * into_wall

	var actual_hand: Vector3 = p.global_position + hand_offset
	var post_rel: Vector3 = actual_hand - anchor
	if post_rel.length_squared() > 0.001:
		var post_dir: Vector3 = post_rel.normalized()
		_swing_velocity -= post_dir * _swing_velocity.dot(post_dir)
		actual_hand = anchor + (post_dir * _grab_distance)
		p.global_position = actual_hand - hand_offset
	p.velocity = Vector3.ZERO

	_rope.set_hand_point(actual_hand, _grab_distance)

	var swing_speed: float = _swing_velocity.length()
	var is_sliding_now: bool = is_sliding and absf(_grab_distance - prev_dist) > 0.0005
	_rope.set_audio(false, is_sliding_now, swing_speed)

	var can_shoot_now: bool = (not is_sliding) and (swing_speed < SWING_STILL_SPEED_THRESHOLD)
	_set_weapon_can_fire(p, can_shoot_now)

	var rope_up: Vector3 = (anchor - actual_hand).normalized()
	var cam_right_vec: Vector3 = _get_flat_camera_right(p)
	var side_dot: float = clampf(rope_up.dot(cam_right_vec), -1.0, 1.0)
	var raw_roll_deg: float = clampf(
		rad_to_deg(asin(side_dot)), -MAX_SWING_ROLL_DEG, MAX_SWING_ROLL_DEG
	)
	_update_camera_and_roll(p, delta, Vector2.ZERO, deg_to_rad(raw_roll_deg))

	if is_sliding and _grab_distance >= max_dist - 0.01:
		_bottom_slide_timer += delta
		if _bottom_slide_timer >= BOTTOM_HOLD_DROP_TIME:
			print("StateRope: Bottom slide hold completed on swing rope. Dropping off.")
			_dismount_drop(p, _swing_velocity)
	else:
		_bottom_slide_timer = 0.0


# --------------------------------------
# PRIVATE METHODS: DISMOUNTING
# --------------------------------------


## Polls jump and interact inputs to execute launch or drop dismounts.
func _check_dismount(p: Player) -> bool:
	var jump_pressed: bool = (
		GestureInputManager.is_action_just_pressed(String(ACTION_JUMP))
		or Input.is_action_just_pressed(ACTION_JUMP)
	)
	if jump_pressed:
		var flat_fwd: Vector3 = _get_flat_camera_forward(p)
		if _rope.mode == ClimbRope3D.Mode.CHAIN:
			var chain_vel: Vector3 = (
				(flat_fwd * CHAIN_JUMP_HORIZONTAL) + Vector3(0.0, CHAIN_JUMP_VERTICAL, 0.0)
			)
			p.global_position += flat_fwd * DISMOUNT_SEPARATION
			_dismount_jump(p, chain_vel, flat_fwd)
		else:
			var look_dir: Vector3 = _get_camera_look_dir(p)
			var pitch_up: float = clampf(look_dir.y, 0.0, 1.0) * SWING_JUMP_PITCH_UP
			var up_vel: float = SWING_JUMP_BASE_UP + pitch_up
			var swing_vel: Vector3 = (
				_swing_velocity + (flat_fwd * SWING_JUMP_FWD_BOOST) + Vector3(0.0, up_vel, 0.0)
			)
			p.global_position += flat_fwd * DISMOUNT_SEPARATION
			_dismount_jump(p, swing_vel, flat_fwd)
		return true

	if _elapsed_time >= INTERACT_DISMOUNT_GRACE:
		var interact_pressed: bool = (
			GestureInputManager.consume_buffered_action(String(ACTION_INTERACT))
			or Input.is_action_just_pressed(ACTION_INTERACT)
		)
		if interact_pressed:
			var carry_vel: Vector3 = (
				_swing_velocity if _rope.mode == ClimbRope3D.Mode.SWING else Vector3.ZERO
			)
			_dismount_drop(p, carry_vel)
			return true

	return false


## Applies launch velocity [param launch_vel] and transitions into [StateAir].
func _dismount_jump(p: Player, launch_vel: Vector3, release_dir: Vector3) -> void:
	print("StateRope: Executing jump dismount.")
	p.velocity = launch_vel
	var loco: PlayerLocomotionComponent = p.locomotion_component
	if is_instance_valid(loco) and release_dir.length_squared() > 0.001:
		loco.set_direction(release_dir)

	_transition_msg.clear()
	_transition_msg[KEY_JUMP] = true
	_transition_msg[KEY_RELEASE_DIR] = release_dir
	state_machine.transition_to(STATE_AIR, _transition_msg)


## Releases the rope without a jump impulse and transitions into [StateAir].
func _dismount_drop(p: Player, carry_velocity: Vector3) -> void:
	print("StateRope: Executing drop dismount.")
	p.velocity = carry_velocity
	var flat_dir: Vector3 = Vector3(carry_velocity.x, 0.0, carry_velocity.z)
	var loco: PlayerLocomotionComponent = p.locomotion_component
	if is_instance_valid(loco) and flat_dir.length_squared() > 0.01:
		loco.set_direction(flat_dir.normalized())

	_transition_msg.clear()
	if flat_dir.length_squared() > 0.01:
		_transition_msg[KEY_RELEASE_DIR] = flat_dir.normalized()
	state_machine.transition_to(STATE_AIR, _transition_msg)


# --------------------------------------
# PRIVATE METHODS: HELPERS
# --------------------------------------


## Returns the owning character cast to [Player] or null.
func _get_player() -> Player:
	return player as Player


## Safely drops any held item or heavy object when mounting a rope.
func _drop_heavy_items_if_needed(p: Player) -> void:
	var interact: PlayerInteractionComponent = p.interaction_component
	if not is_instance_valid(interact):
		return
	if (
		is_instance_valid(interact.interaction_scanner)
		and interact.interaction_scanner.is_heavy_lifting
	):
		interact.interaction_scanner.drop_heavy_object_safely()
	elif is_instance_valid(interact.held_item):
		interact.drop_held_item()


## Updates [member WeaponInventoryComponent.can_fire] on the player's inventory.
func _set_weapon_can_fire(p: Player, allowed: bool) -> void:
	var inv: WeaponInventoryComponent = p.weapon_inventory_component
	if not is_instance_valid(inv) and is_instance_valid(p.interaction_component):
		inv = p.interaction_component.weapon_inventory
	if is_instance_valid(inv):
		inv.can_fire = allowed


## Returns the active gravity scalar from [PlayerLocomotionComponent].
func _get_gravity(p: Player) -> float:
	if is_instance_valid(p.locomotion_component):
		return p.locomotion_component.gravity
	return 9.8


## Returns the 3D forward unit vector of the active player camera.
func _get_camera_look_dir(p: Player) -> Vector3:
	if is_instance_valid(p.camera_controller):
		return p.camera_controller.get_camera_look_dir().normalized()
	return -p.global_transform.basis.z.normalized()


## Returns the horizontal forward unit vector of the active player camera.
func _get_flat_camera_forward(p: Player) -> Vector3:
	var look: Vector3 = _get_camera_look_dir(p)
	var flat: Vector3 = Vector3(look.x, 0.0, look.z)
	if flat.length_squared() > 0.0001:
		return flat.normalized()
	var body_fwd: Vector3 = -p.global_transform.basis.z
	return Vector3(body_fwd.x, 0.0, body_fwd.z).normalized()


## Returns the horizontal right unit vector of the active player camera.
func _get_flat_camera_right(p: Player) -> Vector3:
	var fwd: Vector3 = _get_flat_camera_forward(p)
	return fwd.cross(Vector3.UP).normalized()


## Updates camera FOV/headbob and applies smoothed swing roll to the eyes pivot.
func _update_camera_and_roll(
	p: Player, delta: float, bob_input: Vector2, target_roll_rad: float
) -> void:
	var cam_ctrl: CameraController = p.camera_controller
	if not is_instance_valid(cam_ctrl):
		return

	var spd: float = 4.0 if bob_input != Vector2.ZERO else 0.0
	cam_ctrl.update_camera(delta, bob_input, false, false, false, spd)

	var effective_target: float = 0.0 if cam_ctrl.reduce_motion else target_roll_rad
	_current_roll_rad = MathUtils.damp(
		_current_roll_rad, effective_target, CAMERA_ROLL_LERP_SPEED, delta
	)
	if is_instance_valid(cam_ctrl.eyes):
		cam_ctrl.eyes.rotation.z = _current_roll_rad


## Smoothly tweens the camera eyes roll angle back to zero upon state exit.
func _ease_camera_roll_to_zero(p: Player) -> void:
	var cam_ctrl: CameraController = p.camera_controller
	if not is_instance_valid(cam_ctrl) or not is_instance_valid(cam_ctrl.eyes):
		return
	if is_instance_valid(_roll_reset_tween):
		_roll_reset_tween.kill()
	_roll_reset_tween = create_tween()
	(
		_roll_reset_tween
		. tween_property(cam_ctrl.eyes, "rotation:z", 0.0, 0.25)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
