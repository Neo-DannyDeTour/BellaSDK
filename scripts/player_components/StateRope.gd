class_name StateRope
extends PlayerState

# --------------------------------------
# CONSTANTS
# --------------------------------------
const ROPE_CLIMB_SPEED: float = 1.0

# --------------------------------------
# VARIABLES
# --------------------------------------
var current_rope: RigidBody3D = null
var rope_offset: float = 0.0
var rope_lerp_weight: float = 0.0


func enter(msg: Dictionary = {}) -> void:
	if not msg.has("rope_node"):
		state_machine.transition_to("Air")
		return

	current_rope = msg["rope_node"]

	var rope_root: Node3D = current_rope.get_parent() as Node3D
	var can_swing: bool = (
		rope_root.get("is_swingable") as bool if "is_swingable" in rope_root else false
	)

	# 1. Momentum Transfer
	if can_swing:
		var entry_momentum := Vector3(player.velocity.x, player.velocity.y * 0.2, player.velocity.z)
		current_rope.apply_impulse(
			entry_momentum * 1.5, player.global_position - current_rope.global_position
		)

	# 2. Lock Player Physics
	player.velocity = Vector3.ZERO
	player.add_collision_exception_with(current_rope)
	rope_lerp_weight = 4.0

	# 3. Calculate Limits & Grab Offset
	var local_pos: Vector3 = current_rope.to_local(player.global_position)
	rope_offset = local_pos.y

	var local_top: float = current_rope.to_local(rope_root.global_position).y
	var max_length: float = (
		rope_root.get("rope_length") as float if "rope_length" in rope_root else 10.0
	)

	var top_limit: float = local_top - 2.5
	var bottom_limit: float = local_top - max_length + 0.5
	rope_offset = clampf(rope_offset, bottom_limit, top_limit)

	# 4. Smoothly turn the camera to face the rope
	var face_pos := Vector3(
		current_rope.global_position.x, player.global_position.y, current_rope.global_position.z
	)
	if player.global_position.distance_to(face_pos) > 0.1:
		var target_transform := player.global_transform.looking_at(face_pos, Vector3.UP)
		var tween := create_tween()
		(
			tween
			. tween_property(
				player, "quaternion", target_transform.basis.get_rotation_quaternion(), 0.3
			)
			. set_trans(Tween.TRANS_SINE)
		)


func exit() -> void:
	if current_rope:
		player.remove_collision_exception_with(current_rope)

		var rope_root: Node3D = current_rope.get_parent() as Node3D
		if rope_root and rope_root.has_method("on_player_released"):
			rope_root.call("on_player_released")

	current_rope = null

	# Smoothly restore camera upright
	var release_forward: Vector3 = (
		Vector3(-player.global_transform.basis.z.x, 0.0, -player.global_transform.basis.z.z)
		. normalized()
	)
	if release_forward.length_squared() < 0.001:
		release_forward = -player.global_transform.basis.z

	var target_basis := Basis.looking_at(release_forward, Vector3.UP)
	var release_tween := create_tween().set_parallel(true)

	(
		release_tween
		. tween_property(player, "quaternion", target_basis.get_rotation_quaternion(), 0.3)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)

	(
		release_tween
		. tween_property(player.eyes, "rotation", Vector3.ZERO, 0.3)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)


func physics_update(delta: float) -> void:
	if not current_rope:
		return

	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	_handle_climbing_and_swinging(delta, input_dir)
	_apply_rope_position(delta)

	# Only update components if we haven't dismounted
	if current_rope:
		_check_dismount(input_dir)


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _handle_climbing_and_swinging(delta: float, input_dir: Vector2) -> void:
	var rope_root: Node3D = current_rope.get_parent() as Node3D
	var rope_up: Vector3 = current_rope.global_transform.basis.y.normalized()
	var look_dir: Vector3 = -player.camera.global_transform.basis.z

	var can_swing: bool = (
		rope_root.get("is_swingable") as bool if "is_swingable" in rope_root else false
	)
	var force_amount: float = (
		rope_root.get("swing_force") as float if "swing_force" in rope_root else 300.0
	)

	var swing_angle_deg: float = rad_to_deg(acos(clampf(rope_up.dot(Vector3.UP), -1.0, 1.0)))
	var is_actively_swinging: bool = (
		swing_angle_deg > 5.0 or current_rope.angular_velocity.length() > 0.2
	)
	var center_grab_pos: Vector3 = current_rope.to_global(Vector3(0.0, rope_offset, 0.0))

	var look_dot_rope: float = look_dir.dot(rope_up)
	var is_looking_up: bool = look_dot_rope > 0.6
	var is_looking_down: bool = look_dot_rope < -0.2

	var is_pressing_w: bool = input_dir.y < -0.1
	var is_pressing_s: bool = input_dir.y > 0.1
	var is_sliding: bool = Input.is_action_pressed("crouch") and is_looking_down

	var intent_is_climbing: bool = false
	var climb_direction: float = 0.0

	# 1. Evaluate Climbing Intent
	if not is_sliding:
		if is_looking_up:
			if is_pressing_w:
				intent_is_climbing = true
				climb_direction = 1.0
			elif is_pressing_s and not is_actively_swinging:
				intent_is_climbing = true
				climb_direction = -1.0
		elif is_looking_down:
			if is_pressing_w and not is_actively_swinging:
				intent_is_climbing = true
				climb_direction = -1.0

	var is_climbing_actively: bool = false
	var local_top: float = current_rope.to_local(rope_root.global_position).y
	var max_length: float = (
		rope_root.get("rope_length") as float if "rope_length" in rope_root else 10.0
	)
	var top_limit: float = local_top - 2.5
	var bottom_limit: float = local_top - max_length + 0.5
	var old_offset: float = rope_offset

	# 2. Execute Climb / Slide / Swing
	if is_sliding:
		rope_offset -= (ROPE_CLIMB_SPEED * 7.0) * delta
		rope_offset = clampf(rope_offset, bottom_limit, top_limit)
	elif intent_is_climbing:
		rope_offset += climb_direction * ROPE_CLIMB_SPEED * delta
		rope_offset = clampf(rope_offset, bottom_limit, top_limit)
		is_climbing_actively = true
	else:
		if can_swing and input_dir.length() > 0.01:
			current_rope.sleeping = false
			var flat_fwd := Vector3(look_dir.x, 0.0, look_dir.z).normalized()
			var flat_right := flat_fwd.cross(Vector3.UP).normalized()
			var push_dir := (flat_fwd * -input_dir.y) + (flat_right * input_dir.x)

			if push_dir.length_squared() > 0.01:
				current_rope.apply_force(
					push_dir.normalized() * force_amount,
					center_grab_pos - current_rope.global_position
				)

	# 3. Audio & Camera Bob
	var actually_moved: bool = absf(rope_offset - old_offset) > 0.001
	var play_slide_sound: bool = is_sliding and actually_moved
	var play_climb_sound: bool = is_climbing_actively and actually_moved

	if rope_root.has_method("handle_rope_sounds"):
		rope_root.handle_rope_sounds(play_climb_sound, play_slide_sound)

	if is_climbing_actively and actually_moved:
		# Fake velocity for the camera headbob
		player.camera_controller.update_camera(delta, input_dir, false, false, false, 6.0)
	else:
		# Ease camera back to center
		player.camera.transform.origin = player.camera.transform.origin.lerp(
			Vector3.ZERO, delta * 10.0
		)


