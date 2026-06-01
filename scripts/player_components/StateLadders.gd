class_name StateLadder
extends PlayerState

# --------------------------------------
# CONSTANTS
# --------------------------------------
const LADDER_SPEED: float = 5.0
const MAX_LADDER_SIDE_DIST: float = 0.6  # How far left/right you can go before stopping
const LADDER_CENTER_SNAP_SPEED: float = 8.0  # How fast you slide back to the middle

# --------------------------------------
# VARIABLES
# --------------------------------------
var current_ladder: Node3D = null
var last_hoist_time: int = 0
var is_hoisting: bool = false


func enter(msg: Dictionary = {}) -> void:
	is_hoisting = false

	if msg.has("ladder_node"):
		current_ladder = msg["ladder_node"]
		_snap_to_ladder()


func exit() -> void:
	current_ladder = null
	is_hoisting = false


func physics_update(_delta: float) -> void:
	# Block physics updates if we are actively playing the hoist animation
	if is_hoisting:
		return

	_handle_crouch_state()

	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	# Calculate movement and apply it
	_calculate_ladder_velocity(input_dir)
	player.move_and_slide()

	# Check for dismounts (Jumping off, climbing to the top, hitting the floor)
	_handle_jump_input(input_dir)
	_check_transitions()


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _snap_to_ladder() -> void:
	if not current_ladder:
		return

	var push_out_distance: float = 0.6
	var ladder_forward: Vector3 = current_ladder.global_transform.basis.z.normalized()
	var target_pos: Vector3 = current_ladder.global_position + (ladder_forward * push_out_distance)
	target_pos.y = player.global_position.y  # Keep current height

	var tween := create_tween()
	(
		tween
		. tween_property(player, "global_position", target_pos, 0.15)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)


func _handle_crouch_state() -> void:
	var previous_crouch: bool = player.crouching
	player.crouching = Input.is_action_pressed("crouch")

	if player.crouching != previous_crouch:
		Events.player_crouch_changed.emit(player.crouching)


func _calculate_ladder_velocity(input_dir: Vector2) -> void:
	if not current_ladder:
		return

	# If crouching, slide down fast
	if player.crouching:
		player.velocity = Vector3.DOWN * LADDER_SPEED
		return

	var look_dir: Vector3 = -player.camera.global_transform.basis.z
	var right_dir: Vector3 = player.camera.global_transform.basis.x

	var local_pos: Vector3 = current_ladder.to_local(player.global_position)
	var offset_from_center: float = local_pos.x

	var ladder_right: Vector3 = current_ladder.global_transform.basis.x.normalized()
	var ladder_forward: Vector3 = current_ladder.global_transform.basis.z.normalized()

	# 1. W/S Input Projection
	var lateral_weight_ws: float = look_dir.dot(ladder_right)
	var vertical_weight_ws: float = 1.0 - absf(lateral_weight_ws)
	if look_dir.y < -0.15:
		vertical_weight_ws *= -1.0

	var forward_input: float = -input_dir.y
	var ws_lateral: float = lateral_weight_ws * forward_input
	var ws_vertical: float = vertical_weight_ws * forward_input

	# 2. A/D Input Projection
	var lateral_weight_ad: float = right_dir.dot(ladder_right)
	var vertical_weight_ad: float = 1.0 - absf(lateral_weight_ad)
	if right_dir.y < -0.15:
		vertical_weight_ad *= -1.0

	var strafe_input: float = input_dir.x
	var ad_lateral: float = lateral_weight_ad * strafe_input
	var ad_vertical: float = vertical_weight_ad * strafe_input

	# 3. Combine Intent
	var plane_intent := Vector2(ws_lateral + ad_lateral, ws_vertical + ad_vertical)
	if plane_intent.length() > 1.0:
		plane_intent = plane_intent.normalized()

	var intended_lateral: float = plane_intent.x
	var up_down_movement: float = plane_intent.y
	var lateral_movement: Vector3 = Vector3.ZERO

	# 4. Lateral Bounding & Centering
	if absf(intended_lateral) > 0.05:
		if intended_lateral > 0 and offset_from_center >= MAX_LADDER_SIDE_DIST:
			lateral_movement = Vector3.ZERO
		elif intended_lateral < 0 and offset_from_center <= -MAX_LADDER_SIDE_DIST:
			lateral_movement = Vector3.ZERO
		else:
			lateral_movement = ladder_right * intended_lateral * LADDER_SPEED
	else:
		lateral_movement = -ladder_right * (offset_from_center * LADDER_CENTER_SNAP_SPEED)
		if lateral_movement.length() > LADDER_SPEED:
			lateral_movement = lateral_movement.normalized() * LADDER_SPEED

	# 5. Depth Pull (Stick to the ladder surface)
	var depth_pull: Vector3 = -ladder_forward * (local_pos.z * 4.0)

	player.velocity = (Vector3.UP * up_down_movement * LADDER_SPEED) + lateral_movement + depth_pull


