## Handles overhead monkey bar navigation, hanging, and traversal in [StateMonkeyBars].
class_name StateMonkeyBars
extends PlayerState

## Horizontal traversal speed along overhead monkey bar volume.
const MONKEY_BAR_SPEED: float = 2.5

## Vertical downward offset below monkey bar trigger volume.
const MONKEY_BAR_HANG_OFFSET: float = 2.1

## Active monkey bar trigger volume currently occupied by player.
var current_monkey_bar_volume: Node3D = null

## Cached [AnimationPlayer] node driving first-person camera animations.
var _camera_anims: AnimationPlayer = null

## Cached horizontal velocity vector to prevent runtime heap allocations.
var _flat_vel: Vector2 = Vector2.ZERO


## Attaches player to monkey bars, plays idle animation, and locks sprint FOV.
func enter(msg: Dictionary = {}) -> void:
	print("StateMonkeyBars: enter() called. Player mounting monkey bars.")
	if not is_instance_valid(_camera_anims):
		_camera_anims = player.get_node_or_null("%CameraAnims") as AnimationPlayer

	if not msg.has(&"volume_node"):
		state_machine.transition_to(&"Air")
		return

	current_monkey_bar_volume = msg[&"volume_node"] as Node3D
	player.velocity.y = 0.0

	if is_instance_valid(_camera_anims):
		_camera_anims.play(&"monkey_bar_idle")

	if is_instance_valid(player.camera_controller):
		print("StateMonkeyBars: Disabling sprint FOV scaling.")
		player.camera_controller.disable_sprint_fov = true


## Restores camera animations, stops looping audio, and resets sprint FOV.
func exit() -> void:
	print("StateMonkeyBars: exit() called. Player dismounting monkey bars.")
	current_monkey_bar_volume = null

	var env: PlayerEnvironmentComponent = player.environment_component as PlayerEnvironmentComponent
	if is_instance_valid(env):
		env.monkey_bar_cooldown = 0.5

	if is_instance_valid(_camera_anims):
		_camera_anims.play(&"idle", 0.2)

	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	if is_instance_valid(loco) and is_instance_valid(loco.footstep_manager):
		if loco.footstep_manager.has_method(&"stop_looping_sounds"):
			loco.footstep_manager.call(&"stop_looping_sounds")
			print("StateMonkeyBars: Stopped looping monkey bar sounds.")

	if is_instance_valid(player.camera_controller):
		print("StateMonkeyBars: Re-enabling sprint FOV scaling.")
		player.camera_controller.disable_sprint_fov = false


## Processes horizontal locomotion, vertical magnetism, audio, and dismounts.
func physics_update(delta: float) -> void:
	print("StateMonkeyBars: physics_update() processing monkey bar traversal.")
	var env: PlayerEnvironmentComponent = player.environment_component as PlayerEnvironmentComponent
	var active_bar: Node3D = null
	if is_instance_valid(env):
		active_bar = env.available_monkey_bar

	if active_bar == null:
		state_machine.transition_to(&"Air")
		return

	if current_monkey_bar_volume != active_bar:
		current_monkey_bar_volume = active_bar

	if not is_instance_valid(current_monkey_bar_volume):
		_perform_dismount()
		return

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	_apply_horizontal_movement(input_dir)
	_apply_vertical_magnetism()
	_handle_animations(input_dir)
	player.move_and_slide()

	_flat_vel.x = player.velocity.x
	_flat_vel.y = player.velocity.z

	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	if is_instance_valid(loco) and is_instance_valid(loco.footstep_manager):
		loco.footstep_manager.process_surface_and_footsteps(
			delta, false, _flat_vel.length(), false, false, false, true
		)

	player.camera_controller.update_camera(delta, input_dir, false, false, false, MONKEY_BAR_SPEED)
	_check_dismount_conditions()


## Calculates horizontal velocity relative to camera orientation.
func _apply_horizontal_movement(input_dir: Vector2) -> void:
	print("StateMonkeyBars: _apply_horizontal_movement() steering character.")
	var look_dir: Vector3 = player.camera_controller.get_camera_look_dir()
	var right_dir: Vector3 = player.camera_controller.get_camera_right_dir()

	look_dir.y = 0.0
	right_dir.y = 0.0
	look_dir = look_dir.normalized()
	right_dir = right_dir.normalized()

	var target_dir: Vector3 = (look_dir * -input_dir.y) + (right_dir * input_dir.x)
	var final_dir: Vector3 = Vector3.ZERO

	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	if is_instance_valid(loco):
		if target_dir.length_squared() > 0.0:
			loco.set_direction(target_dir.normalized())
		else:
			loco.set_direction(Vector3.ZERO)
		final_dir = loco.get_direction()
	else:
		if target_dir.length_squared() > 0.0:
			final_dir = target_dir.normalized()

	player.velocity.x = final_dir.x * MONKEY_BAR_SPEED
	player.velocity.z = final_dir.z * MONKEY_BAR_SPEED


## Snaps player vertical position to underside of monkey bar volume.
func _apply_vertical_magnetism() -> void:
	print("StateMonkeyBars: _apply_vertical_magnetism() applying height clamp.")
	var volume: MonkeyBarVolume = current_monkey_bar_volume as MonkeyBarVolume
	if not is_instance_valid(volume):
		return

	var player_pos: Vector3 = player.global_position
	var local_pos: Vector3 = volume.to_local(player_pos)
	local_pos.y = -volume.size.y / 2.0

	var target_global: Vector3 = volume.to_global(local_pos)
	var target_y: float = target_global.y - MONKEY_BAR_HANG_OFFSET
	var distance_to_target: float = target_y - player_pos.y

	if absf(distance_to_target) > 4.0:
		_perform_dismount()
		return

	var pull_speed: float = distance_to_target * 12.0
	player.velocity.y = clampf(pull_speed, -6.0, 6.0)


## Updates procedural character animations based on movement vector.
func _handle_animations(_input_dir: Vector2) -> void:
	print("StateMonkeyBars: _handle_animations() checking camera anim clips.")


## Evaluates jump or crouch inputs to trigger monkey bar dismount.
func _check_dismount_conditions() -> void:
	print("StateMonkeyBars: _check_dismount_conditions() polling release buttons.")
	if (
		GestureInputManager.is_action_just_pressed(&"jump")
		or GestureInputManager.is_action_just_pressed(&"crouch")
	):
		_perform_dismount()


## Applies exit downward push and transitions state into [StateAir].
func _perform_dismount() -> void:
	print("StateMonkeyBars: _perform_dismount() dismounting monkey bars.")
	player.velocity.y = -2.0
	state_machine.transition_to(&"Air")
