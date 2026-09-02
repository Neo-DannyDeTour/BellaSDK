class_name SystemMenuController
extends Node

# --------------------------------------
# SIGNALS
# --------------------------------------
## Emitted when the game's pause status changes.
## [param is_paused] True if the game entered pause state.
signal pause_toggled(is_paused: bool)

## Emitted when noclip flight mode is toggled.
## [param is_flying] True if the player has entered noclip flight.
signal noclip_toggled(is_flying: bool)

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Node References")

## The player character physics body.
@export var player_body: CharacterBody3D

## The primary gameplay camera.
@export var camera: Camera3D

## The head/eye node used for camera tilting effects.
@export var eyes: Node3D

## Collision shape representing standing height.
@export var standing_collision: CollisionShape3D

## Collision shape representing crouching height.
@export var crouching_collision: CollisionShape3D

@export_category("Menu Settings")

## Packed scene resource representing the main pause and system menu.
@export var menu_scene: PackedScene = preload("res://ui/main_menu.tscn")

@export_category("Noclip Settings")

## Base movement speed while sprinting in noclip mode.
@export var base_sprinting_speed: float = 6.5

## Degrees of roll applied to the camera when strafing in noclip mode.
@export var camera_tilt_amount: float = 3.0

## Smoothing speed multiplier for camera rotations and tilts.
@export var lerp_speed: float = 15.0

# --------------------------------------
# VARIABLES
# --------------------------------------
## Security variable: Indicates if debug commands (noclip) are allowed via input or events.
var is_debug_allowed: bool = OS.has_feature("debug")

## Indicates if the game is currently paused.
var is_paused: bool = false

## Indicates if a debug menu or overlay is open.
var is_menu_open: bool = false

## Instance of the main menu CanvasLayer.
var menu_instance: CanvasLayer

## Indicates if noclip flying is active.
var flying: bool = false

## Multiplier scaling noclip flight movement speed.
var noclip_speed_multiplier: float = 8.0

## Fallback fullbright environment applied during debug mode.
var fullbright_env: Environment

## Tracks whether the player character is currently stunned.
var is_stunned: bool = false

## Cached original environment applied to camera before fullbright toggle.
var _cached_camera_env: Environment = null


## Lifecycle initialization connecting debug events and instantiating menus.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("SystemMenuController: Initializing system menu and debug handlers.")
	_setup_menu()
	_setup_fullbright_environment()

	Events.debug_menu_toggled.connect(_on_debug_menu_toggled)
	Events.noclip_ui_button_pressed.connect(toggle_noclip)
	Events.fullbright_toggled.connect(_on_fullbright_toggled)


## Instantiates the menu scene and attaches it to the viewport root safely.
func _setup_menu() -> void:
	if not menu_scene:
		push_warning("SystemMenuController: menu_scene is null or not assigned.")
		return

	var scene_node: Node = menu_scene.instantiate()
	if not is_instance_valid(scene_node):
		push_error("SystemMenuController: Failed to instantiate menu_scene.")
		return

	menu_instance = scene_node as CanvasLayer
	if is_instance_valid(menu_instance):
		add_child(menu_instance)
		menu_instance.hide()
		print("SystemMenuController: Menu instance initialized successfully.")
	else:
		push_error("SystemMenuController: menu_scene root is not a CanvasLayer.")
		scene_node.queue_free()


## Builds the environment configuration used for fullbright debug viewing.
func _setup_fullbright_environment() -> void:
	print("SystemMenuController: Building fullbright Environment resource.")
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
## Intercepts global unhandled actions such as pause and noclip hotkeys.
## [param event] The unhandled input event.
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
			Events.noclip_speed_changed.emit(noclip_speed_multiplier)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			noclip_speed_multiplier = maxf(0.1, noclip_speed_multiplier * 0.9)
			Events.noclip_speed_changed.emit(noclip_speed_multiplier)
			get_viewport().set_input_as_handled()
			return

	if is_debug_allowed and event.is_action_pressed("noclip", false):
		print("SystemMenuController: Noclip hotkey intercepted.")
		toggle_noclip()
		get_viewport().set_input_as_handled()
		return


# --------------------------------------
# META LOGIC
# --------------------------------------
## Toggles the global pause state and shows or hides the system menu instance.
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
			if menu_instance.has_method("_return_to_main_buttons"):
				menu_instance.call("_return_to_main_buttons")
			menu_instance.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	pause_toggled.emit(is_paused)


## Tracks whether an external debug menu is opened.
## [param is_open] True if the debug menu was opened.
func _on_debug_menu_toggled(is_open: bool) -> void:
	is_menu_open = is_open
	print("SystemMenuController: _on_debug_menu_toggled() called. Open state: ", is_open)


## Handles fullbright debug rendering toggling.
## [param is_fullbright] True to enable fullbright lighting override.
func _on_fullbright_toggled(is_fullbright: bool) -> void:
	print("SystemMenuController: _on_fullbright_toggled() called. Active: ", is_fullbright)
	if not is_instance_valid(camera):
		return

	if is_fullbright:
		_cached_camera_env = camera.environment
		camera.environment = fullbright_env
	else:
		camera.environment = _cached_camera_env
		_cached_camera_env = null

	var sun: DirectionalLight3D = get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	if is_instance_valid(sun):
		sun.visible = not is_fullbright
		sun.shadow_enabled = not is_fullbright


# --------------------------------------
# NOCLIP LOGIC
# --------------------------------------
## Toggles the noclip state, disabling player physics collisions and gravities.
func toggle_noclip() -> void:
	if not is_debug_allowed:
		return

	print("SystemMenuController: toggle_noclip() called.")
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


## Calculates frame velocity and applies direct transform translations during noclip flight.
## [param delta] The frame delta time in seconds.
func process_noclip(delta: float) -> void:
	if not flying or not is_instance_valid(player_body):
		return

	var input_dir: Vector2 = GestureInputManager.get_vector("left", "right", "forward", "backward")
	var basis: Basis = camera.global_transform.basis

	var fly_dir: Vector3 = basis * Vector3(input_dir.x, 0.0, input_dir.y)
	var vertical_input: float = GestureInputManager.get_axis("crouch", "jump")

	fly_dir += Vector3.UP * vertical_input
	fly_dir = fly_dir.normalized()

	var current_speed: float = base_sprinting_speed * noclip_speed_multiplier
	Events.noclip_speed_changed.emit(noclip_speed_multiplier)

	if fly_dir.length() > 0:
		player_body.velocity = fly_dir * current_speed
	else:
		player_body.velocity = Vector3.ZERO

	if GestureInputManager.is_action_pressed("left"):
		var target_tilt: float = deg_to_rad(camera_tilt_amount)
		eyes.rotation.z = lerpf(eyes.rotation.z, target_tilt, delta * lerp_speed)
	elif GestureInputManager.is_action_pressed("right"):
		var target_tilt: float = deg_to_rad(-camera_tilt_amount)
		eyes.rotation.z = lerpf(eyes.rotation.z, target_tilt, delta * lerp_speed)
	else:
		eyes.rotation.z = lerpf(eyes.rotation.z, 0.0, delta * lerp_speed)

	player_body.global_position += player_body.velocity * delta
