## Handles zipline transit, auto-sliding, and dismount kinematics in [StateZipline].
class_name StateZipline
extends PlayerState

## Base traversal speed along the zipline cable path.
const ZIPLINE_SLIDE_SPEED: float = 8.0

## Vertical downward offset below cable anchor point for player hands.
const ZIPLINE_HANG_OFFSET: float = 2.0

## Velocity multiplier applied to momentum upon zipline detachment.
const DETACH_MOMENTUM_MULTIPLIER: float = 1.1

## Active zipline [Node3D] instance currently ridden by player.
var current_zipline: Node3D = null

## Global origin anchor position of the active zipline cable.
var zipline_start: Vector3 = Vector3.ZERO

## Global termination anchor position of the active zipline cable.
var zipline_end: Vector3 = Vector3.ZERO

## Normalized direction vector pointing from start to end of zipline.
var zipline_dir: Vector3 = Vector3.ZERO

## Total world-space length in meters of the active zipline cable.
var zipline_length: float = 0.0

## Normalized scalar progress along zipline cable from 0.0 to 1.0.
var zipline_progress: float = 0.0

## Indicates whether player is automatically sliding downhill on zipline.
var is_auto_sliding: bool = false

## Indicates if attachment tween transition is currently in progress.
var is_zipline_transitioning: bool = false

## Elapsed time since attaching to zipline to prevent instant dismount.
var zipline_grace_timer: float = 0.0

## Reusable transition payload dictionary to avoid runtime allocations.
var _transition_msg: Dictionary = {}


## Attaches player to zipline and initializes cable progression metrics.
func enter(msg: Dictionary = {}) -> void:
	print("StateZipline: enter() called. Player mounting zipline.")
	if not msg.has(&"zipline_node") or not msg.has(&"start_pos") or not msg.has(&"end_pos"):
		state_machine.transition_to(&"Air")
		return

	current_zipline = msg[&"zipline_node"] as Node3D
	zipline_start = msg[&"start_pos"] as Vector3
	zipline_end = msg[&"end_pos"] as Vector3

	zipline_dir = (zipline_end - zipline_start).normalized()
	zipline_length = zipline_start.distance_to(zipline_end)
	zipline_grace_timer = 0.0
	is_zipline_transitioning = true

	_calculate_initial_progress()
	_perform_attach_tween()


## Restores camera angles and cleans up zipline attachment state.
func exit() -> void:
	print("StateZipline: exit() called. Player dismounting zipline.")
	current_zipline = null
	is_zipline_transitioning = false
	player.scale = Vector3.ONE

	var p: Player = player as Player
	var detach_tween: Tween = create_tween().set_parallel(true)

	if is_instance_valid(p) and is_instance_valid(p.camera_controller):
		var cam_ctrl: CameraController = p.camera_controller
		if is_instance_valid(cam_ctrl.head):
			detach_tween.tween_property(cam_ctrl.head, "rotation:x", 0.0, 0.15).set_trans(
				Tween.TRANS_SINE
			)
		if is_instance_valid(cam_ctrl.eyes):
			detach_tween.tween_property(cam_ctrl.eyes, "rotation:z", 0.0, 0.15).set_trans(
				Tween.TRANS_SINE
			)


## Updates traversal progress, camera orientation, and dismount conditions.
func physics_update(delta: float) -> void:
	print("StateZipline: physics_update() processing zipline traversal.")
	if is_zipline_transitioning:
		return

	zipline_grace_timer += delta

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	_calculate_movement(delta, input_dir)
	_apply_position()

	var p: Player = player as Player
	if is_instance_valid(p) and is_instance_valid(p.camera_controller):
		p.camera_controller.update_camera(
			delta, input_dir, false, false, false, ZIPLINE_SLIDE_SPEED
		)

	_check_dismount_conditions()


## Calculates initial cable progress ratio based on player attachment point.
func _calculate_initial_progress() -> void:
	print("StateZipline: _calculate_initial_progress() projecting player position.")
	var line_vec: Vector3 = zipline_end - zipline_start
	var player_vec: Vector3 = player.global_position - zipline_start
	var t: float = player_vec.dot(line_vec) / line_vec.length_squared()
	zipline_progress = clampf(t, 0.0, 1.0)

	var is_start_highest: bool = zipline_start.y > zipline_end.y
	var top_progress: float = 0.0 if is_start_highest else 1.0
	var grabbed_at_top: bool = absf(zipline_progress - top_progress) < 0.10

	is_auto_sliding = grabbed_at_top
	player.velocity = Vector3.ZERO
	player.scale = Vector3.ONE


## Tweens player position and yaw orientation smoothly onto zipline cable.
func _perform_attach_tween() -> void:
	print("StateZipline: _perform_attach_tween() tweening character to cable.")
	var real_target_pos: Vector3 = zipline_start.lerp(zipline_end, zipline_progress)
	real_target_pos.y -= ZIPLINE_HANG_OFFSET

	var attach_tween: Tween = create_tween().set_parallel(true)
	attach_tween.tween_property(player, "global_position", real_target_pos, 0.25).set_trans(
		Tween.TRANS_SINE
	)

	if is_auto_sliding:
		var is_start_highest: bool = zipline_start.y > zipline_end.y
		var downhill_dir: Vector3 = zipline_dir if is_start_highest else -zipline_dir

		var flat_dir: Vector3 = Vector3(downhill_dir.x, 0.0, downhill_dir.z).normalized()
		if flat_dir.length_squared() < 0.01:
			flat_dir = Vector3.FORWARD

		var target_yaw_quat: Quaternion = (
			Basis.looking_at(flat_dir, Vector3.UP).get_rotation_quaternion()
		)
		attach_tween.tween_property(player, "quaternion", target_yaw_quat, 0.25).set_trans(
			Tween.TRANS_SINE
		)

		var pitch_angle: float = asin(downhill_dir.y)
		var p: Player = player as Player
		if is_instance_valid(p) and is_instance_valid(p.camera_controller):
			var cam_ctrl: CameraController = p.camera_controller
			if is_instance_valid(cam_ctrl.head):
				(
					attach_tween
					. tween_property(cam_ctrl.head, "rotation:x", pitch_angle, 0.25)
					. set_trans(Tween.TRANS_SINE)
				)

	attach_tween.set_parallel(false)
	attach_tween.tween_callback(_on_attach_tween_finished)


