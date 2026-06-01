class_name StateZipline
extends PlayerState

# --------------------------------------
# CONSTANTS
# --------------------------------------
const ZIPLINE_SLIDE_SPEED: float = 8.0
const ZIPLINE_HANG_OFFSET: float = 2.0
const DETACH_MOMENTUM_MULTIPLIER: float = 1.1

# --------------------------------------
# VARIABLES
# --------------------------------------
var current_zipline: Node3D = null
var zipline_start: Vector3 = Vector3.ZERO
var zipline_end: Vector3 = Vector3.ZERO
var zipline_dir: Vector3 = Vector3.ZERO
var zipline_length: float = 0.0
var zipline_progress: float = 0.0

var is_auto_sliding: bool = false
var is_zipline_transitioning: bool = false
var zipline_grace_timer: float = 0.0


func enter(msg: Dictionary = {}) -> void:
	if not msg.has("zipline_node") or not msg.has("start_pos") or not msg.has("end_pos"):
		state_machine.transition_to("Air")
		return

	current_zipline = msg["zipline_node"]
	zipline_start = msg["start_pos"]
	zipline_end = msg["end_pos"]
	
	zipline_dir = (zipline_end - zipline_start).normalized()
	zipline_length = zipline_start.distance_to(zipline_end)
	zipline_grace_timer = 0.0
	is_zipline_transitioning = true

	_calculate_initial_progress()
	_perform_attach_tween()


func exit() -> void:
	current_zipline = null
	is_zipline_transitioning = false
	player.scale = Vector3.ONE

	# Fix "Standing Up" on release to ensure the camera is upright
	var current_fwd: Vector3 = -player.global_transform.basis.z
	var flat_fwd: Vector3 = Vector3(current_fwd.x, 0.0, current_fwd.z).normalized()
	if flat_fwd.length_squared() < 0.01:
		flat_fwd = Vector3.FORWARD

	var upright_basis := Basis.looking_at(flat_fwd, Vector3.UP)
	var detach_tween := create_tween().set_parallel(true)
	(detach_tween.tween_property(player, "quaternion", upright_basis.get_rotation_quaternion(), 0.15)
		.set_trans(Tween.TRANS_SINE))
	detach_tween.tween_property(player.eyes, "rotation:z", 0.0, 0.15)


func physics_update(delta: float) -> void:
	if is_zipline_transitioning:
		return

	zipline_grace_timer += delta

	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	
	_calculate_movement(delta, input_dir)
	_apply_position()
	
	# Update camera (passing 0 velocity since we override position directly)
	player.camera_controller.update_camera(
		delta, 
		input_dir, 
		false, # is_sprinting
		false, # is_crouching
		false, # is_grounded
		ZIPLINE_SLIDE_SPEED # Fake speed for headbob scaling
	)

	_check_dismount_conditions()


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _calculate_initial_progress() -> void:
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


func _perform_attach_tween() -> void:
	var real_target_pos: Vector3 = zipline_start.lerp(zipline_end, zipline_progress)
	real_target_pos.y -= ZIPLINE_HANG_OFFSET

	var attach_tween := create_tween().set_parallel(true)
	(attach_tween.tween_property(player, "global_position", real_target_pos, 0.25)
		.set_trans(Tween.TRANS_SINE))

	if is_auto_sliding:
		var is_start_highest: bool = zipline_start.y > zipline_end.y
		var downhill_dir: Vector3 = zipline_dir if is_start_highest else -zipline_dir
		var target_quat: Quaternion = Basis.looking_at(downhill_dir, Vector3.UP).get_rotation_quaternion()
		(attach_tween.tween_property(player, "quaternion", target_quat, 0.25)
			.set_trans(Tween.TRANS_SINE))

	attach_tween.set_parallel(false)
	attach_tween.tween_callback(func() -> void: is_zipline_transitioning = false)


func _calculate_movement(delta: float, input_dir: Vector2) -> void:
	var downhill_sign: float = 1.0 if zipline_dir.y < 0.0 else -1.0
	var downhill_vector: Vector3 = zipline_dir * downhill_sign

	var look_forward: Vector3 = -player.camera.global_transform.basis.z
	var look_dot_downhill: float = look_forward.dot(downhill_vector)

	var is_looking_downhill: bool = look_dot_downhill > 0.1
	var is_looking_uphill: bool = look_dot_downhill < -0.1

	var is_pressing_w: bool = input_dir.y < -0.1
	var is_pressing_s: bool = input_dir.y > 0.1

	var frame_movement: float = 0.0

	if is_auto_sliding:
		var fast_slide_speed: float = ZIPLINE_SLIDE_SPEED * 1.8
		frame_movement = downhill_sign * (fast_slide_speed / zipline_length) * delta
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


func _apply_position() -> void:
	var target_pos: Vector3 = zipline_start.lerp(zipline_end, zipline_progress)
	target_pos.y -= ZIPLINE_HANG_OFFSET
	player.global_position = target_pos
	player.velocity = Vector3.ZERO


func _check_dismount_conditions() -> void:
	var hit_end: bool = zipline_grace_timer > 0.5 and (zipline_progress >= 0.999 or zipline_progress <= 0.001)
	var pressed_jump: bool = Input.is_action_just_pressed("jump")
	var pressed_crouch: bool = Input.is_action_just_pressed("crouch")

	if hit_end or pressed_jump or pressed_crouch:
		_perform_dismount()


func _perform_dismount() -> void:
	player.zipline_cooldown = 0.5
	
	var zip_vel: Vector3 = Vector3.ZERO
	if current_zipline and current_zipline.has_method("get_current_travel_velocity"):
		zip_vel = current_zipline.get_current_travel_velocity()

	# If we hit the absolute end, the cable velocity is 0.
	# We guarantee a forward and downward launch!
	if zip_vel.length() < 2.0:
		var look_dir: Vector3 = -player.camera.global_transform.basis.z
		var launch_flat_fwd: Vector3 = Vector3(look_dir.x, 0.0, look_dir.z).normalized()
		
		if launch_flat_fwd.length_squared() < 0.01:
			launch_flat_fwd = Vector3.FORWARD
			
		zip_vel = (launch_flat_fwd * ZIPLINE_SLIDE_SPEED) + Vector3(0.0, -ZIPLINE_SLIDE_SPEED * 0.5, 0.0)

	player.velocity = zip_vel * DETACH_MOMENTUM_MULTIPLIER

	var flat_vel: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if flat_vel.length() > 0.0:
		player.direction = flat_vel.normalized()

	if Input.is_action_just_pressed("jump"):
		player.velocity.y += 5.0

	if current_zipline and current_zipline.has_method("on_player_released"):
		current_zipline.on_player_released()

	state_machine.transition_to("Air")
