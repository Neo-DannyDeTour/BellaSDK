class_name Player
extends CharacterBody3D

# --------------------------------------
# EXPORTS (Shared Data for States)
# --------------------------------------
@export_category("Movement Speeds")
@export var walking_speed: float = 5.0
@export var sprinting_speed: float = 6.5
@export var crouching_speed: float = 3.0
@export var swimming_speed: float = 4.0
@export var swim_up_speed: float = 5.0

@export_category("Jump & Gravity")
@export var jump_buffer_duration: float = 0.15
@export var coyote_time_duration: float = 0.15
@export var fall_gravity_multiplier: float = 1.5

@export_category("Physics Lerping")
@export var default_lerp_speed: float = 15.0
@export var air_lerp_speed: float = 3.0
@export var ice_lerp_speed: float = 1.5

# --------------------------------------
# SHARED STATE VARIABLES
# --------------------------------------
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var sprint_active: bool = false
var crouching: bool = false
var can_sprint: bool = true
var on_ice: bool = false

var direction: Vector3 = Vector3.ZERO
var last_velocity: Vector3 = Vector3.ZERO

# Environmental Cooldowns/Detectors
var zipline_cooldown: float = 0.0
var monkey_bar_cooldown: float = 0.0
var available_monkey_bar: Node3D = null
#var overlapping_water_areas: Array[Area3D] = []
var overlapping_waterfall_areas: Array[Area3D] = []

var in_updraft: bool = false
var updraft_strength: float = 0.0
var updraft_top_y: float = 0.0

var current_water_node: Node3D = null
var flashlight_controller: Node = null

# --------------------------------------
# COMPONENT REFERENCES
# --------------------------------------
@onready var state_machine: PlayerStateMachine = $StateMachine
@onready var camera_controller: CameraController = %CameraController
@onready var interaction_scanner: InteractionScanner = $InteractionScanner
@onready var footstep_manager: FootstepManager = $FootstepManager
@onready var vfx_manager: ScreenVFXManager = $ScreenVFXManager
@onready var vault_controller: VaultController = $VaultController
@onready var physics_pusher: PhysicsPusher = $PhysicsPusher
@onready var system_menu: SystemMenuController = $SystemMenuController
@onready var health_component: Node = $HealthComponent  # Adjust type as needed

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
@onready var head: Node3D = $Head
@onready var eyes: Node3D = $Head/Eyes
@onready var camera: Camera3D = $Head/Eyes/Camera3D
# @onready var camera_anims: AnimationPlayer = $Head/Eyes/CameraAnims
@onready var standing_collision: CollisionShape3D = $StandingCollisionShape
@onready var crouching_collision: CollisionShape3D = $CrouchingCollisionShape
@onready var crouch_cast_check: RayCast3D = $CrouchCastCheck


# --------------------------------------
# INITIALIZATION
# --------------------------------------
func _ready() -> void:
	# 1. Connect Health
	if health_component.has_signal("health_changed"):
		health_component.health_changed.connect(_on_health_changed)
	if health_component.has_signal("died"):
		health_component.died.connect(_on_player_died)

	# 2. Add exceptions
	if has_node("Head/Eyes/Camera3D/SpringArm3D"):
		var spring_arm: SpringArm3D = $Head/Eyes/Camera3D/SpringArm3D
		spring_arm.add_excluded_object(self.get_rid())

	# Lock the mouse into the game window!
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --------------------------------------
# HARDWARE INPUT ROUTING
# --------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# 1. Block all other inputs if we are paused, in a menu, or stunned
	if system_menu.is_paused or system_menu.is_menu_open or system_menu.get("is_stunned"):
		return

	# 2. Route Mouse Look to the Camera Controller
	if event is InputEventMouseMotion:
		camera_controller.handle_mouse_input(
			event,
			interaction_scanner.is_in_terminal_mode,
			interaction_scanner.is_heavy_lifting,
			interaction_scanner.heavy_lift_yaw_base
		)

		# If you extracted the flashlight, route sway here too:
		# if has_node("CameraController/FlashlightController"):
		#     $CameraController/FlashlightController.sway_target += event.relative

	# 3. Route Interactions and Combat to the Scanner
	if event.is_action_pressed("interact"):
		interaction_scanner.handle_interact_input()

	if event.is_action_pressed("shoot"):
		interaction_scanner.handle_shoot_input()


