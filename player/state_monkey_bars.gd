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


## Enters monkey bars state, mounts player to bar, and resets vertical velocity.
func enter(msg: Dictionary = {}) -> void:
	print("StateMonkeyBars: enter() called. Player mounting monkey bars.")
	var p: Player = player if player is Player else null
	if not is_instance_valid(_camera_anims) and is_instance_valid(p):
		_camera_anims = p.get_node_or_null("%CameraAnims") as AnimationPlayer

	if not msg.has(&"volume_node"):
		state_machine.transition_to(&"Air")
		return

	var raw_node: Variant = msg[&"volume_node"]
	current_monkey_bar_volume = raw_node if raw_node is Node3D else null

	if is_instance_valid(p):
		p.velocity.y = 0.0

	if is_instance_valid(_camera_anims):
		_camera_anims.play(&"monkey_bar_idle")

	if is_instance_valid(p) and is_instance_valid(p.camera_controller):
		print("StateMonkeyBars: Disabling sprint FOV scaling.")
		p.camera_controller.disable_sprint_fov = true


## Restores camera animations, stops looping audio, and resets sprint FOV.
func exit() -> void:
	print("StateMonkeyBars: exit() called. Player dismounting monkey bars.")
	current_monkey_bar_volume = null
	var p: Player = player if player is Player else null
	if not is_instance_valid(p):
		return

	var env: PlayerEnvironmentComponent = p.environment_component
	if is_instance_valid(env):
		env.monkey_bar_cooldown = 0.5

	if is_instance_valid(_camera_anims):
		_camera_anims.play(&"idle", 0.2)

	var loco: PlayerLocomotionComponent = p.locomotion_component
	if is_instance_valid(loco) and is_instance_valid(loco.footstep_manager):
		if loco.footstep_manager.has_method(&"stop_looping_sounds"):
			loco.footstep_manager.call(&"stop_looping_sounds")
			print("StateMonkeyBars: Stopped looping monkey bar sounds.")

	if is_instance_valid(p.camera_controller):
		print("StateMonkeyBars: Re-enabling sprint FOV scaling.")
		p.camera_controller.disable_sprint_fov = false


## Processes horizontal locomotion, vertical magnetism, audio, and dismounts.
func physics_update(delta: float) -> void:
	print("StateMonkeyBars: physics_update() processing monkey bar traversal.")
	var p: Player = player if player is Player else null
	if not is_instance_valid(p):
		return

	var env: PlayerEnvironmentComponent = p.environment_component
	var active_bar: Node3D = null
	if is_instance_valid(env):
		active_bar = env.available_monkey_bar

	if active_bar == null:
		state_machine.transition_to(&"Air")
		return

	if current_monkey_bar_volume != active_bar:
		current_monkey_bar_volume = active_bar

	if not is_instance_valid(current_monkey_bar_volume):
		_perform_dismount(p)
		return

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	_apply_horizontal_movement(input_dir, p)
	_apply_vertical_magnetism(p)
	_handle_animations(input_dir)
	p.move_and_slide()

	_flat_vel.x = p.velocity.x
	_flat_vel.y = p.velocity.z

	var loco: PlayerLocomotionComponent = p.locomotion_component
	if is_instance_valid(loco) and is_instance_valid(loco.footstep_manager):
		if loco.footstep_manager.has_method(&"process_surface_and_footsteps"):
			loco.footstep_manager.call(
				&"process_surface_and_footsteps",
				delta,
				false,
				_flat_vel.length(),
				false,
				false,
				false,
				true
			)

	if is_instance_valid(p.camera_controller):
		p.camera_controller.update_camera(delta, input_dir, false, false, false, MONKEY_BAR_SPEED)

	_check_dismount_conditions(p)


## Calculates horizontal velocity relative to camera orientation.
func _apply_horizontal_movement(input_dir: Vector2, p: Player) -> void:
	print("StateMonkeyBars: _apply_horizontal_movement() steering character.")
	var cam: CameraController = p.camera_controller
	if not is_instance_valid(cam):
		return

	var look_dir: Vector3 = cam.get_camera_look_dir()
	var right_dir: Vector3 = cam.get_camera_right_dir()

	look_dir.y = 0.0
	right_dir.y = 0.0
	look_dir = look_dir.normalized()
	right_dir = right_dir.normalized()

	var target_dir: Vector3 = (look_dir * -input_dir.y) + (right_dir * input_dir.x)
	var final_dir: Vector3 = Vector3.ZERO

	var loco: PlayerLocomotionComponent = p.locomotion_component
	if is_instance_valid(loco):
		if target_dir.length_squared() > 0.0:
			loco.set_direction(target_dir.normalized())
		else:
			loco.set_direction(Vector3.ZERO)
		final_dir = loco.get_direction()
	else:
		if target_dir.length_squared() > 0.0:
			final_dir = target_dir.normalized()

	p.velocity.x = final_dir.x * MONKEY_BAR_SPEED
	p.velocity.z = final_dir.z * MONKEY_BAR_SPEED


## Snaps player vertical position to underside of monkey bar volume.
func _apply_vertical_magnetism(p: Player) -> void:
	print("StateMonkeyBars: _apply_vertical_magnetism() applying height clamp.")
	var volume: MonkeyBarVolume = (
		current_monkey_bar_volume if current_monkey_bar_volume is MonkeyBarVolume else null
	)
	if not is_instance_valid(volume):
		return

	var player_pos: Vector3 = p.global_position
	var local_pos: Vector3 = volume.to_local(player_pos)
	local_pos.y = -volume.size.y / 2.0

	var target_global: Vector3 = volume.to_global(local_pos)
	var target_y: float = target_global.y - MONKEY_BAR_HANG_OFFSET
	var distance_to_target: float = target_y - player_pos.y

	if absf(distance_to_target) > 4.0:
		_perform_dismount(p)
		return

	var pull_speed: float = distance_to_target * 12.0
	p.velocity.y = clampf(pull_speed, -6.0, 6.0)


## Updates procedural character animations based on movement vector.
func _handle_animations(_input_dir: Vector2) -> void:
	print("StateMonkeyBars: _handle_animations() checking camera anim clips.")


## Evaluates jump or crouch inputs to trigger monkey bar dismount.
func _check_dismount_conditions(p: Player) -> void:
	print("StateMonkeyBars: _check_dismount_conditions() polling release buttons.")
	if (
		GestureInputManager.is_action_just_pressed(&"jump")
		or GestureInputManager.is_action_just_pressed(&"crouch")
	):
		_perform_dismount(p)


## Applies exit downward push and transitions state into [StateAir].
func _perform_dismount(p: Player) -> void:
	print("StateMonkeyBars: _perform_dismount() dismounting monkey bars.")
	if is_instance_valid(p):
		p.velocity.y = -2.0
	state_machine.transition_to(&"Air")
