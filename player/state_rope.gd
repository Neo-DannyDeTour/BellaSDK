## Handles hanging, climbing, and swinging on interactive ropes in [StateRope].
class_name StateRope
extends PlayerState

## Base speed scalar for climbing up and down the rope.
const ROPE_CLIMB_SPEED: float = 1.0

## The specific physics body segment of the rope the player is currently grabbing.
var current_rope: RigidBody3D = null

## The local vertical Y-axis offset on the rope segment where the player's hands are anchored.
var rope_offset: float = 0.0

## Blending weight used to smoothly interpolate the player to the exact rope grab point.
var rope_lerp_weight: float = 0.0

## Reusable transition payload dictionary to avoid runtime heap allocations.
var _transition_msg: Dictionary = {}


## Initializes rope state, calculates grab offsets, and transfers player momentum.
func enter(msg: Dictionary = {}) -> void:
	print("StateRope: enter() called. Player attaching to rope.")
	if not msg.has(&"rope_node"):
		state_machine.transition_to(&"Air")
		return

	current_rope = msg[&"rope_node"] as RigidBody3D
	if not is_instance_valid(current_rope):
		state_machine.transition_to(&"Air")
		return

	var rope_root: Node3D = (
		current_rope.get_parent() if current_rope.get_parent() is Node3D else null
	)
	var can_swing: bool = (
		rope_root.get(&"is_swingable")
		if rope_root != null and &"is_swingable" in rope_root
		else false
	)

	if can_swing:
		var entry_momentum: Vector3 = Vector3(
			player.velocity.x, player.velocity.y * 0.2, player.velocity.z
		)
		var rel_pos: Vector3 = player.global_position - current_rope.global_position
		current_rope.apply_impulse(entry_momentum * 1.5, rel_pos)

	player.velocity = Vector3.ZERO
	player.add_collision_exception_with(current_rope)
	rope_lerp_weight = 4.0

	var local_pos: Vector3 = current_rope.to_local(player.global_position)
	rope_offset = local_pos.y

	var local_top: float = (
		current_rope.to_local(rope_root.global_position).y if is_instance_valid(rope_root) else 0.0
	)
	var max_length: float = (
		rope_root.get(&"rope_length") if rope_root != null and &"rope_length" in rope_root else 10.0
	)

	var top_limit: float = local_top - 2.5
	var bottom_limit: float = local_top - max_length + 0.5
	rope_offset = clampf(rope_offset, bottom_limit, top_limit)

	var face_pos: Vector3 = Vector3(
		current_rope.global_position.x, player.global_position.y, current_rope.global_position.z
	)
	if player.global_position.distance_squared_to(face_pos) > 0.01:
		var target_transform: Transform3D = player.global_transform.looking_at(face_pos, Vector3.UP)
		var tween: Tween = create_tween()
		(
			tween
			. tween_property(
				player, "quaternion", target_transform.basis.get_rotation_quaternion(), 0.3
			)
			. set_trans(Tween.TRANS_SINE)
		)


## Cleans up physics exceptions and smooths camera rotation back upright on exit.
func exit() -> void:
	print("StateRope: exit() called. Player releasing rope.")
	if is_instance_valid(current_rope):
		player.remove_collision_exception_with(current_rope)

		var rope_root: Node3D = (
			current_rope.get_parent() if current_rope.get_parent() is Node3D else null
		)
		if is_instance_valid(rope_root):
			if rope_root.has_method(&"on_player_released"):
				rope_root.call(&"on_player_released")

	current_rope = null

	var release_forward: Vector3 = (
		Vector3(-player.global_transform.basis.z.x, 0.0, -player.global_transform.basis.z.z)
		. normalized()
	)
	if release_forward.length_squared() < 0.001:
		release_forward = -player.global_transform.basis.z

	var target_basis: Basis = Basis.looking_at(release_forward, Vector3.UP)
	var release_tween: Tween = create_tween().set_parallel(true)

	(
		release_tween
		. tween_property(player, "quaternion", target_basis.get_rotation_quaternion(), 0.3)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)

	var cam: Camera3D = _get_camera()
	if is_instance_valid(cam):
		(
			release_tween
			. tween_property(cam, "rotation", Vector3.ZERO, 0.3)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)


## Routes frame updates to climb or swing logic based on input gestures.
func physics_update(delta: float) -> void:
	print("StateRope: physics_update() processing rope attachment.")
	if not is_instance_valid(current_rope):
		return

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	_handle_climbing_and_swinging(delta, input_dir)
	_apply_rope_position(delta)

	if is_instance_valid(current_rope):
		_check_dismount(input_dir)


