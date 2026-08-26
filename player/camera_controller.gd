## Controls first-person camera transforms, view bobbing, FOV adjustments, and input sensitivity.
class_name CameraController
extends Node3D

## Head bobbing cycle speed during sprint locomotion.
const HEAD_BOBBING_SPRINTING_SPEED: float = 22.0
## Head bobbing cycle speed during standard walking.
const HEAD_BOBBING_WALKING_SPEED: float = 14.0
## Head bobbing cycle speed while crouched.
const HEAD_BOBBING_CROUCHING_SPEED: float = 10.0
## Head bobbing cycle speed while standing idle.
const HEAD_BOBBING_IDLE_SPEED: float = 3.0

## Head bobbing displacement intensity during sprint locomotion.
const HEAD_BOBBING_SPRINTING_INTENSITY: float = 0.2
## Head bobbing displacement intensity during standard walking.
const HEAD_BOBBING_WALKING_INTENSITY: float = 0.1
## Head bobbing displacement intensity while crouched.
const HEAD_BOBBING_CROUCHING_INTENSITY: float = 0.08
## Head bobbing displacement intensity while standing idle.
const HEAD_BOBBING_IDLE_INTENSITY: float = 0.02

@export_category("Node References")
## Reference to the root player physics body.
@export var player_body: CharacterBody3D
## Reference to the vertical pitch pivot node.
@export var head: Node3D
## Reference to the camera container node handling offsets.
@export var eyes: Node3D
## Reference to the active 3D camera instance.
@export var camera: Camera3D

@export_category("Sensitivity & FOV")
## Base mouse look sensitivity factor.
@export var mouse_sensitivity_base: float = 0.05
## Default resting field of view in degrees.
@export var base_fov: float = 75.0
## Field of view applied while sprinting.
@export var sprint_fov: float = 85.0
## Field of view applied while zooming.
@export var zoom_fov: float = 10.0
## Interpolation rate for smooth FOV transitions.
@export var fov_change_speed: float = 12.0

@export_category("Camera Movement")
## Interpolation rate for camera smoothing and bobbing.
@export var lerp_speed: float = 15.0
## Roll angle tilt magnitude applied during strafing movements.
@export var camera_tilt_amount: float = 3.0

## Active mouse sensitivity scalar used for real-time input evaluation.
var mouse_sensitivity: float = 0.05
## Target FOV degree goal for interpolation.
var target_fov: float = 75.0
## Whether sprint FOV adjustments are disabled.
var disable_sprint_fov: bool = false
## Whether zoom state is currently held by player.
var is_using_zoom: bool = false

## Time progression accumulator for head bob calculation.
var head_bobbing_index: float = 0.0
## Current magnitude of the active head bob displacement.
var head_bobbing_current_intensity: float = 0.0
## Calculated 2D vector for camera head bob offset.
var headbob_offset: Vector2 = Vector2.ZERO

## Smooth vertical offset applied when traversing stair steps.
var stair_offset: float = 0.0

## Determines if vertical camera movement is inverted.
var invert_y: bool = false


## Lifecycle initialization method loading saved preferences and preparing camera state.
func _ready() -> void:
	print("CameraController: Initializing settings.")

	mouse_sensitivity_base = (
		GlobalSettings.get_setting("Controls", "mouse_sensitivity", 1.0) as float
	)
	base_fov = GlobalSettings.get_setting("Settings", "base_fov", 75.0) as float
	disable_sprint_fov = (
		GlobalSettings.get_setting("Settings", "disable_sprint_fov", false) as bool
	)
	invert_y = GlobalSettings.get_setting("Controls", "invert_y", false) as bool

	mouse_sensitivity = mouse_sensitivity_base
	target_fov = base_fov


## Sets the base mouse sensitivity multiplier and syncs the live sensitivity.
## [param new_sens] The target mouse sensitivity value.
func set_mouse_sensitivity(new_sens: float) -> void:
	print("CameraController: Setting base sensitivity to: ", new_sens)
	mouse_sensitivity_base = new_sens
	mouse_sensitivity = new_sens


## Evaluates incoming mouse motion to rotate the player body and camera head.
## [param event] The mouse motion input event.
## [param is_terminal_mode] Whether terminal focus restricts mouse movement.
## [param is_heavy_lifting] Whether heavy lifting restricts camera yaw/pitch.
## [param _heavy_lift_yaw_base] Yaw constraint baseline angle.
func handle_mouse_input(
	event: InputEventMouseMotion,
	is_terminal_mode: bool,
	is_heavy_lifting: bool,
	_heavy_lift_yaw_base: float
) -> void:
	if absf(event.relative.x) > 50.0 or absf(event.relative.y) > 50.0:
		print("CameraController: Large mouse movement detected, processing input.")

	var active_sens: float = mouse_sensitivity
	if is_terminal_mode:
		active_sens *= 0.5

	var y_multiplier: float = -1.0 if invert_y else 1.0
	var pitch_input: float = event.relative.y * active_sens * y_multiplier

	if is_heavy_lifting:
		head.rotation.y -= deg_to_rad(event.relative.x * active_sens)
		head.rotation.y = clampf(head.rotation.y, deg_to_rad(-15.0), deg_to_rad(15.0))

		head.rotation.x -= deg_to_rad(pitch_input)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-15.0), deg_to_rad(89.0))
	else:
		player_body.rotate_y(deg_to_rad(-event.relative.x * active_sens))

		head.rotation.x -= deg_to_rad(pitch_input)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	head.rotation.z = 0.0