## Callback triggered when attachment tween finishes to enable physics updates.
func _on_attach_tween_finished() -> void:
	print("StateZipline: _on_attach_tween_finished() cable connection complete.")
	is_zipline_transitioning = false


## Computes frame traversal progression based on look angle and inputs.
func _calculate_movement(delta: float, input_dir: Vector2) -> void:
	print("StateZipline: _calculate_movement() computing travel step.")
	var downhill_sign: float = 1.0 if zipline_dir.y < 0.0 else -1.0
	var downhill_vector: Vector3 = zipline_dir * downhill_sign

	var p: Player = player as Player
	var look_forward: Vector3 = Vector3.FORWARD
	if is_instance_valid(p) and is_instance_valid(p.camera_controller):
		look_forward = p.camera_controller.get_camera_look_dir()

	var look_dot_downhill: float = look_forward.dot(downhill_vector)

	var is_looking_downhill: bool = look_dot_downhill > 0.1
	var is_looking_uphill: bool = look_dot_downhill < -0.1

	var is_pressing_w: bool = input_dir.y < -0.1
	var is_pressing_s: bool = input_dir.y > 0.1
	var frame_movement: float = 0.0

	if is_auto_sliding:
		var fast_slide_speed: float = ZIPLINE_SLIDE_SPEED * 1.8
		frame_movement = (downhill_sign * (fast_slide_speed / zipline_length) * delta)
	else:
		if is_looking_downhill and is_pressing_w:
			is_auto_sliding = true
		else:
			var climb_speed: float = 4.0
			var climb_amount: float = (climb_speed / zipline_length) * delta

			if is_looking_uphill and is_pressing_w:
				frame_movement = -downhill_sign * climb_amount
			elif is_looking_downhill and is_pressing_s:
				frame_movement = -downhill_sign * climb_amount
			elif is_looking_uphill and is_pressing_s:
				frame_movement = downhill_sign * climb_amount

	zipline_progress += frame_movement
	zipline_progress = clampf(zipline_progress, 0.0, 1.0)


## Applies interpolated position along zipline cable to player transform.
func _apply_position() -> void:
	print("StateZipline: _apply_position() snapping player to cable coordinate.")
	var target_pos: Vector3 = zipline_start.lerp(zipline_end, zipline_progress)
	target_pos.y -= ZIPLINE_HANG_OFFSET
	player.global_position = target_pos
	player.velocity = Vector3.ZERO


## Evaluates cable termination and player input triggers for dismount.
func _check_dismount_conditions() -> void:
	print("StateZipline: _check_dismount_conditions() polling exit inputs.")
	var hit_end: bool = (
		zipline_grace_timer > 0.5 and (zipline_progress >= 0.999 or zipline_progress <= 0.001)
	)
	var pressed_jump: bool = GestureInputManager.is_action_just_pressed(&"jump")
	var pressed_crouch: bool = GestureInputManager.is_action_just_pressed(&"crouch")

	if hit_end or pressed_jump or pressed_crouch:
		_perform_dismount()


## Applies exit launch impulse and transitions machine into [StateAir].
func _perform_dismount() -> void:
	print("StateZipline: _perform_dismount() releasing from zipline.")
	var p: Player = player as Player
	if is_instance_valid(p) and is_instance_valid(p.environment_component):
		var env: PlayerEnvironmentComponent = p.environment_component
		env.start_zipline_cooldown(0.5)

	var zip_vel: Vector3 = Vector3.ZERO
	if (
		is_instance_valid(current_zipline)
		and current_zipline.has_method(&"get_current_travel_velocity")
	):
		zip_vel = (current_zipline.call(&"get_current_travel_velocity") as Vector3)

	if zip_vel.length_squared() < 4.0:
		var look_dir: Vector3 = Vector3.FORWARD
		if is_instance_valid(p) and is_instance_valid(p.camera_controller):
			look_dir = p.camera_controller.get_camera_look_dir()
		var launch_flat_fwd: Vector3 = Vector3(look_dir.x, 0.0, look_dir.z).normalized()

		if launch_flat_fwd.length_squared() < 0.01:
			launch_flat_fwd = Vector3.FORWARD

		zip_vel = (
			(launch_flat_fwd * ZIPLINE_SLIDE_SPEED) + Vector3(0.0, -ZIPLINE_SLIDE_SPEED * 0.5, 0.0)
		)

	player.velocity = zip_vel * DETACH_MOMENTUM_MULTIPLIER

	var flat_vel: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var release_dir: Vector3 = Vector3.ZERO
	if flat_vel.length_squared() > 0.0:
		release_dir = flat_vel.normalized()

	if GestureInputManager.is_action_just_pressed(&"jump"):
		player.velocity.y += 5.0

	if is_instance_valid(current_zipline) and current_zipline.has_method(&"on_player_released"):
		current_zipline.call(&"on_player_released")

	_transition_msg.clear()
	if release_dir != Vector3.ZERO:
		_transition_msg[&"release_dir"] = release_dir
	state_machine.transition_to(&"Air", _transition_msg)
