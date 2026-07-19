extends CharacterBody3D
class_name PlayerDrone

@export var move_speed: float = 8.0
@export var vertical_speed: float = 5.0
@export var mouse_sensitivity: float = 0.002
@export var tilt_angle: float = 15.0
@export var tilt_speed: float = 5.0

var is_possessed: bool = false
var last_interact_time: float = 0.0
var double_tap_window: float = 0.4
var camera_pitch: float = 0.0
var original_player: CharacterBody3D = null

@onready var tilt_pivot: Node3D = $TiltPivot
@onready var camera: Camera3D = $TiltPivot/DroneCamera
@onready var interact_comp: InteractComponent = $InteractComponent
@onready var drone_hud: CanvasLayer = $DroneHUD


func _ready() -> void:
	camera.current = false
	drone_hud.hide()
	interact_comp.interacted.connect(_on_drone_interacted)


func _on_drone_interacted(character: CharacterBody3D) -> void:
	print("PlayerDrone: _on_drone_interacted() called. Deploying or interacting with drone.")
	if not is_possessed:
		original_player = character
		possess_drone()


func possess_drone() -> void:
	print("PlayerDrone: Possessing. Activating camera and HUD.")
	is_possessed = true
	camera.current = true
	drone_hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if is_instance_valid(original_player) and original_player.has_method("start_operating_machine"):
		original_player.start_operating_machine()


func exit_drone() -> void:
	print("PlayerDrone: Exiting. Restoring player control.")
	is_possessed = false
	camera.current = false
	drone_hud.hide()

	if is_instance_valid(original_player) and original_player.has_method("stop_operating_machine"):
		original_player.stop_operating_machine()

	original_player = null


# CHANGED: Upgraded to _input to ensure priority over UI elements
func _input(event: InputEvent) -> void:
	if not is_possessed:
		return

	if event is InputEventMouseMotion:
		_handle_mouse_look(event)
		# Consume the mouse event so the hidden player doesn't try to use it
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("interact"):
		_check_exit_double_tap()
		# CRITICAL FIX: Consume the interact key so the player doesn't immediately re-trigger it
		get_viewport().set_input_as_handled()


func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	# Print statement added to verify mouse tracking is alive
	if absf(event.relative.x) > 10.0 or absf(event.relative.y) > 10.0:
		print("PlayerDrone: Mouse motion detected. Moving camera.")

	rotate_y(-event.relative.x * mouse_sensitivity)

	camera_pitch = clampf(camera_pitch - event.relative.y * mouse_sensitivity, -1.5, 1.5)
	camera.transform.basis = Basis()
	camera.rotate_x(camera_pitch)


func _check_exit_double_tap() -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0

	if current_time - last_interact_time < double_tap_window:
		print("PlayerDrone: Double-tap threshold met. Triggering exit.")
		exit_drone()

	last_interact_time = current_time


func _physics_process(delta: float) -> void:
	if not is_possessed:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	_process_movement(delta)


func _process_movement(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var vert_input: float = 0.0
	if Input.is_action_pressed("jump"):
		vert_input += 1.0
	if Input.is_action_pressed("crouch"):
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


func _apply_visual_tilt(input_dir: Vector2, delta: float) -> void:
	var target_pitch: float = -input_dir.y * deg_to_rad(tilt_angle)
	var target_roll: float = -input_dir.x * deg_to_rad(tilt_angle)

	tilt_pivot.rotation.x = lerpf(tilt_pivot.rotation.x, target_pitch, tilt_speed * delta)
	tilt_pivot.rotation.z = lerpf(tilt_pivot.rotation.z, target_roll, tilt_speed * delta)