## Master frame update routing FOV, tilting, headbobbing, and stair smoothing.
## [param delta] Physics frame delta time in seconds.
## [param input_dir] Current horizontal locomotion input vector.
## [param is_sprinting] Sprint locomotion state flag.
## [param is_crouching] Crouch state flag.
## [param is_grounded] Ground contact status flag.
## [param player_velocity] Current horizontal movement speed.
func update_camera(
	delta: float,
	input_dir: Vector2,
	is_sprinting: bool,
	is_crouching: bool,
	is_grounded: bool,
	player_velocity: float
) -> void:
	if Input.is_action_just_pressed("zoom") or Input.is_action_just_pressed("sprint"):
		print("CameraController: update_camera() processing state change.")

	_update_fov(delta, is_sprinting, is_grounded, input_dir)
	_update_tilt(delta, input_dir)
	_update_headbob(delta, input_dir, is_sprinting, is_crouching)
	_update_stair_smoothing(delta, player_velocity)


## Calculates FOV goals based on zooming, sprint states, and interpolates camera FOV.
## [param delta] Frame delta time in seconds.
## [param is_sprinting] Sprint locomotion state flag.
## [param is_grounded] Ground contact status flag.
## [param input_dir] Current movement vector.
func _update_fov(delta: float, is_sprinting: bool, is_grounded: bool, input_dir: Vector2) -> void:
	var is_valid_sprint: bool = (
		(is_sprinting and input_dir.length() > 0.1)
		or (not is_grounded and target_fov == sprint_fov)
	)

	if GestureInputManager.is_action_pressed("zoom"):
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


## Smoothly rolls the camera roll axis when strafing.
## [param delta] Frame delta time in seconds.
## [param input_dir] Current movement vector.
func _update_tilt(delta: float, input_dir: Vector2) -> void:
	var target_tilt: float = input_dir.x * camera_tilt_amount
	eyes.rotation.z = lerpf(eyes.rotation.z, deg_to_rad(-target_tilt), delta * lerp_speed)


## Updates procedural sine-wave head bobbing offsets for active movement.
## [param delta] Frame delta time in seconds.
## [param input_dir] Current movement vector.
## [param is_sprinting] Sprint locomotion state flag.
## [param is_crouching] Crouch state flag.
## [param intensity_modifier] Additional scaling multiplier for shake/bob.
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

	var movement_multiplier: float = 1.0 if input_dir.length() > 0.1 else 0.5
	head_bobbing_index += bob_speed * delta * movement_multiplier

	var target_bob_y: float = (
		sin(head_bobbing_index) * (head_bobbing_current_intensity / 2.0) * intensity_modifier
	)
	var target_bob_x: float = (
		sin(head_bobbing_index / 2.0) * head_bobbing_current_intensity * intensity_modifier
	)

	headbob_offset.y = lerpf(headbob_offset.y, target_bob_y, delta * lerp_speed)
	headbob_offset.x = lerpf(headbob_offset.x, target_bob_x, delta * lerp_speed)

	eyes.position.y = headbob_offset.y + stair_offset
	eyes.position.x = headbob_offset.x


## Injects a step displacement offset when navigating step height changes.
## [param snap_amount] Step displacement distance in meters.
func add_stair_offset(snap_amount: float) -> void:
	print("CameraController: Applying stair snap offset: ", snap_amount)
	stair_offset -= snap_amount
	stair_offset = clampf(stair_offset, -0.5, 0.5)


## Decays stair displacement back to zero over time.
## [param delta] Frame delta time in seconds.
## [param player_velocity] Current horizontal movement speed.
func _update_stair_smoothing(delta: float, player_velocity: float) -> void:
	if stair_offset == 0.0:
		return

	var move_amount: float = maxf(player_velocity * delta, 2.5 * delta)
	stair_offset = move_toward(stair_offset, 0.0, move_amount)


## Calculates the normalized forward look vector from the active camera.
## [return] The unit forward [Vector3].
func get_camera_look_dir() -> Vector3:
	if is_instance_valid(camera):
		return -camera.global_transform.basis.z
	return Vector3.FORWARD


## Calculates the normalized right view vector from the active camera.
## [return] The unit right [Vector3].
func get_camera_right_dir() -> Vector3:
	if is_instance_valid(camera):
		return camera.global_transform.basis.x
	return Vector3.RIGHT


## Forces pitch and yaw rotation values directly to camera transform components.
## [param pitch] Camera vertical pitch in radians.
## [param yaw] Body horizontal yaw in radians.
func apply_saved_rotation(pitch: float, yaw: float) -> void:
	print("CameraController: apply_saved_rotation() called. Forcing camera vectors.")
	global_rotation = Vector3(pitch, yaw, 0.0)

	if is_instance_valid(head):
		head.rotation.x = pitch

	if is_instance_valid(player_body):
		player_body.rotation.y = yaw