func _apply_rope_position(delta: float) -> void:
	var rope_root: Node3D = current_rope.get_parent() as Node3D
	var rope_up: Vector3 = current_rope.global_transform.basis.y.normalized()
	var center_grab_pos: Vector3 = current_rope.to_global(Vector3(0.0, rope_offset, 0.0))
	var can_swing: bool = (
		rope_root.get("is_swingable") as bool if "is_swingable" in rope_root else false
	)

	var cam_fwd: Vector3 = -player.camera.global_transform.basis.z.normalized()
	var cam_right: Vector3 = -player.camera.global_transform.basis.x.normalized()
	var orbit_fwd: Vector3 = Vector3(cam_fwd.x, 0.0, cam_fwd.z).normalized()
	var orbit_right: Vector3 = Vector3(cam_right.x, 0.0, cam_right.z).normalized()

	var target_pos: Vector3
	if can_swing:
		target_pos = center_grab_pos - (orbit_fwd * 0.7) + (orbit_right * 0.5)
	else:
		target_pos = center_grab_pos - (orbit_fwd * 0.2)

	if rope_lerp_weight < 45.0:
		rope_lerp_weight += delta * 150.0
		player.global_position = player.global_position.lerp(target_pos, delta * 15.0)
	else:
		player.global_position = target_pos

	player.global_rotation.x = 0.0
	player.global_rotation.z = 0.0

	var tilt_quat := Quaternion(Vector3.UP, rope_up)
	player.eyes.quaternion = Quaternion.IDENTITY.slerp(tilt_quat, 0.15)
	player.velocity = Vector3.ZERO


func _check_dismount(input_dir: Vector2) -> void:
	if Input.is_action_just_pressed("jump"):
		_perform_jump_dismount(input_dir)
	elif Input.is_action_just_pressed("interact"):
		if rope_lerp_weight > 10.0:
			var release_dir: Vector3 = -player.camera.global_transform.basis.z
			_transition_out_of_rope(release_dir, 0.0, 0.0)


func _perform_jump_dismount(input_dir: Vector2) -> void:
	var rope_root: Node3D = current_rope.get_parent() as Node3D
	var can_swing: bool = (
		rope_root.get("is_swingable") as bool if "is_swingable" in rope_root else false
	)

	var grab_offset: Vector3 = player.global_position - current_rope.global_position
	var rope_momentum: Vector3 = current_rope.angular_velocity.cross(grab_offset)
	var jump_dir: Vector3 = -player.camera.global_transform.basis.z.normalized()
	var flat_jump_dir: Vector3 = Vector3(jump_dir.x, 0.0, jump_dir.z).normalized()

	var vertical_hop: float = 0.0
	var forward_push: float = 0.0

	if can_swing and input_dir.length() > 0.1:
		current_rope.apply_impulse(-flat_jump_dir * 12.0, Vector3.ZERO)

		var directional_momentum: float = rope_momentum.dot(jump_dir)
		var swing_boost: float = maxf(0.0, directional_momentum)
		var camera_lift: float = maxf(jump_dir.y, 0.0) * 2.5

		vertical_hop = 5.0 + camera_lift + (swing_boost * 0.4)
		forward_push = 8.0 + (swing_boost * 2.5)
	else:
		vertical_hop = 4.5
		forward_push = 7.0

	_transition_out_of_rope(jump_dir, forward_push, vertical_hop)


func _transition_out_of_rope(
	release_dir: Vector3, forward_push: float, vertical_hop: float
) -> void:
	var flat_jump_dir: Vector3 = Vector3(release_dir.x, 0.0, release_dir.z).normalized()

	player.velocity = (flat_jump_dir * forward_push) + Vector3(0.0, vertical_hop, 0.0)

	if flat_jump_dir.length_squared() > 0.01:
		player.direction = flat_jump_dir

	player.global_position += release_dir * 0.5

	# Pass the release direction so the next state (Air) knows how to align the camera if needed
	state_machine.transition_to("Air", {"release_dir": release_dir})
