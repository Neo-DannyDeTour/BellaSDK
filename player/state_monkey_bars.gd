class_name StateMonkeyBars
extends PlayerState

# --------------------------------------
# CONSTANTS
# --------------------------------------
const MONKEY_BAR_SPEED: float = 2.5
const MONKEY_BAR_HANG_OFFSET: float = 2.1

# --------------------------------------
# VARIABLES
# --------------------------------------
var current_monkey_bar_volume: Node3D = null

# CACHED NODE
var _camera_anims: AnimationPlayer = null


func enter(msg: Dictionary = {}) -> void:
	if not is_instance_valid(_camera_anims):
		_camera_anims = player.get_node_or_null("%CameraAnims") as AnimationPlayer

	if not msg.has("volume_node"):
		state_machine.transition_to("Air")
		return

	current_monkey_bar_volume = msg["volume_node"]

	# Instantly kill vertical momentum so we "catch" the bar
	player.velocity.y = 0.0

	if is_instance_valid(_camera_anims):
		_camera_anims.play("monkey_bar_idle")

	# Force the camera back to base_fov
	if is_instance_valid(player.camera_controller):
		print("StateMonkeyBars: Disabling sprint FOV flag")
		player.camera_controller.disable_sprint_fov = true


func exit() -> void:
	current_monkey_bar_volume = null

	# FIX: Route cooldown to your environment_component
	if is_instance_valid(player.environment_component):
		player.environment_component.monkey_bar_cooldown = 0.5

	if is_instance_valid(_camera_anims):
		_camera_anims.play("idle", 0.2)

	# --- NEW: Kill the looping audio when we let go ---
	if (
		is_instance_valid(player.locomotion_component)
		and is_instance_valid(player.locomotion_component.get("footstep_manager"))
	):
		if player.locomotion_component.footstep_manager.has_method("stop_looping_sounds"):
			player.locomotion_component.footstep_manager.stop_looping_sounds()
			print("StateMonkeyBars: Stopped looping monkey bar sounds")

	# Re-enable the ability to sprint FOV when returning to ground/air
	if is_instance_valid(player.camera_controller):
		print("StateMonkeyBars: Re-enabling sprint FOV flag")
		player.camera_controller.disable_sprint_fov = false


func physics_update(delta: float) -> void:
	# Print statement omitted here to prevent console spam at 60 FPS
	var active_bar: Node3D = null

	if is_instance_valid(player.environment_component):
		active_bar = player.environment_component.get("available_monkey_bar") as Node3D

	if active_bar == null:
		state_machine.transition_to("Air")
		return

	if current_monkey_bar_volume != active_bar:
		current_monkey_bar_volume = active_bar

	if not is_instance_valid(current_monkey_bar_volume):
		_perform_dismount()
		return

	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	_apply_horizontal_movement(input_dir)
	_apply_vertical_magnetism()
	_handle_animations(input_dir)

	player.move_and_slide()

	# --- NEW: Play Monkey Bar Sounds ---
	# We only pass horizontal velocity so the vertical magnetism wobble doesn't trigger audio
	var flat_vel: Vector2 = Vector2(player.velocity.x, player.velocity.z)
	if (
		is_instance_valid(player.locomotion_component)
		and is_instance_valid(player.locomotion_component.get("footstep_manager"))
	):
		player.locomotion_component.footstep_manager.process_surface_and_footsteps(
			delta, false, flat_vel.length(), false, false, false, true
		)

	player.camera_controller.update_camera(delta, input_dir, false, false, false, MONKEY_BAR_SPEED)

	_check_dismount_conditions()


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _apply_horizontal_movement(input_dir: Vector2) -> void:
	# FIX: Route camera reference through camera_controller
	var look_dir: Vector3 = player.camera_controller.get_camera_look_dir()
	var right_dir: Vector3 = player.camera_controller.get_camera_right_dir()

	look_dir.y = 0.0
	right_dir.y = 0.0
	look_dir = look_dir.normalized()
	right_dir = right_dir.normalized()

	var target_dir: Vector3 = (look_dir * -input_dir.y) + (right_dir * input_dir.x)
	var final_dir: Vector3 = Vector3.ZERO

	if is_instance_valid(player.locomotion_component):
		if target_dir.length() > 0.0:
			player.locomotion_component.set_direction(target_dir.normalized())
		else:
			player.locomotion_component.set_direction(Vector3.ZERO)
		final_dir = player.locomotion_component.get_direction()
	else:
		if target_dir.length() > 0.0:
			final_dir = target_dir.normalized()

	player.velocity.x = final_dir.x * MONKEY_BAR_SPEED
	player.velocity.z = final_dir.z * MONKEY_BAR_SPEED


func _apply_vertical_magnetism() -> void:
	var volume: MonkeyBarVolume = current_monkey_bar_volume as MonkeyBarVolume
	if not is_instance_valid(volume):
		return

	var player_pos: Vector3 = player.global_position

	# 1. Convert the player's position to the volume's local coordinate space
	var local_pos: Vector3 = volume.to_local(player_pos)

	# 2. Snap the local Y exactly to the bottom face of the CSGBox3D
	local_pos.y = -volume.size.y / 2.0

	# 3. Convert back to global space to find the true slanted height
	var target_global: Vector3 = volume.to_global(local_pos)
	var target_y: float = target_global.y - MONKEY_BAR_HANG_OFFSET
	var distance_to_target: float = target_y - player_pos.y
	# If the player manages to slip too far away
	if absf(distance_to_target) > 4.0:
		_perform_dismount()
		return

	# Smoothly pull them to the exact hang height
	var pull_speed: float = distance_to_target * 12.0
	player.velocity.y = clampf(pull_speed, -6.0, 6.0)


func _handle_animations(_input_dir: Vector2) -> void:
	pass


func _check_dismount_conditions() -> void:
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("crouch"):
		_perform_dismount()


func _perform_dismount() -> void:
	player.velocity.y = -2.0  # Slight downward push to cleanly exit the trigger volume
	state_machine.transition_to("Air")
