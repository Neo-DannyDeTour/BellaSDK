class_name CameraController
extends Node3D

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Node References")
@export var player_body: CharacterBody3D
@export var head: Node3D
@export var eyes: Node3D
@export var camera: Camera3D

@export_category("Sensitivity & FOV")
@export var mouse_sensitivity_base: float = 0.05
@export var base_fov: float = 75.0
@export var sprint_fov: float = 85.0
@export var zoom_fov: float = 10.0
@export var fov_change_speed: float = 12.0

@export_category("Camera Movement")
@export var lerp_speed: float = 15.0
@export var camera_tilt_amount: float = 3.0

# --------------------------------------
# CONSTANTS
# --------------------------------------
const HEAD_BOBBING_SPRINTING_SPEED: float = 22.0
const HEAD_BOBBING_WALKING_SPEED: float = 14.0
const HEAD_BOBBING_CROUCHING_SPEED: float = 10.0
const HEAD_BOBBING_IDLE_SPEED: float = 3.0

const HEAD_BOBBING_SPRINTING_INTENSITY: float = 0.2
const HEAD_BOBBING_WALKING_INTENSITY: float = 0.1
const HEAD_BOBBING_CROUCHING_INTENSITY: float = 0.08
const HEAD_BOBBING_IDLE_INTENSITY: float = 0.02

# --------------------------------------
# VARIABLES
# --------------------------------------
var mouse_sensitivity: float = 0.05
var target_fov: float = 75.0
var disable_sprint_fov: bool = false
var is_using_zoom: bool = false

var head_bobbing_index: float = 0.0
var head_bobbing_current_intensity: float = 0.0
var headbob_offset: Vector2 = Vector2.ZERO

var stair_offset: float = 0.0


func _ready() -> void:
	mouse_sensitivity = mouse_sensitivity_base
	target_fov = base_fov

	# If you have a settings file loader, you can call a setup function from Player.gd
	# to inject the saved sensitivity here.


# --------------------------------------
# INPUT HANDLING
# --------------------------------------
func handle_mouse_input(
	event: InputEventMouseMotion,
	is_terminal_mode: bool,
	is_heavy_lifting: bool,
	_heavy_lift_yaw_base: float
) -> void:
	var active_sens: float = mouse_sensitivity
	if is_terminal_mode:
		active_sens *= 0.5

	if is_heavy_lifting:
		# 1. YAW: Modify Euler angles directly to prevent Gimbal lock / Z-roll
		head.rotation.y -= deg_to_rad(event.relative.x * active_sens)
		head.rotation.y = clampf(head.rotation.y, deg_to_rad(-15.0), deg_to_rad(15.0))
		
		# 2. PITCH: Restrict Up/Down Look
		head.rotation.x -= deg_to_rad(event.relative.y * active_sens)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-15.0), deg_to_rad(89.0))
	else:
		# Standard FPS control: Body handles Y, Head handles X
		player_body.rotate_y(deg_to_rad(-event.relative.x * active_sens))
		
		head.rotation.x -= deg_to_rad(event.relative.y * active_sens)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
		
	# Strictly lock the Z-axis to prevent the camera from permanently tilting
	head.rotation.z = 0.0


# --------------------------------------
# PROCESS UPDATES
# --------------------------------------
func update_camera(
	delta: float,
	input_dir: Vector2,
	is_sprinting: bool,
	is_crouching: bool,
	is_grounded: bool,
	player_velocity: float
) -> void:
	_update_fov(delta, is_sprinting, is_grounded, input_dir)
	_update_tilt(delta, input_dir)
	_update_headbob(delta, input_dir, is_sprinting, is_crouching)
	_update_stair_smoothing(delta, player_velocity)


