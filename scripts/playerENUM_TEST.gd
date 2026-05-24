extends CharacterBody3D

# 1. Define the States
enum State { IDLE, WALKING, SPRINTING, SWIMMING, CROUCHING, FLYING, JUMPING }  # Acts as our general "In Air / Falling" state

# SPEED VARS

const CROUCH_JUMP_VELOCITY := 3.5
const SPRINT_JUMP_VELOCITY := 5

# INPUT VARS

const MOUSE_SENSITIVITY = 0.5

# HEADBOB VARS
const HEAD_BOBBING_SPRINTING_SPEED := 22.0
const HEAD_BOBBING_WALKING_SPEED := 14.0
const HEAD_BOBBING_CROUCHING_SPEED := 10.0
const HEAD_BOBBING_IDLE_SPEED := 3.0

const HEAD_BOBBING_SPRINTING_INTENSITY := 0.2
const HEAD_BOBBING_WALKING_INTENSITY := 0.1
const HEAD_BOBBING_CROUCHING_INTENSITY := 0.08
const HEAD_BOBBING_IDLE_INTENSITY := 0.02

# Movement Speeds
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 6.5
@export var crouch_speed: float = 3.5
@export var swim_speed: float = 4.0
@export var fly_speed: float = 20.0
@export var jump_velocity: float = 4.5

# SPRINT FOV VARS
@export var base_fov := 75.0
@export var sprint_fov := 90.0
var fov_change_speed := 10.0

# 2. State Variables
var current_state: State = State.IDLE
var current_speed: float = 0.0
# Get gravity from project settings
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var direction := Vector3.ZERO

var head_bobbing_vector := Vector2.ZERO
var head_bobbing_index := 0.0
var head_bobbing_current_intensity := 0.0

# MOVEMENT VARS
var lerp_speed := 15.0
var air_lerp_speed := 3.0
var crouching_depth := -0.7
var last_velocity := Vector3.ZERO

var CameraTiltLeft := 3.0
var CameraTiltRight := -3.0

## FLASHLIGHT VARS
var flashlight_rotation_smoothness := 10.0
var flashlight_position_smoothness := 10.0

var bob_freq := 2.0
var bob_amp := 1.0
var bob_time := 0.0

# DEVTOOLS VARS
var noclip_speed_multiplier := 4.0

@onready var head: Node3D = $Head
@onready var eyes: Node3D = $Head/Eyes
@onready var standing_collision_shape: CollisionShape3D = $StandingCollisionShape
@onready var crouching_collision_shape: CollisionShape3D = $CrouchingCollisionShape
@onready var crouch_cast_check: RayCast3D = $CrouchCastCheck
@onready var cam: Camera3D = $Head/Eyes/Camera3D
@onready var jump_anim: AnimationPlayer = $Head/Eyes/JumpAnim

@onready var flash_light_node: Node3D = $FlashLightNode
@onready var flashlight: SpotLight3D = $FlashLightNode/Flashlight
#var is_menu_open: bool = false


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	flashlight.visible = false


func _input(event: InputEvent) -> void:
	# MOUSE LOOKING LOGIC
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))


func _physics_process(delta: float) -> void:
	# STEP 1: Decide what state the player SHOULD be in right now
	determine_state(delta)

	# STEP 2: Execute movement logic based strictly on the current state
	match current_state:
		State.FLYING:
			process_flying(delta)
			print("FLYING state")
		State.SWIMMING:
			process_swimming(delta)
			print("SWIMMING state")
		State.JUMPING:
			process_in_air(delta)
			print("JUMPING state")
		State.CROUCHING:
			current_speed = crouch_speed
			process_ground_movement(delta)
			print("CROUCHING state")
		State.SPRINTING:
			current_speed = sprint_speed
			process_ground_movement(delta)
			print("SPRINTING state")
		State.WALKING:
			current_speed = walk_speed
			process_ground_movement(delta)
			print("WALKING state")
		State.IDLE:
			current_speed = 0.0
			process_ground_movement(delta)
			print("IDLE state")

	# STEP 3: Apply the velocity to the CharacterBody3D
	move_and_slide()


# ---------------------------------------------------------
# STATE LOGIC
# ---------------------------------------------------------


func determine_state(delta: float) -> void:
	var target_fov := base_fov
	# 1. Overrides: If flying, ignore all normal ground/water logic
	if current_state == State.FLYING:
		# (You would toggle flying off via your debug menu input)
		return

	# 2. Water Check (Conceptual: assumes you have a boolean checking water Area3Ds)
	# if is_in_water:
	#     current_state = State.SWIMMING
	#     return

	# 3. Air Check
	if not is_on_floor():
		current_state = State.JUMPING
		return

	# 4. Jump Initiation
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		current_state = State.JUMPING
		return

	# 5. Ground States (Depends on Input)
	var input_dir := Input.get_vector("left", "right", "forward", "backward")

	if input_dir == Vector2.ZERO:
		current_state = State.IDLE
	elif Input.is_action_pressed("crouch"):
		current_state = State.CROUCHING
	elif Input.is_action_pressed("sprint") and input_dir.y < -0.1:
		# Only sprint if holding shift AND moving forward
		current_state = State.SPRINTING
		target_fov = sprint_fov
	else:
		current_state = State.WALKING
		target_fov = base_fov

	cam.fov = lerp(cam.fov, target_fov, delta * fov_change_speed)


# ---------------------------------------------------------
# MOVEMENT BEHAVIORS
# ---------------------------------------------------------


func process_ground_movement(delta: float) -> void:
	# Apply gravity just to keep the player snapped to the floor
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		# Friction stops the player when inputs are released
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)


func process_in_air(delta: float) -> void:
	# Always apply full gravity
	velocity.y -= gravity * delta

	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Air control (you can change current_speed here if you want less control in air)
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)


func process_flying(delta: float) -> void:
	# No gravity. Move freely based on the camera's look direction (Eyes node)
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	direction = (eyes.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity = direction * fly_speed
	else:
		velocity = velocity.move_toward(Vector3.ZERO, fly_speed * delta * 5.0)  # Dampening


func process_swimming(_delta: float) -> void:
	# Custom floaty physics for water go here
	pass
