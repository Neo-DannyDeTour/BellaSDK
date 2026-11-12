## Handles ladder climbing, lateral strafing, and eject dismounts in [StateLadder].
class_name StateLadder
extends PlayerState

## Base vertical climbing and sliding speed along ladder surface.
const LADDER_SPEED: float = 5.0

## Maximum lateral offset from center rung before clamping movement.
const MAX_LADDER_SIDE_DIST: float = 0.6

## Centering snap speed pulling player back towards ladder midline.
const LADDER_CENTER_SNAP_SPEED: float = 8.0

## Target local Z offset in front of ladder center to stay inside 0.1m trigger.
const LADDER_DEPTH_OFFSET: float = 0.1

## Velocity gain aligning player depth toward [member LADDER_DEPTH_OFFSET].
const LADDER_DEPTH_PULL_SPEED: float = 8.0

## Minimum look-right dot magnitude (~64 deg) before forward/back steers laterally.
const LATERAL_LOOK_THRESHOLD: float = 0.90

## Downward look Y component (~30 deg down) required to flip forward input into descent.
const CLIMB_DOWN_LOOK_PITCH: float = -0.50

## Brief cooldown after ground dismount to prevent single-frame re-attachment.
const GROUND_DISMOUNT_COOLDOWN: float = 0.15

## Cooldown after jumping off a ladder before re-attaching to the same ladder.
const JUMP_EJECT_COOLDOWN: float = 0.5

## State identifier for grounded locomotion.
const STATE_GROUND: StringName = &"Ground"

## State identifier for airborne locomotion.
const STATE_AIR: StringName = &"Air"

## Payload key referencing the active ladder [Node3D].
const KEY_LADDER_NODE: StringName = &"ladder_node"

## Active ladder [Node3D] instance currently grabbed by player character.
var current_ladder: Node3D = null

## Reusable transition payload dictionary to avoid runtime allocations.
var _transition_msg: Dictionary = {}


## Initializes ladder state and resets entry velocity for clean surface grab.
func enter(msg: Dictionary = {}) -> void:
	print("StateLadder: enter() called. Initializing ladder state.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	p.velocity = Vector3.ZERO
	if msg.has(KEY_LADDER_NODE):
		var ladder_candidate: Variant = msg[KEY_LADDER_NODE]
		if ladder_candidate is Node3D:
			current_ladder = ladder_candidate


## Cleans up ladder reference upon exiting ladder locomotion state.
func exit() -> void:
	print("StateLadder: exit() called. Exiting ladder state.")
	current_ladder = null


## Updates ladder climbing, sound effects, jump inputs, and transitions.
func physics_update(delta: float) -> void:
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
		ACTION_LEFT, ACTION_RIGHT, ACTION_FORWARD, ACTION_BACKWARD
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
	_check_transitions(p, env)


## Toggles crouch state and emits [signal Events.player_crouch_changed].
func _handle_crouch_state(loco: PlayerLocomotionComponent) -> void:
	if not is_instance_valid(loco):
		return

	var previous_crouch: bool = loco.crouching
	loco.crouching = GestureInputManager.is_action_pressed(ACTION_CROUCH)

	if loco.crouching != previous_crouch:
		print("StateLadder: Crouch slide toggled: ", loco.crouching)
		Events.player_crouch_changed.emit(loco.crouching)


## Computes climbing, strafing, and surface depth velocities without snap oscillation.
func _calculate_ladder_velocity(
	p: Player, loco: PlayerLocomotionComponent, cam: CameraController, input_dir: Vector2
) -> void:
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

	var raw_lateral_ws: float = look_dir.dot(ladder_right)
	var lateral_weight_ws: float = 0.0
	if absf(raw_lateral_ws) > LATERAL_LOOK_THRESHOLD:
		var excess: float = (
			(absf(raw_lateral_ws) - LATERAL_LOOK_THRESHOLD) / (1.0 - LATERAL_LOOK_THRESHOLD)
		)
		lateral_weight_ws = signf(raw_lateral_ws) * clampf(excess, 0.0, 1.0)

	var vertical_weight_ws: float = 1.0 - absf(lateral_weight_ws)
	if look_dir.y < CLIMB_DOWN_LOOK_PITCH:
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
			lateral_movement = ladder_right * intended_lateral * LADDER_SPEED
	else:
		lateral_movement = -ladder_right * (offset_from_center * LADDER_CENTER_SNAP_SPEED)
		if lateral_movement.length_squared() > (LADDER_SPEED * LADDER_SPEED):
			lateral_movement = lateral_movement.normalized() * LADDER_SPEED

	var depth_error: float = local_pos.z - LADDER_DEPTH_OFFSET
	var depth_pull_speed: float = clampf(
		depth_error * LADDER_DEPTH_PULL_SPEED, -LADDER_SPEED, LADDER_SPEED
	)
	var depth_pull: Vector3 = -ladder_forward * depth_pull_speed
	p.velocity = (Vector3.UP * up_down_movement * LADDER_SPEED) + lateral_movement + depth_pull


## Processes directional jump inputs to eject or strafe dismount from ladder.
func _handle_jump_input(
	p: Player, cam: CameraController, env: PlayerEnvironmentComponent, input_dir: Vector2
) -> void:
	if (
		not GestureInputManager.is_action_just_pressed(ACTION_JUMP)
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
			env.ladder_cooldown = JUMP_EJECT_COOLDOWN

		p.move_and_slide()
		_transition_msg.clear()
		_transition_msg[&"jump"] = true
		_transition_msg[&"release_dir"] = jump_dir
		state_machine.transition_to(STATE_AIR, _transition_msg)
		return

	if dot_outward > -0.2:
		print("StateLadder: Intentional Eject. Pushing in look direction.")
		p.velocity = (flat_look * 7.0) + Vector3(0.0, 4.5, 0.0)

		if is_instance_valid(env):
			env.last_ladder = current_ladder
			env.ladder_cooldown = JUMP_EJECT_COOLDOWN

		p.move_and_slide()
		_transition_msg.clear()
		_transition_msg[&"jump"] = true
		_transition_msg[&"release_dir"] = flat_look
		state_machine.transition_to(STATE_AIR, _transition_msg)
		return

	print("StateLadder: Jump blocked. Player is facing the ladder.")


## Checks ground contact conditions to dismount into [StateGround].
func _check_transitions(p: Player, env: PlayerEnvironmentComponent) -> void:
	if p.is_on_floor() and p.velocity.y <= 0.0:
		print("StateLadder: Ground contact detected. Dismounting to Ground.")
		if is_instance_valid(env):
			env.last_ladder = current_ladder
			env.ladder_cooldown = GROUND_DISMOUNT_COOLDOWN
		state_machine.transition_to(STATE_GROUND)
