## Controllable surveillance and flight drone possessed by the player character.
class_name PlayerDrone
extends CharacterBody3D

## Maximum horizontal movement velocity in meters per second.
@export var move_speed: float = 8.0

## Maximum vertical ascent and descent speed in meters per second.
@export var vertical_speed: float = 5.0

## Mouse look sensitivity factor applied to camera rotations.
@export var mouse_sensitivity: float = 0.002

## Maximum visual banking tilt angle in degrees during lateral movement.
@export var tilt_angle: float = 15.0

## Interpolation speed applied to visual tilt smoothing.
@export var tilt_speed: float = 5.0

## Tracks whether player currently possesses and controls this drone.
var is_possessed: bool = false

## Timestamp in seconds of the most recent interaction input event.
var last_interact_time: float = 0.0

## Permitted time window in seconds to register double-tap exit trigger.
var double_tap_window: float = 0.4

## Accumulated vertical look pitch angle in radians.
var camera_pitch: float = 0.0

## Reference to originating player body possessing this drone.
var original_player: CharacterBody3D = null

## Pivot transform applying procedural visual roll and pitch banking.
@onready var tilt_pivot: Node3D = $TiltPivot

## Perspective camera rendering active drone viewport view.
@onready var camera: Camera3D = $TiltPivot/DroneCamera

## Interaction trigger component detecting possession activations.
@onready var interact_comp: InteractComponent = $InteractComponent

## Canvas overlay presenting flight instruments and crosshairs.
@onready var drone_hud: CanvasLayer = $DroneHUD


## Configures default inactive camera state and connects interaction signal.
func _ready() -> void:
	print("PlayerDrone: Initializing drone unit: ", name)
	camera.current = false
	drone_hud.hide()
	interact_comp.interacted.connect(_on_drone_interacted)


## Handles player interaction signal, initiating drone possession sequence.
func _on_drone_interacted(character: CharacterBody3D) -> void:
	print("PlayerDrone: _on_drone_interacted() called. Deploying or interacting with drone.")
	if not is_possessed:
		original_player = character
		possess_drone()


## Activates drone camera, locks mouse cursor, and freezes player character.
func possess_drone() -> void:
	print("PlayerDrone: Possessing. Activating camera and HUD.")
	is_possessed = true
	camera.current = true
	drone_hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if is_instance_valid(original_player) and original_player.has_method("start_operating_machine"):
		original_player.call(&"start_operating_machine")


## Restores player camera control, hides HUD, and unfreezes player body.
func exit_drone() -> void:
	print("PlayerDrone: Exiting. Restoring player control.")
	is_possessed = false
	camera.current = false
	drone_hud.hide()

	if is_instance_valid(original_player) and original_player.has_method("stop_operating_machine"):
		original_player.call(&"stop_operating_machine")

	original_player = null


## Intercepts look motion and double-tap exit inputs while possessed.
func _input(event: InputEvent) -> void:
	if not is_possessed:
		return

	if event is InputEventMouseMotion:
		_handle_mouse_look(event as InputEventMouseMotion)
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("interact"):
		_check_exit_double_tap()
		get_viewport().set_input_as_handled()


## Updates drone yaw and clamped camera pitch from mouse movements.
func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	if absf(event.relative.x) > 10.0 or absf(event.relative.y) > 10.0:
		print("PlayerDrone: Mouse motion detected. Moving camera.")

	rotate_y(-event.relative.x * mouse_sensitivity)

	camera_pitch = clampf(camera_pitch - event.relative.y * mouse_sensitivity, -1.5, 1.5)
	camera.transform.basis = Basis()
	camera.rotate_x(camera_pitch)


## Evaluates time difference between interact presses to trigger detachment.
func _check_exit_double_tap() -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0

	if current_time - last_interact_time < double_tap_window:
		print("PlayerDrone: Double-tap threshold met. Triggering exit.")
		exit_drone()

	last_interact_time = current_time


## Dispatches directional flight updates or zeros residual velocities.
func _physics_process(delta: float) -> void:
	if not is_possessed:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	_process_movement(delta)


## Translates input vectors into 3D flight velocities and invokes motion.
func _process_movement(delta: float) -> void:
	var input_dir: Vector2 = GestureInputManager.get_vector("left", "right", "forward", "backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var vert_input: float = 0.0
	if GestureInputManager.is_action_pressed("jump"):
		vert_input += 1.0
	if GestureInputManager.is_action_pressed("crouch"):
		vert_input -= 1.0

	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	velocity.y = vert_input * vertical_speed

	_apply_visual_tilt(input_dir, delta)
	move_and_slide()


## Smoothly tilts pivot node matching directional movement input.
func _apply_visual_tilt(input_dir: Vector2, delta: float) -> void:
	var target_pitch: float = -input_dir.y * deg_to_rad(tilt_angle)
	var target_roll: float = -input_dir.x * deg_to_rad(tilt_angle)

	tilt_pivot.rotation.x = lerpf(tilt_pivot.rotation.x, target_pitch, tilt_speed * delta)
	tilt_pivot.rotation.z = lerpf(tilt_pivot.rotation.z, target_roll, tilt_speed * delta)
