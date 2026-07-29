class_name PushWheelState
extends PlayerState

var active_wheel: PushWheel
var loco_component: PlayerLocomotionComponent
var _exit_cooldown: float = 0.0
var _is_mounting: bool = false


func enter(msg: Dictionary = {}) -> void:
	_is_mounting = false

	if msg.has("target_transform"):
		var t: Transform3D = msg["target_transform"]
		_is_mounting = true
		var tween : Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(player, "global_transform", t, 0.4)
		# Strict typing for the lambda callback
		tween.finished.connect(func() -> void: _is_mounting = false)

	if msg.has("wheel"):
		active_wheel = msg["wheel"] as PushWheel
		print("PushWheelState: Entered. Attached to wheel.")

		_exit_cooldown = 0.2

		loco_component = player.get_node_or_null("LocomotionComponent")
		if is_instance_valid(loco_component):
			loco_component.set_physics_active(false)
			loco_component.reset_momentum()
			print("PushWheelState: Disabled LocomotionComponent.")
	else:
		push_error("PushWheelState: No wheel provided in enter message.")
		state_machine.transition_to("Ground")


func physics_update(delta: float) -> void:
	if not is_instance_valid(active_wheel) or not active_wheel.is_installed:
		state_machine.transition_to("Ground")
		return

	if _exit_cooldown > 0.0:
		_exit_cooldown -= delta
	else:
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("jump"):
			print("PushWheelState: Player manually released wheel.")
			state_machine.transition_to("Ground")
			return

	var push_input: float = Input.get_axis("backward", "forward")
	if push_input != 0.0:
		var sync_multiplier: float = _calculate_input_sync_multiplier()
		active_wheel.push(push_input * sync_multiplier * delta)

	# Only lock the transform IF the mounting tween is finished
	if not _is_mounting and is_instance_valid(active_wheel.current_active_anchor):
		player.global_transform = active_wheel.current_active_anchor.global_transform

	if player.get("head") != null:
		var head: Node3D = player.head as Node3D
		head.rotation.x = lerp_angle(head.rotation.x, 0.0, 10.0 * delta)


func _calculate_input_sync_multiplier() -> float:
	var dir_multi: float = -1.0 if active_wheel.turn_clockwise else 1.0
	var angular_velocity_dir: Vector3 = (active_wheel.spin_axis * dir_multi).normalized()

	var wheel_center: Vector3 = active_wheel.global_position
	if is_instance_valid(active_wheel.wheel):
		wheel_center = active_wheel.wheel.global_position

	var to_player: Vector3 = player.global_position - wheel_center
	var positive_progress_linear_dir: Vector3 = angular_velocity_dir.cross(to_player).normalized()

	var player_forward: Vector3 = -player.global_transform.basis.z.normalized()
	var alignment: float = positive_progress_linear_dir.dot(player_forward)

	# If pressing forward naturally aligns with positive progress, multiply by 1.0.
	# If on the opposite side, it results in a negative alignment, so we invert the input.
	return 1.0 if alignment >= 0.0 else -1.0


func exit() -> void:
	print("PushWheelState: Exiting state.")
	if is_instance_valid(loco_component):
		loco_component.set_physics_active(true)
		print("PushWheelState: Re-enabled LocomotionComponent.")

	active_wheel = null
