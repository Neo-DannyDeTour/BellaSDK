class_name SystemMenuController
extends Node

# --------------------------------------
# SIGNALS
# --------------------------------------
signal pause_toggled(is_paused: bool)
signal noclip_toggled(is_flying: bool)

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Node References")
@export var player_body: CharacterBody3D
@export var camera: Camera3D
@export var eyes: Node3D
@export var standing_collision: CollisionShape3D
@export var crouching_collision: CollisionShape3D

@export_category("Menu Settings")
@export var menu_scene: PackedScene = preload("res://ui/main_menu.tscn")

@export_category("Noclip Settings")
@export var base_sprinting_speed: float = 6.5
@export var camera_tilt_amount: float = 3.0
@export var lerp_speed: float = 15.0

# --------------------------------------
# VARIABLES
# --------------------------------------
var is_paused: bool = false
var is_menu_open: bool = false
var menu_instance: CanvasLayer

var flying: bool = false
var noclip_speed_multiplier: float = 8.0

var fullbright_env: Environment
var is_stunned: bool = false

func _ready() -> void:
	print("SystemMenuController: _ready() called. Initializing sub-systems.")
	_setup_menu()
	_setup_fullbright_environment()

	# Connect to global event buses directly
	Events.debug_menu_toggled.connect(_on_debug_menu_toggled)
	Events.noclip_ui_button_pressed.connect(toggle_noclip)
	Events.fullbright_toggled.connect(_on_fullbright_toggled)

func _setup_menu() -> void:
	if menu_scene:
		menu_instance = menu_scene.instantiate() as CanvasLayer
		add_child(menu_instance)
		menu_instance.hide()

func _setup_fullbright_environment() -> void:
	fullbright_env = Environment.new()
	fullbright_env.background_mode = Environment.BG_COLOR
	fullbright_env.background_color = Color(0.5, 0.5, 0.5)
	fullbright_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	fullbright_env.ambient_light_color = Color.WHITE
	fullbright_env.ambient_light_energy = 2.0

	fullbright_env.ssao_enabled = false
	fullbright_env.ssil_enabled = false
	fullbright_env.sdfgi_enabled = false
	fullbright_env.glow_enabled = false

# --------------------------------------
# INPUT HANDLING
# --------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		print("SystemMenuController: ui_cancel intercepted. Toggling pause.")
		toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if is_paused or is_menu_open:
		get_viewport().set_input_as_handled()
		return

	if flying and event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			noclip_speed_multiplier = minf(100.0, noclip_speed_multiplier * 1.1)
			print("SystemMenuController: Noclip speed increased to ", noclip_speed_multiplier)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			noclip_speed_multiplier = maxf(0.1, noclip_speed_multiplier * 0.9)
			print("SystemMenuController: Noclip speed decreased to ", noclip_speed_multiplier)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("noclip", false):
		print("SystemMenuController: Noclip hotkey intercepted.")
		toggle_noclip()
		get_viewport().set_input_as_handled()
		return

# --------------------------------------
# META LOGIC
# --------------------------------------
func toggle_pause() -> void:
	is_paused = not is_paused
	get_tree().paused = is_paused
	print("SystemMenuController: toggle_pause() called. Paused state: ", is_paused)

	if is_paused:
		if is_instance_valid(menu_instance):
			menu_instance.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if is_instance_valid(menu_instance):
			menu_instance.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	pause_toggled.emit(is_paused)

func _on_debug_menu_toggled(is_open: bool) -> void:
	is_menu_open = is_open
	print("SystemMenuController: _on_debug_menu_toggled() called. Open state: ", is_open)

func _on_fullbright_toggled(is_fullbright: bool) -> void:
	print("SystemMenuController: _on_fullbright_toggled() called. Active: ", is_fullbright)
	if is_fullbright:
		camera.environment = fullbright_env
	else:
		camera.environment = null

	var sun: DirectionalLight3D = get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	if is_instance_valid(sun):
		sun.visible = not is_fullbright
		sun.shadow_enabled = not is_fullbright

# --------------------------------------
# NOCLIP LOGIC
# --------------------------------------
func toggle_noclip() -> void:
	flying = not flying

	if is_instance_valid(standing_collision):
		standing_collision.disabled = flying
	if is_instance_valid(crouching_collision):
		crouching_collision.disabled = flying

	if flying:
		print("SystemMenuController: Noclip ON")
		if is_instance_valid(player_body):
			player_body.velocity.y = 0.0
	else:
		print("SystemMenuController: Noclip OFF")
		if is_instance_valid(player_body):
			player_body.velocity = Vector3.ZERO
			
			var loco: Node = player_body.get("locomotion_component")
			if is_instance_valid(loco):
				loco.set("last_velocity", Vector3.ZERO) 

	Events.noclip_toggled.emit(flying)
	noclip_toggled.emit(flying)

func process_noclip(delta: float) -> void:
	if not flying or not is_instance_valid(player_body):
		return

	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var basis: Basis = camera.global_transform.basis

	var fly_dir: Vector3 = basis * Vector3(input_dir.x, 0.0, input_dir.y)
	var vertical_input: float = Input.get_axis("crouch", "jump")

	fly_dir += Vector3.UP * vertical_input
	fly_dir = fly_dir.normalized()

	var current_speed: float = base_sprinting_speed * noclip_speed_multiplier
	Events.noclip_speed_changed.emit(noclip_speed_multiplier)

	if fly_dir.length() > 0:
		player_body.velocity = fly_dir * current_speed
	else:
		player_body.velocity = Vector3.ZERO

	# Camera Tilt
	if Input.is_action_pressed("left"):
		var target_tilt: float = deg_to_rad(camera_tilt_amount)
		eyes.rotation.z = lerpf(eyes.rotation.z, target_tilt, delta * lerp_speed)
	elif Input.is_action_pressed("right"):
		var target_tilt: float = deg_to_rad(-camera_tilt_amount)
		eyes.rotation.z = lerpf(eyes.rotation.z, target_tilt, delta * lerp_speed)
	else:
		eyes.rotation.z = lerpf(eyes.rotation.z, 0.0, delta * lerp_speed)

	# Bypass physics calculations to prevent internal CharacterBody3D floor_snap drift
	player_body.global_position += player_body.velocity * delta
