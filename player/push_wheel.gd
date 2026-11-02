## Locks player to a [PushWheel] or [TimberJibCrane] base anchor, mapping input to rotation.
class_name PushWheelState
extends PlayerState

## Target state name entered when detaching from the wheel handle.
const STATE_GROUND: StringName = &"Ground"

## Message dictionary key storing the target mount [Transform3D].
const KEY_TARGET_TRANSFORM: StringName = &"target_transform"

## Message dictionary key storing the wheel or crane [Node3D] instance.
const KEY_WHEEL: StringName = &"wheel"

## Method identifier invoked per frame to advance wheel rotation.
const METHOD_PUSH: StringName = &"push"

## Method identifier invoked when the player mounts the base handle.
const METHOD_PUSH_STARTED: StringName = &"on_push_started"

## Method identifier invoked when the player releases the base handle.
const METHOD_PUSH_ENDED: StringName = &"on_push_ended"

## Property identifier checking whether the wheel handle is installed.
const PROP_IS_INSTALLED: StringName = &"is_installed"

## Property identifier retrieving the active [Marker3D] player anchor.
const PROP_ACTIVE_ANCHOR: StringName = &"current_active_anchor"

## Property identifier checking clockwise rotation direction.
const PROP_TURN_CLOCKWISE: StringName = &"turn_clockwise"

## Property identifier retrieving the rotation [Vector3] axis.
const PROP_SPIN_AXIS: StringName = &"spin_axis"

## Property identifier retrieving the rotating hub [Node3D].
const PROP_WHEEL_NODE: StringName = &"wheel"

## Currently bound [PushWheel] or [TimberJibCrane] interactive node.
var active_wheel: Node3D = null

## Cached reference to the player's [PlayerLocomotionComponent].
var loco_component: PlayerLocomotionComponent = null

## Short cooldown timer preventing immediate accidental state exit.
var _exit_cooldown: float = 0.0

## Flag indicating if the player is currently tweening onto the wheel anchor.
var _is_mounting: bool = false

## Active [Tween] interpolating player onto the handle anchor.
var _mount_tween: Tween = null


## Enters state, tweens player to target transform, and attaches to wheel or crane base.
func enter(msg: Dictionary = {}) -> void:
	print("PushWheelState: enter() called. Setting up wheel interaction.")
	_is_mounting = false
	Utilities.safe_kill_tween(_mount_tween)
	_mount_tween = null

	if msg.has(KEY_TARGET_TRANSFORM) and msg[KEY_TARGET_TRANSFORM] is Transform3D:
		var t: Transform3D = msg[KEY_TARGET_TRANSFORM]
		_is_mounting = true
		_mount_tween = Utilities.reset_tween_ext(
			self, _mount_tween, Tween.TRANS_SINE, Tween.EASE_OUT
		)
		if is_instance_valid(_mount_tween):
			_mount_tween.tween_property(player, ^"global_transform", t, 0.4)
			_mount_tween.finished.connect(_on_mount_tween_finished)
		else:
			player.global_transform = t
			_is_mounting = false

	var raw_wheel: Variant = msg.get(KEY_WHEEL)
	var candidate_wheel: Node3D = raw_wheel as Node3D if raw_wheel is Object else null
	if is_instance_valid(candidate_wheel) and candidate_wheel.has_method(METHOD_PUSH):
		active_wheel = candidate_wheel
		print("PushWheelState: Entered. Attached to wheel: ", active_wheel.name)
		_exit_cooldown = 0.2

		var p: Player = _get_player()
		if is_instance_valid(p) and is_instance_valid(p.locomotion_component):
			loco_component = p.locomotion_component
		else:
			loco_component = (
				player.get_node_or_null(^"LocomotionComponent") as PlayerLocomotionComponent
			)

		if is_instance_valid(loco_component):
			loco_component.set_physics_active(false)
			loco_component.reset_momentum()
			print("PushWheelState: Disabled LocomotionComponent.")

		if active_wheel.has_method(METHOD_PUSH_STARTED):
			active_wheel.call(METHOD_PUSH_STARTED, player)
	else:
		push_error("PushWheelState: No valid wheel node provided in enter message.")
		state_machine.transition_to(STATE_GROUND)