# --------------------------------------
# GLOBAL EVENT ROUTING
# --------------------------------------
func _on_health_changed(new_health: int) -> void:
	Events.player_health_changed.emit(new_health)


func _on_player_died() -> void:
	print("Player has died. Triggering game over sequence...")
	# Events.player_died.emit()


# --------------------------------------
# ENVIRONMENTAL TRIGGERS (Called by Area3Ds)
# --------------------------------------
func set_available_monkey_bar(bar: Node3D) -> void:
	available_monkey_bar = bar


func clear_available_monkey_bar(bar: Node3D) -> void:
	if available_monkey_bar == bar:
		available_monkey_bar = null


func teleport_to(new_position: Vector3, stun_time: float = 0.1) -> void:
	global_position = new_position
	velocity = Vector3.ZERO
	last_velocity = Vector3.ZERO
	direction = Vector3.ZERO

	if stun_time > 0.0:
		system_menu.is_stunned = true  # Assuming you move is_stunned to the menu/meta controller
		get_tree().create_timer(stun_time).timeout.connect(
			func() -> void: system_menu.is_stunned = false
		)


# --------------------------------------
# MASTER PHYSICS OVERRIDE
# --------------------------------------
func _physics_process(delta: float) -> void:
	if zipline_cooldown > 0.0:
		zipline_cooldown -= delta
	if monkey_bar_cooldown > 0.0:
		monkey_bar_cooldown -= delta

	# 1. Handle Pauses & Stuns
	if system_menu.is_paused or system_menu.is_menu_open or system_menu.get("is_stunned"):
		state_machine.set_physics_process(false)
		state_machine.set_process_unhandled_input(false)
		velocity = Vector3.ZERO
		return

	# 2. Handle Noclip (Cheat Mode)
	if system_menu.flying:
		state_machine.set_physics_process(false)
		state_machine.set_process_unhandled_input(false)
		system_menu.process_noclip(delta)
		return

	# 3. Normal Gameplay (Let the State Machine take the wheel!)
	state_machine.set_physics_process(true)
	state_machine.set_process_unhandled_input(true)


# --------------------------------------
# ENVIRONMENTAL ADAPTERS
# --------------------------------------


# 1. Ropes
func _on_rope_grabbed(rope_body: RigidBody3D) -> void:
	if vault_controller.is_vaulting:
		return
	state_machine.transition_to("Rope", {"rope_node": rope_body})


# 2. Ziplines (Adjust the parameters if your zipline script passes different data!)
func _on_zipline_grabbed(zipline_ref: Node3D, start_pos: Vector3, end_pos: Vector3) -> void:
	if vault_controller.is_vaulting:
		return
	state_machine.transition_to(
		"Zipline", {"zipline_node": zipline_ref, "start_pos": start_pos, "end_pos": end_pos}
	)


# 3. Ladders (Change the function name to whatever your ladder script tries to call)
func _on_ladder_grabbed(ladder_node: Node3D) -> void:
	if vault_controller.is_vaulting:
		return
	state_machine.transition_to("Ladder", {"ladder_node": ladder_node})


# 4. Fast Ropes
func _on_fastrope_grabbed() -> void:
	state_machine.transition_to("FastRope")


# 5. Updraft
func enter_updraft(strength: float, top_y: float) -> void:
	in_updraft = true
	updraft_strength = strength
	updraft_top_y = top_y

	if state_machine.state.name == "Ground":
		state_machine.transition_to("Air")


func exit_updraft() -> void:
	in_updraft = false
	updraft_strength = 0.0


func enter_water(water_volume: Node3D) -> void:
	current_water_node = water_volume

	# Don't force Swim if we are doing a dedicated parkour move
	if state_machine.state.name not in ["Vault", "Zipline", "Rope"]:
		state_machine.transition_to("Swim")


func exit_water(water_volume: Node3D) -> void:
	# Only clear it if we are leaving the exact pool of water we were in
	if current_water_node == water_volume:
		current_water_node = null

		# THE FIX: Only transition to Air if we are actively swimming.
		# If we are Vaulting (or on a Zipline, Rope, etc.), let that state finish!
		if state_machine.state.name == "Swim":
			state_machine.transition_to("Air")