## Evaluates player camera angles and input vectors to determine rope locomotion.
func _handle_climbing_and_swinging(delta: float, input_dir: Vector2) -> void:
	print("StateRope: _handle_climbing_and_swinging() evaluating intent.")
	var rope_root: Node3D = (
		current_rope.get_parent() if current_rope.get_parent() is Node3D else null
	)
	var rope_up: Vector3 = current_rope.global_transform.basis.y.normalized()
	var cam: Camera3D = _get_camera()
	var look_dir: Vector3 = (
		-cam.global_transform.basis.z
		if is_instance_valid(cam)
		else -player.global_transform.basis.z
	)

	var can_swing: bool = (
		rope_root.get(&"is_swingable")
		if rope_root != null and &"is_swingable" in rope_root
		else false
	)
	var force_amount: float = (
		rope_root.get(&"swing_force")
		if rope_root != null and &"swing_force" in rope_root
		else 1200.0
	)

	var swing_angle_deg: float = rad_to_deg(acos(clampf(rope_up.dot(Vector3.UP), -1.0, 1.0)))
	var is_actively_swinging: bool = (
		swing_angle_deg > 5.0 or current_rope.angular_velocity.length() > 0.2
	)

	var look_dot_rope: float = look_dir.dot(rope_up)
	var is_looking_up: bool = look_dot_rope > 0.6
	var is_looking_down: bool = look_dot_rope < -0.2

	var is_pressing_w: bool = input_dir.y < -0.1
	var is_pressing_s: bool = input_dir.y > 0.1
	var is_sliding: bool = GestureInputManager.is_action_pressed(&"crouch") and is_looking_down

	var intent_is_climbing: bool = false
	var climb_direction: float = 0.0

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
	var local_top: float = (
		current_rope.to_local(rope_root.global_position).y if is_instance_valid(rope_root) else 0.0
	)
	var max_length: float = (
		rope_root.get(&"rope_length") if rope_root != null and &"rope_length" in rope_root else 10.0
	)
	var top_limit: float = local_top - 2.5
	var bottom_limit: float = local_top - max_length + 0.5
	var old_offset: float = rope_offset

	if is_sliding:
		rope_offset -= (ROPE_CLIMB_SPEED * 7.0) * delta
		rope_offset = clampf(rope_offset, bottom_limit, top_limit)
		print("StateRope: Player sliding down rope.")
	elif intent_is_climbing:
		rope_offset += climb_direction * ROPE_CLIMB_SPEED * delta
		rope_offset = clampf(rope_offset, bottom_limit, top_limit)
		is_climbing_actively = true
		print("StateRope: Player actively climbing rope.")
	else:
		if can_swing and input_dir.length_squared() > 0.0001:
			current_rope.sleeping = false
			var flat_fwd: Vector3 = Vector3(look_dir.x, 0.0, look_dir.z).normalized()
			var flat_right: Vector3 = flat_fwd.cross(Vector3.UP).normalized()
			var push_dir: Vector3 = (flat_fwd * -input_dir.y) + (flat_right * input_dir.x)

			if push_dir.length_squared() > 0.01:
				var applied_force: Vector3 = push_dir.normalized() * force_amount
				current_rope.apply_central_force(applied_force)
				print("StateRope: Applying raw swing force: ", applied_force)

	var actually_moved: bool = absf(rope_offset - old_offset) > 0.001
	var play_slide_sound: bool = is_sliding and actually_moved
	var play_climb_sound: bool = is_climbing_actively and actually_moved

	if is_instance_valid(rope_root):
		if rope_root.has_method(&"handle_rope_sounds"):
			rope_root.call(&"handle_rope_sounds", play_climb_sound, play_slide_sound)

	var cam_ctrl: Node = _get_camera_controller()
	if is_instance_valid(cam_ctrl) and cam_ctrl.has_method(&"update_camera"):
		if is_climbing_actively and actually_moved:
			cam_ctrl.call(&"update_camera", delta, input_dir, false, false, false, 6.0)
		else:
			cam_ctrl.call(&"update_camera", delta, Vector2.ZERO, false, false, false, 0.0)


