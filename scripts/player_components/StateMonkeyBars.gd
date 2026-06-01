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


func enter(msg: Dictionary = {}) -> void:
	if not msg.has("volume_node"):
		state_machine.transition_to("Air")
		return

	current_monkey_bar_volume = msg["volume_node"]
	
	# Instantly kill vertical momentum so we "catch" the bar
	player.velocity.y = 0.0
	
	if player.has_node("%CameraAnims"): # Or whatever your AnimationPlayer is named
		player.get_node("%CameraAnims").play("monkey_bar_idle")


func exit() -> void:
	current_monkey_bar_volume = null
	
	# Start the cooldown on the main player script so they don't instantly regrab
	player.monkey_bar_cooldown = 0.5
	
	if player.has_node("%CameraAnims"):
		# Play a falling/idle animation, or use a crossfade transition
		player.get_node("%CameraAnims").play("idle", 0.2)

	# Reset animations
	# if player.camera_anims:
	# 	player.camera_anims.play("RESET", 0.3)
	# 	player.camera_anims.speed_scale = 1.0


func physics_update(delta: float) -> void:
	if player.available_monkey_bar == null:
		state_machine.transition_to("Air")
		return
		
	if not is_instance_valid(current_monkey_bar_volume):
		_perform_dismount()
		return

	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	
	_apply_horizontal_movement(input_dir)
	_apply_vertical_magnetism()
	_handle_animations(input_dir)
	
	player.move_and_slide()

	# Update the camera and headbob (passing our custom speed)
	player.camera_controller.update_camera(
		delta, 
		input_dir, 
		false, # is_sprinting
		false, # is_crouching
		false, # is_grounded
		MONKEY_BAR_SPEED
	)

	_check_dismount_conditions()


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _apply_horizontal_movement(input_dir: Vector2) -> void:
	var look_dir: Vector3 = -player.camera.global_transform.basis.z
	var right_dir: Vector3 = player.camera.global_transform.basis.x
	
	# Flatten directions
	look_dir.y = 0.0
	right_dir.y = 0.0
	look_dir = look_dir.normalized()
	right_dir = right_dir.normalized()

	var bar_vel: Vector3 = (look_dir * -input_dir.y) + (right_dir * input_dir.x)
	player.velocity.x = bar_vel.x * MONKEY_BAR_SPEED
	player.velocity.z = bar_vel.z * MONKEY_BAR_SPEED

	var flat_vel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if flat_vel.length() > 0.0:
		player.direction = flat_vel.normalized()


func _apply_vertical_magnetism() -> void:
	# Keep the player perfectly suspended beneath the volume's center point
	var target_y: float = current_monkey_bar_volume.global_position.y - MONKEY_BAR_HANG_OFFSET
	var distance_to_target: float = target_y - player.global_position.y

	# If the player manages to slip too far away (e.g., fell off the end of the area)
	if absf(distance_to_target) > 4.0:
		_perform_dismount()
		return

	# Smoothly pull them to the exact hang height
	var pull_speed: float = distance_to_target * 12.0
	player.velocity.y = clampf(pull_speed, -6.0, 6.0)


func _handle_animations(_input_dir: Vector2) -> void:
	pass
	# Uncomment and hook up to your AnimationPlayer once ready
	# if input_dir.length() > 0.1:
	# 	if player.camera_anims.current_animation != "MonkeMoves":
	# 		player.camera_anims.play("MonkeMoves", 0.3)
	# 	player.camera_anims.speed_scale = 1.0 if input_dir.y < 0.0 else -1.0
	# else:
	# 	if player.camera_anims.current_animation == "MonkeMoves":
	# 		player.camera_anims.play("RESET", 0.3)
	# 		player.camera_anims.speed_scale = 1.0


func _check_dismount_conditions() -> void:
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("crouch"):
		_perform_dismount()


func _perform_dismount() -> void:
	player.velocity.y = -2.0 # Slight downward push to cleanly exit the trigger volume
	state_machine.transition_to("Air")