func _update_fov(delta: float, is_sprinting: bool, is_grounded: bool, input_dir: Vector2) -> void:
	var is_valid_sprint: bool = (
		(is_sprinting and input_dir.length() > 0.1)
		or (not is_grounded and target_fov == sprint_fov)
	)

	if Input.is_action_pressed("zoom"):
		target_fov = zoom_fov
		mouse_sensitivity = mouse_sensitivity_base / 10.0
		if not is_using_zoom:
			is_using_zoom = true
			print("CameraController: Zoom activated. Emitting player_zoomed(true).")
			Events.player_zoomed.emit(true) 
			
	elif is_valid_sprint and not disable_sprint_fov:
		target_fov = sprint_fov
		mouse_sensitivity = mouse_sensitivity_base
		if is_using_zoom:
			is_using_zoom = false
			print("CameraController: Sprint overriding zoom. Emitting player_zoomed(false).")
			Events.player_zoomed.emit(false) 
			
	else:
		target_fov = base_fov
		mouse_sensitivity = mouse_sensitivity_base
		if is_using_zoom:
			is_using_zoom = false
			print("CameraController: Zoom deactivated. Emitting player_zoomed(false).")
			Events.player_zoomed.emit(false) 

	camera.fov = lerpf(camera.fov, target_fov, delta * fov_change_speed)


func _update_tilt(delta: float, input_dir: Vector2) -> void:
	# This automatically tilts left/right based on A/D or analog stick input!
	var target_tilt: float = input_dir.x * camera_tilt_amount
	eyes.rotation.z = lerpf(eyes.rotation.z, deg_to_rad(-target_tilt), delta * lerp_speed)


func _update_headbob(
	delta: float,
	input_dir: Vector2,
	is_sprinting: bool,
	is_crouching: bool,
	intensity_modifier: float = 1.0
) -> void:
	var bob_speed: float = HEAD_BOBBING_IDLE_SPEED

	if is_sprinting and input_dir != Vector2.ZERO:
		bob_speed = HEAD_BOBBING_SPRINTING_SPEED
		head_bobbing_current_intensity = HEAD_BOBBING_SPRINTING_INTENSITY
	elif input_dir != Vector2.ZERO:
		if is_crouching:
			bob_speed = HEAD_BOBBING_CROUCHING_SPEED
			head_bobbing_current_intensity = HEAD_BOBBING_CROUCHING_INTENSITY
		else:
			bob_speed = HEAD_BOBBING_WALKING_SPEED
			head_bobbing_current_intensity = HEAD_BOBBING_WALKING_INTENSITY
	else:
		head_bobbing_current_intensity = HEAD_BOBBING_IDLE_INTENSITY

	# Increment timer
	var movement_multiplier: float = 1.0 if input_dir.length() > 0.1 else 0.5
	head_bobbing_index += bob_speed * delta * movement_multiplier

	# Calculate offset
	var target_bob_y: float = (
		sin(head_bobbing_index) * (head_bobbing_current_intensity / 2.0) * intensity_modifier
	)
	var target_bob_x: float = (
		sin(head_bobbing_index / 2.0) * head_bobbing_current_intensity * intensity_modifier
	)

	headbob_offset.y = lerpf(headbob_offset.y, target_bob_y, delta * lerp_speed)
	headbob_offset.x = lerpf(headbob_offset.x, target_bob_x, delta * lerp_speed)

	# Apply to eyes (combining headbob with stair offset)
	eyes.position.y = headbob_offset.y + stair_offset
	eyes.position.x = headbob_offset.x


# --------------------------------------
# STAIR SMOOTHING
# --------------------------------------
func add_stair_offset(snap_amount: float) -> void:
	stair_offset -= snap_amount
	stair_offset = clampf(stair_offset, -0.5, 0.5)


func _update_stair_smoothing(delta: float, player_velocity: float) -> void:
	if stair_offset == 0.0:
		return

	# Recovers back to 0.0 smoothly based on movement speed
	var move_amount: float = maxf(player_velocity * delta, 2.5 * delta)
	stair_offset = move_toward(stair_offset, 0.0, move_amount)