## Routes movement input into wheel rotation and syncs player transform to anchor.
func physics_update(delta: float) -> void:
	if not is_instance_valid(active_wheel) or not _is_wheel_installed():
		state_machine.transition_to(STATE_GROUND)
		return

	if _exit_cooldown > 0.0:
		_exit_cooldown -= delta
	else:
		var release_pressed: bool = (
			GestureInputManager.is_action_just_pressed(ACTION_INTERACT)
			or GestureInputManager.is_action_just_pressed(ACTION_JUMP)
		)
		if release_pressed:
			print("PushWheelState: Player manually released wheel.")
			state_machine.transition_to(STATE_GROUND)
			return

	var push_input: float = GestureInputManager.get_axis(ACTION_BACKWARD, ACTION_FORWARD)
	if not is_zero_approx(push_input):
		var sync_multiplier: float = _calculate_input_sync_multiplier()
		active_wheel.call(METHOD_PUSH, push_input * sync_multiplier * delta)

	if not _is_mounting:
		var anchor: Marker3D = _get_active_anchor()
		if is_instance_valid(anchor):
			player.global_transform = anchor.global_transform

	var head: Node3D = _resolve_head_node()
	if is_instance_valid(head):
		head.rotation.x = lerp_angle(head.rotation.x, 0.0, 10.0 * delta)


## Restores player locomotion component and clears active wheel reference.
func exit() -> void:
	print("PushWheelState: exit() called. Restoring locomotion.")
	Utilities.safe_kill_tween(_mount_tween)
	_mount_tween = null
	_is_mounting = false

	if is_instance_valid(active_wheel) and active_wheel.has_method(METHOD_PUSH_ENDED):
		active_wheel.call(METHOD_PUSH_ENDED, player)

	if is_instance_valid(loco_component):
		loco_component.set_physics_active(true)
		print("PushWheelState: Re-enabled LocomotionComponent.")

	active_wheel = null


## Marks mounting interpolation complete once attach tween finishes.
func _on_mount_tween_finished() -> void:
	_is_mounting = false


## Returns true if the active wheel or crane base has an installed handle.
func _is_wheel_installed() -> bool:
	if not is_instance_valid(active_wheel):
		return false
	if PROP_IS_INSTALLED in active_wheel:
		return active_wheel.get(PROP_IS_INSTALLED) == true
	return true


## Retrieves the active [Marker3D] player anchor from the bound wheel node.
func _get_active_anchor() -> Marker3D:
	if not is_instance_valid(active_wheel) or not (PROP_ACTIVE_ANCHOR in active_wheel):
		return null
	var raw_anchor: Variant = active_wheel.get(PROP_ACTIVE_ANCHOR)
	return raw_anchor as Marker3D if raw_anchor is Object else null


## Resolves the player head pivot node for pitch leveling.
func _resolve_head_node() -> Node3D:
	if not is_instance_valid(player):
		return null
	var p: Player = _get_player()
	if is_instance_valid(p) and is_instance_valid(p.camera_controller):
		return p.camera_controller.head
	var raw_head: Variant = player.get(&"head")
	if raw_head is Node3D:
		var head_node: Node3D = raw_head
		return head_node
	return player.get_node_or_null(^"Head") as Node3D


## Calculates input multiplier based on player orientation relative to spin axis.
func _calculate_input_sync_multiplier() -> float:
	var clockwise: bool = true
	if PROP_TURN_CLOCKWISE in active_wheel:
		clockwise = active_wheel.get(PROP_TURN_CLOCKWISE) == true

	var axis: Vector3 = Vector3.UP
	if PROP_SPIN_AXIS in active_wheel:
		var raw_axis: Variant = active_wheel.get(PROP_SPIN_AXIS)
		if raw_axis is Vector3:
			var vec_axis: Vector3 = raw_axis
			axis = vec_axis

	var dir_multi: float = -1.0 if clockwise else 1.0
	var angular_velocity_dir: Vector3 = (axis * dir_multi).normalized()

	var wheel_center: Vector3 = active_wheel.global_position
	if PROP_WHEEL_NODE in active_wheel:
		var raw_hub: Variant = active_wheel.get(PROP_WHEEL_NODE)
		var hub_node: Node3D = raw_hub as Node3D if raw_hub is Object else null
		if is_instance_valid(hub_node):
			wheel_center = hub_node.global_position

	var to_player: Vector3 = player.global_position - wheel_center
	var positive_progress_linear_dir: Vector3 = angular_velocity_dir.cross(to_player).normalized()

	var player_forward: Vector3 = -player.global_transform.basis.z.normalized()
	var alignment: float = positive_progress_linear_dir.dot(player_forward)

	return 1.0 if alignment >= 0.0 else -1.0
