## Autonomous spectator camera allowing free 3D flying and orientation inspection.
#class_name FreecamController
extends Camera3D

## Base translation flight speed in meters per second.
const BASE_SPEED: float = 12.0

## Multiplier applied to flight speed when holding sprint action or Shift.
const FAST_SPEED_MULT: float = 3.0

## Mouse look angular sensitivity factor.
const MOUSE_SENSITIVITY: float = 0.003

## Gamepad right stick look sensitivity in radians per second.
const JOYPAD_SENSITIVITY: float = 2.5

## Gamepad right stick analog deadzone threshold.
const JOYPAD_DEADZONE: float = 0.15

## Node path constant to developer console canvas layer.
const CONSOLE_NODE_PATH: NodePath = ^"/root/InGameConsole"

## Flight translation speed multiplier adjusted dynamically via mouse wheel.
var speed_multiplier: float = 1.0

## Accumulated vertical pitch angle clamped in radians.
var _pitch: float = 0.0

## Accumulated horizontal yaw angle in radians.
var _yaw: float = 0.0

## Cached reference to the player entity.
var _player: Node3D = null

## Cached reference to the player original active camera.
var _original_camera: Camera3D = null


## Intercepts mouse look and capture inputs while freecam is active.
func _input(event: InputEvent) -> void:
	if _is_console_open():
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.is_pressed() and not key_event.is_echo():
			if key_event.keycode == KEY_T and key_event.shift_pressed:
				teleport_player_and_exit()
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.is_pressed():
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				speed_multiplier = clampf(speed_multiplier * 1.25, 0.1, 10.0)
				print("FreecamController: Speed multiplier increased -> ", speed_multiplier)
				get_viewport().set_input_as_handled()
				return
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				speed_multiplier = clampf(speed_multiplier / 1.25, 0.1, 10.0)
				print("FreecamController: Speed multiplier decreased -> ", speed_multiplier)
				get_viewport().set_input_as_handled()
				return
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(
			_pitch - motion.relative.y * MOUSE_SENSITIVITY, -deg_to_rad(89.0), deg_to_rad(89.0)
		)
		transform.basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0), EULER_ORDER_YXZ)
		get_viewport().set_input_as_handled()


## Updates camera translation along local basis vectors using GestureInputManager.
func _process(delta: float) -> void:
	if _is_console_open():
		return

	var joy_x: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var joy_y: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var joy_rotated: bool = false
	if absf(joy_x) > JOYPAD_DEADZONE:
		_yaw -= joy_x * JOYPAD_SENSITIVITY * delta
		joy_rotated = true
	if absf(joy_y) > JOYPAD_DEADZONE:
		_pitch = clampf(
			_pitch - joy_y * JOYPAD_SENSITIVITY * delta, -deg_to_rad(89.0), deg_to_rad(89.0)
		)
		joy_rotated = true
	if joy_rotated:
		transform.basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0), EULER_ORDER_YXZ)

	var h_input: Vector2 = GestureInputManager.get_vector("left", "right", "forward", "backward")
	var v_input: float = GestureInputManager.get_axis("crouch", "jump")

	if Input.is_key_pressed(KEY_W):
		h_input.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		h_input.y += 1.0
	if Input.is_key_pressed(KEY_A):
		h_input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		h_input.x += 1.0
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E):
		v_input += 1.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_C):
		v_input -= 1.0

	if h_input.length_squared() > 1.0:
		h_input = h_input.normalized()

	v_input = clampf(v_input, -1.0, 1.0)

	var move_vec: Vector3 = (
		(transform.basis.x * h_input.x) + (transform.basis.z * h_input.y) + (Vector3.UP * v_input)
	)

	if move_vec.length_squared() > 0.001:
		var is_fast: bool = (
			GestureInputManager.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)
		)
		var current_speed: float = (
			BASE_SPEED * speed_multiplier * (FAST_SPEED_MULT if is_fast else 1.0)
		)
		global_position += move_vec.normalized() * current_speed * delta


## Configures spectator camera transform and locks player locomotion.
func setup(source_camera: Camera3D, player_node: Node3D) -> void:
	print("FreecamController: Initializing spectator camera.")
	_original_camera = source_camera
	_player = player_node

	if is_instance_valid(source_camera):
		global_transform = source_camera.global_transform
		fov = source_camera.fov
		var cam_rot: Vector3 = source_camera.global_rotation
		_yaw = cam_rot.y
		_pitch = cam_rot.x
		transform.basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0), EULER_ORDER_YXZ)

	current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.player_cinematic_lock_requested.emit(true)


## Teleports player entity to current spectator coordinates and exits freecam.
func teleport_player_and_exit() -> void:
	print("FreecamController: Teleporting player to camera position.")
	if is_instance_valid(_player):
		if is_inside_tree() and _player.is_inside_tree():
			_player.global_position = global_position
		else:
			_player.position = position
		if _player.has_method(&"apply_saved_rotation"):
			_player.call(&"apply_saved_rotation", _pitch, _yaw)
	restore_and_exit()


## Restores player camera, unlocks player locomotion, and frees freecam node.
func restore_and_exit() -> void:
	print("FreecamController: Exiting spectator camera.")
	Events.player_cinematic_lock_requested.emit(false)
	if is_instance_valid(_original_camera):
		_original_camera.current = true
	queue_free()


## Evaluates whether the in-game developer console is currently visible.
func _is_console_open() -> bool:
	var console_layer: CanvasLayer = get_node_or_null(CONSOLE_NODE_PATH) as CanvasLayer
	return is_instance_valid(console_layer) and console_layer.visible