func _handle_jump_input(input_dir: Vector2) -> void:
	if not Input.is_action_just_pressed("jump") or not current_ladder:
		return

	var look_dir: Vector3 = -player.camera.global_transform.basis.z
	var right_dir: Vector3 = player.camera.global_transform.basis.x
	var ladder_forward: Vector3 = current_ladder.global_transform.basis.z.normalized()

	var dot_forward: float = look_dir.dot(ladder_forward)
	var is_looking_down: bool = look_dir.y < -0.3
	var is_looking_up: bool = look_dir.y > 0.4
	var is_looking_away: bool = dot_forward > -0.2
	var is_looking_at_ladder: bool = dot_forward < -0.6
	var strafe_input: float = input_dir.x

	var is_shapecast_hitting: bool = player.interaction_scanner.interact_shapecast.is_colliding()
	var flat_jump_dir: Vector3 = Vector3.ZERO

	# CONDITION A: Side jump (Looking at the ladder, pressing A or D)
	if absf(strafe_input) > 0.1 and not is_looking_away and not is_looking_down:
		var flat_right := Vector3(right_dir.x, 0.0, right_dir.z).normalized()
		player.velocity = (flat_right * strafe_input * 6.0)
		player.global_position += (flat_right * strafe_input) * 0.2
		state_machine.transition_to("Air")
		return

	# CONDITION B: Upward leap / Hoist (Looking strictly UP)
	if (
		is_looking_up
		and (is_looking_at_ladder or is_shapecast_hitting)
		and absf(strafe_input) < 0.1
	):
		var current_time := Time.get_ticks_msec()
		if current_time - last_hoist_time >= 1000:
			last_hoist_time = current_time

			if is_shapecast_hitting:
				# Hoist Upward
				is_hoisting = true
				var hoist_target := player.global_position + (Vector3.UP * 1.5)
				var tween := create_tween()
				(
					tween
					. tween_property(player, "global_position", hoist_target, 0.2)
					. set_trans(Tween.TRANS_QUAD)
					. set_ease(Tween.EASE_OUT)
				)
				tween.tween_callback(func() -> void: state_machine.transition_to("Air"))
			else:
				# Vault over ledge
				flat_jump_dir = Vector3(look_dir.x, 0.0, look_dir.z).normalized()
				player.velocity = (flat_jump_dir * 5.0) + Vector3(0.0, 4.5, 0.0)
				player.global_position += look_dir * 0.2
				state_machine.transition_to("Air")
		return

	# CONDITION C: Detach jump (Looking down, away, or neutral)
	flat_jump_dir = Vector3(look_dir.x, 0.0, look_dir.z).normalized()
	var camera_lift: float = maxf(look_dir.y, 0.0) * 2.5
	var vertical_hop: float = 4.5 + camera_lift

	player.velocity = (flat_jump_dir * 6.0) + Vector3(0.0, vertical_hop, 0.0)
	player.global_position += look_dir * 0.2
	state_machine.transition_to("Air")


func _check_transitions() -> void:
	if player.is_on_floor() and player.velocity.y < 0.0:
		# Dismount on the ground
		state_machine.transition_to("Ground")