## Updates global position and rotation to follow moving rope physics body via [MathUtils].
func _apply_rope_position(delta: float) -> void:
	print("StateRope: _apply_rope_position() syncing with rope transform.")
	var rope_root: Node3D = (
		current_rope.get_parent() if current_rope.get_parent() is Node3D else null
	)
	var rope_up: Vector3 = current_rope.global_transform.basis.y.normalized()
	var center_grab_pos: Vector3 = current_rope.to_global(Vector3(0.0, rope_offset, 0.0))
	var can_swing: bool = (
		rope_root.get(&"is_swingable")
		if rope_root != null and &"is_swingable" in rope_root
		else false
	)

	var cam: Camera3D = _get_camera()
	var cam_fwd: Vector3 = (
		-cam.global_transform.basis.z.normalized()
		if is_instance_valid(cam)
		else -player.global_transform.basis.z.normalized()
	)
	var cam_right: Vector3 = (
		-cam.global_transform.basis.x.normalized()
		if is_instance_valid(cam)
		else -player.global_transform.basis.x.normalized()
	)
	var orbit_fwd: Vector3 = Vector3(cam_fwd.x, 0.0, cam_fwd.z).normalized()
	var orbit_right: Vector3 = Vector3(cam_right.x, 0.0, cam_right.z).normalized()

	var target_pos: Vector3
	if can_swing:
		target_pos = (center_grab_pos - (orbit_fwd * 0.7) + (orbit_right * 0.5))
	else:
		target_pos = center_grab_pos - (orbit_fwd * 0.2)

	if rope_lerp_weight < 45.0:
		rope_lerp_weight += delta * 150.0
		player.global_position = MathUtils.damp_v3(player.global_position, target_pos, 15.0, delta)
	else:
		player.global_position = target_pos

	player.global_rotation.x = 0.0
	player.global_rotation.z = 0.0

	if is_instance_valid(cam):
		var tilt_quat: Quaternion = Quaternion(Vector3.UP, rope_up)
		cam.quaternion = Quaternion.IDENTITY.slerp(tilt_quat, 0.15)
	player.velocity = Vector3.ZERO


## Listens for jump or interact actions to release player from current rope.
func _check_dismount(input_dir: Vector2) -> void:
	print("StateRope: _check_dismount() polling release triggers.")
	if GestureInputManager.is_action_just_pressed(&"jump"):
		_perform_jump_dismount(input_dir)
	elif GestureInputManager.is_action_just_pressed(&"interact"):
		if rope_lerp_weight > 10.0:
			var cam: Camera3D = _get_camera()
			var release_dir: Vector3 = (
				-cam.global_transform.basis.z
				if is_instance_valid(cam)
				else -player.global_transform.basis.z
			)
			_transition_out_of_rope(release_dir, 0.0, 0.0)


## Calculates directional momentum and boosts when jumping off swing rope.
func _perform_jump_dismount(input_dir: Vector2) -> void:
	print("StateRope: _perform_jump_dismount() computing exit velocity.")
	var rope_root: Node3D = (
		current_rope.get_parent() if current_rope.get_parent() is Node3D else null
	)
	var can_swing: bool = (
		rope_root.get(&"is_swingable")
		if rope_root != null and &"is_swingable" in rope_root
		else false
	)

	var grab_offset: Vector3 = player.global_position - current_rope.global_position
	var rope_momentum: Vector3 = current_rope.angular_velocity.cross(grab_offset)
	var cam: Camera3D = _get_camera()
	var jump_dir: Vector3 = (
		-cam.global_transform.basis.z.normalized()
		if is_instance_valid(cam)
		else -player.global_transform.basis.z.normalized()
	)
	var flat_jump_dir: Vector3 = Vector3(jump_dir.x, 0.0, jump_dir.z).normalized()

	var vertical_hop: float = 0.0
	var forward_push: float = 0.0

	if can_swing and input_dir.length_squared() > 0.01:
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


## Applies exit velocity and transitions state machine back into [StateAir].
func _transition_out_of_rope(
	release_dir: Vector3, forward_push: float, vertical_hop: float
) -> void:
	print("StateRope: _transition_out_of_rope() executing detachment.")
	var flat_jump_dir: Vector3 = Vector3(release_dir.x, 0.0, release_dir.z).normalized()
	player.velocity = ((flat_jump_dir * forward_push) + Vector3(0.0, vertical_hop, 0.0))

	var loc_comp: Node = _get_locomotion()
	if flat_jump_dir.length_squared() > 0.01:
		if is_instance_valid(loc_comp):
			if loc_comp.has_method(&"set_direction"):
				loc_comp.call(&"set_direction", flat_jump_dir)

	player.global_position += release_dir * 0.5
	_transition_msg.clear()
	_transition_msg[&"release_dir"] = release_dir
	state_machine.transition_to(&"Air", _transition_msg)


## Safely retrieves the player camera controller component.
func _get_camera_controller() -> Node:
	if not is_instance_valid(player):
		return null
	var ctrl: Variant = player.get(&"camera_controller")
	if ctrl is Node and is_instance_valid(ctrl as Node):
		return ctrl as Node
	return null


## Safely retrieves the player [Camera3D] node.
func _get_camera() -> Camera3D:
	var ctrl: Node = _get_camera_controller()
	if is_instance_valid(ctrl):
		var cam: Variant = ctrl.get(&"camera")
		if cam is Camera3D and is_instance_valid(cam as Camera3D):
			return cam as Camera3D
	return null


## Safely retrieves the player locomotion component.
func _get_locomotion() -> Node:
	if not is_instance_valid(player):
		return null
	var loc: Variant = player.get(&"locomotion_component")
	if loc is Node and is_instance_valid(loc as Node):
		return loc as Node
	return null
