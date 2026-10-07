## Handles ladder climbing, lateral strafing, and eject dismounts in [StateLadder].
class_name StateLadder
extends PlayerState

## Base vertical climbing and sliding speed along ladder surface.
const LADDER_SPEED: float = 5.0

## Maximum lateral offset from center rung before clamping movement.
const MAX_LADDER_SIDE_DIST: float = 0.6

## Centering snap speed pulling player back towards ladder midline.
const LADDER_CENTER_SNAP_SPEED: float = 8.0

## Active ladder [Node3D] instance currently grabbed by player character.
var current_ladder: Node3D = null

## Reusable transition payload dictionary to avoid runtime allocations.
var _transition_msg: Dictionary = {}


## Returns the owning player instance cast to concrete [Player] or null.
func _get_player() -> Player:
	return player as Player


## Initializes ladder state and snaps player to ladder surface.
func enter(msg: Dictionary = {}) -> void:
	print("StateLadder: enter() called. Initializing ladder state.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	if msg.has(&"ladder_node"):
		var ladder_candidate: Variant = msg[&"ladder_node"]
		if ladder_candidate is Node3D:
			current_ladder = ladder_candidate
			_snap_to_ladder(p)


## Cleans up ladder reference upon exiting ladder locomotion state.
func exit() -> void:
	print("StateLadder: exit() called. Exiting ladder state.")
	current_ladder = null


## Updates ladder climbing, sound effects, jump inputs, and transitions.
func physics_update(delta: float) -> void:
	print("StateLadder: physics_update() processing ladder frame.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	var loco: PlayerLocomotionComponent = p.locomotion_component
	var env: PlayerEnvironmentComponent = p.environment_component
	var cam: CameraController = (
		p.camera_controller if p.camera_controller is CameraController else null
	)

	_handle_crouch_state(loco)

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	_calculate_ladder_velocity(p, loco, cam, input_dir)
	p.move_and_slide()

	if is_instance_valid(loco):
		var footsteps: FootstepManager = (
			loco.footstep_manager if loco.footstep_manager is FootstepManager else null
		)
		if is_instance_valid(footsteps):
			footsteps.process_surface_and_footsteps(
				delta, false, p.velocity.length(), false, false, true
			)

	_handle_jump_input(p, cam, env, input_dir)
	_check_transitions(p)


## Smoothly interpolates player position to align with ladder front plane.
func _snap_to_ladder(p: Player) -> void:
	print("StateLadder: _snap_to_ladder() aligning player with ladder rungs.")
	if not is_instance_valid(current_ladder):
		return

	var push_out_distance: float = 0.6
	var ladder_forward: Vector3 = current_ladder.global_transform.basis.z.normalized()
	var target_pos: Vector3 = current_ladder.global_position + (ladder_forward * push_out_distance)
	target_pos.y = p.global_position.y

	var tween: Tween = create_tween()
	(
		tween
		. tween_property(p, "global_position", target_pos, 0.15)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)


## Toggles crouch state and emits [signal Events.player_crouch_changed].
func _handle_crouch_state(loco: PlayerLocomotionComponent) -> void:
	print("StateLadder: _handle_crouch_state() polling crouch slide inputs.")
	if not is_instance_valid(loco):
		return

	var previous_crouch: bool = loco.crouching
	loco.crouching = GestureInputManager.is_action_pressed(&"crouch")

	if loco.crouching != previous_crouch:
		Events.player_crouch_changed.emit(loco.crouching)


## Computes climbing, strafing, and surface depth velocities.
func _calculate_ladder_velocity(
	p: Player, loco: PlayerLocomotionComponent, cam: CameraController, input_dir: Vector2
) -> void:
	print("StateLadder: _calculate_ladder_velocity() calculating 3D projection.")
	if not is_instance_valid(current_ladder):
		return

	if is_instance_valid(loco) and loco.crouching:
		p.velocity = Vector3.DOWN * LADDER_SPEED
		return

	if not is_instance_valid(cam) or not is_instance_valid(cam.camera):
		return

	var look_dir: Vector3 = -cam.camera.global_transform.basis.z
	var right_dir: Vector3 = cam.camera.global_transform.basis.x

	var local_pos: Vector3 = current_ladder.to_local(p.global_position)
	var offset_from_center: float = local_pos.x

	var ladder_right: Vector3 = current_ladder.global_transform.basis.x.normalized()
	var ladder_forward: Vector3 = current_ladder.global_transform.basis.z.normalized()

	var lateral_weight_ws: float = look_dir.dot(ladder_right)
	var vertical_weight_ws: float = 1.0 - absf(lateral_weight_ws)
	if look_dir.y < -0.15:
		vertical_weight_ws *= -1.0

	var forward_input: float = -input_dir.y
	var ws_lateral: float = lateral_weight_ws * forward_input
	var ws_vertical: float = vertical_weight_ws * forward_input

	var lateral_weight_ad: float = right_dir.dot(ladder_right)
	var vertical_weight_ad: float = 1.0 - absf(lateral_weight_ad)
	if right_dir.y < -0.15:
		vertical_weight_ad *= -1.0

	var strafe_input: float = input_dir.x
	var ad_lateral: float = lateral_weight_ad * strafe_input
	var ad_vertical: float = vertical_weight_ad * strafe_input

	var plane_intent: Vector2 = Vector2(ws_lateral + ad_lateral, ws_vertical + ad_vertical)
	if plane_intent.length_squared() > 1.0:
		plane_intent = plane_intent.normalized()

	var intended_lateral: float = plane_intent.x
	var up_down_movement: float = plane_intent.y
	var lateral_movement: Vector3 = Vector3.ZERO

	if absf(intended_lateral) > 0.05:
		if intended_lateral > 0.0 and offset_from_center >= MAX_LADDER_SIDE_DIST:
			lateral_movement = Vector3.ZERO
		elif intended_lateral < 0.0 and offset_from_center <= -MAX_LADDER_SIDE_DIST:
			lateral_movement = Vector3.ZERO
		else:
			lateral_movement = (ladder_right * intended_lateral * LADDER_SPEED)
	else:
		lateral_movement = -ladder_right * (offset_from_center * LADDER_CENTER_SNAP_SPEED)
		if lateral_movement.length_squared() > (LADDER_SPEED * LADDER_SPEED):
			lateral_movement = lateral_movement.normalized() * LADDER_SPEED

	var depth_pull: Vector3 = -ladder_forward * (local_pos.z * 4.0)
	p.velocity = ((Vector3.UP * up_down_movement * LADDER_SPEED) + lateral_movement + depth_pull)


## Processes directional jump inputs to eject or strafe dismount from ladder.
func _handle_jump_input(
	p: Player, cam: CameraController, env: PlayerEnvironmentComponent, input_dir: Vector2
) -> void:
	print("StateLadder: _handle_jump_input() polling ladder jump triggers.")
	if (
		not GestureInputManager.is_action_just_pressed(&"jump")
		or not is_instance_valid(current_ladder)
	):
		return

	if not is_instance_valid(cam) or not is_instance_valid(cam.camera):
		return

	var look_dir: Vector3 = -cam.camera.global_transform.basis.z
	if look_dir.y > 0.3:
		print("StateLadder: Jump blocked. Player is looking up.")
		return

	var ladder_outward: Vector3 = current_ladder.global_transform.basis.z.normalized()
	var ladder_right: Vector3 = current_ladder.global_transform.basis.x.normalized()

	var flat_look: Vector3 = Vector3(look_dir.x, 0.0, look_dir.z).normalized()
	var flat_outward: Vector3 = Vector3(ladder_outward.x, 0.0, ladder_outward.z).normalized()
	var flat_ladder_right: Vector3 = Vector3(ladder_right.x, 0.0, ladder_right.z).normalized()

	var dot_outward: float = flat_look.dot(flat_outward)
	var strafe_input: float = input_dir.x

	if absf(strafe_input) > 0.1:
		print("StateLadder: Intentional Side Jump. Pushing strictly laterally.")
		var jump_dir: Vector3 = (flat_ladder_right * signf(strafe_input)).normalized()
		p.velocity = (jump_dir * 7.5) + Vector3(0.0, 4.5, 0.0)

		if is_instance_valid(env):
			env.last_ladder = current_ladder
			env.ladder_cooldown = 0.5

		p.move_and_slide()
		_transition_msg.clear()
		_transition_msg[&"jump"] = true
		_transition_msg[&"release_dir"] = jump_dir
		state_machine.transition_to(&"Air", _transition_msg)
		return

	if dot_outward > -0.2:
		print("StateLadder: Intentional Eject. Pushing in look direction.")
		p.velocity = (flat_look * 7.0) + Vector3(0.0, 4.5, 0.0)

		if is_instance_valid(env):
			env.last_ladder = current_ladder
			env.ladder_cooldown = 0.5

		p.move_and_slide()
		_transition_msg.clear()
		_transition_msg[&"jump"] = true
		_transition_msg[&"release_dir"] = flat_look
		state_machine.transition_to(&"Air", _transition_msg)
		return

	print("StateLadder: Jump blocked. Player is facing the ladder.")


## Checks ground contact conditions to dismount into [StateGround].
func _check_transitions(p: Player) -> void:
	print("StateLadder: _check_transitions() testing ground dismount.")
	if p.is_on_floor() and p.velocity.y < 0.0:
		state_machine.transition_to(&"Ground")
