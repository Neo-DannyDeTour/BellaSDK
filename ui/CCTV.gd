## A physical in-world security camera monitor that the player can interact with.
##
## Manages camera switching, orientation controls, and throttled rendering to maintain 60 FPS.
## When interacted with, [method _enable_fullscreen_mode] projects the feed onto a [CanvasLayer]
## without reallocating viewport buffers at runtime.
class_name CCTV
extends StaticBody3D

@export_category("CCTV Settings")
## The [SubViewport] that renders the CCTV camera feed to the screen material.
@export var camera_vp: SubViewport

## An array of [Node3D] markers representing locations the CCTV camera can snap to.
@export var camera_locations: Array[Node3D] = []

## Speed in degrees per second at which the camera pans when receiving input.
@export var pan_speed: float = 60.0

## Speed at which the FOV changes during a scroll wheel zoom input.
@export var zoom_speed: float = 5.0

## Minimum field of view in degrees allowed when zooming in.
@export var min_fov: float = 30.0

## Maximum field of view in degrees allowed when zooming out.
@export var max_fov: float = 75.0

## If true, interacting creates a canvas overlay that replaces the player view.
@export var replace_player_camera: bool = true

@export_category("Performance Optimization")
## The main [WorldEnvironment] to disable heavy effects on while looking through the CCTV.
@export var world_env: WorldEnvironment

## If true, temporarily disables global fog and clouds to keep framerates high.
@export var disable_global_volumetrics: bool = true

## The target frame rate the CCTV viewport updates at when actively controlled.
@export var cctv_fps: float = 15.0

## The fixed render resolution used by [member camera_vp] to prevent GPU reallocations.
@export var internal_resolution: Vector2i = Vector2i(640, 360)

## Maximum visible distance in meters for [member cctv_camera] to preserve frustum culling.
@export var camera_far_distance: float = 100.0

## The [MeshInstance3D] displaying the screen texture.
@onready var screen_mesh: MeshInstance3D = $ScreenMesh

## The interaction component the player targets to trigger the CCTV.
@onready var interact_comp: Node = $InteractComponent

## The actual [Camera3D] node inside the viewport that moves around.
@onready var cctv_camera: Camera3D = $CameraViewport/CCTVCamera

## The UI [Label] that displays controls while the player is interacting.
@onready var tutorial_label: Label = $CameraViewport/CanvasLayer/MarginContainer/TutorialLabel

## Reference to the dynamically created or existing [StandardMaterial3D] on the screen mesh.
var screen_mat_override: StandardMaterial3D = null

## The index of the currently active camera location in [member camera_locations].
var active_cam_idx: int = 0

## True if the player is currently bound to the screen controls.
var is_controlling: bool = false

## Reference to the [CharacterBody3D] currently using the CCTV.
var current_player: CharacterBody3D = null

## The target field of view being interpolated towards during a zoom.
var target_fov: float = 75.0

## The current horizontal rotation of the camera in radians.
var current_yaw: float = 0.0

## The current vertical rotation of the camera in radians.
var current_pitch: float = 0.0

## Timer that prevents the player from accidentally exiting immediately after entering.
var _interaction_cooldown: float = 0.0

## Stores the player's camera cull mask to restore it after fullscreen mode ends.
var _stored_player_cull_mask: int = 0

## The [CanvasLayer] used to draw the full-screen CCTV effect.
var _fullscreen_canvas: CanvasLayer = null

## The [TextureRect] displaying the viewport output on [_fullscreen_canvas].
var _fullscreen_rect: TextureRect = null

## Accumulator used to limit the viewport update rate to the target [member cctv_fps].
var _update_timer: float = 0.0

## Stores the [Compositor] resource before removing it to disable clouds.
var _stored_compositor: Compositor = null

## Stores the previous volumetric fog enabled state.
var _stored_volumetric_state: bool = false


## Sets up materials, viewport overrides, camera clipping, and initial positions.
func _ready() -> void:
	print("[CCTV] Initializing TV screen, camera cull limits, and UI.")
	if (
		is_instance_valid(interact_comp)
		and not interact_comp.interacted.is_connected(_on_interacted)
	):
		interact_comp.interacted.connect(_on_interacted)

	screen_mat_override = screen_mesh.get_material_override() as StandardMaterial3D
	if not is_instance_valid(screen_mat_override):
		screen_mat_override = screen_mesh.get_surface_override_material(0) as StandardMaterial3D

	if not is_instance_valid(screen_mat_override):
		screen_mat_override = StandardMaterial3D.new()
		screen_mesh.material_override = screen_mat_override

	if is_instance_valid(camera_vp):
		camera_vp.size = internal_resolution
		camera_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		camera_vp.positional_shadow_atlas_size = 0
		if is_instance_valid(screen_mat_override):
			screen_mat_override.albedo_texture = camera_vp.get_texture()

	if is_instance_valid(cctv_camera):
		cctv_camera.far = camera_far_distance
		target_fov = cctv_camera.fov
		cctv_camera.make_current()
		_force_clear_environment()

	_update_tutorial_text()

	if is_instance_valid(tutorial_label):
		tutorial_label.visible = false

	if not camera_locations.is_empty():
		_set_camera(0)


## Processes cooldowns, input panning, and throttles the viewport render rate.
## [param delta] The frame time in seconds.
func _process(delta: float) -> void:
	if _interaction_cooldown > 0.0:
		_interaction_cooldown -= delta

	if not is_controlling or not is_instance_valid(cctv_camera):
		return

	_pan_camera(delta)
	_handle_zoom(delta)

	_update_timer += delta
	var frame_time: float = 1.0 / cctv_fps

	if _update_timer >= frame_time:
		_update_timer -= frame_time
		if is_instance_valid(camera_vp):
			camera_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Handles raw player input events while bound to the CCTV controls.
## [param event] The input event to process.
func _input(event: InputEvent) -> void:
	if not is_controlling:
		return

	if event.is_action_pressed("interact") and _interaction_cooldown <= 0.0:
		_stop_controlling()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("shoot"):
		_cycle_camera()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			print("[CCTV] Zooming IN.")
			target_fov -= zoom_speed
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			print("[CCTV] Zooming OUT.")
			target_fov += zoom_speed
			get_viewport().set_input_as_handled()


## Overrides the CCTV camera's environment to remove local fog and sky passes.
func _force_clear_environment() -> void:
	print("[CCTV] Overriding camera environment to block localized fog/sky.")
	var cctv_env: Environment = cctv_camera.environment
	if not is_instance_valid(cctv_env):
		cctv_env = Environment.new()
		cctv_camera.environment = cctv_env

	cctv_env.background_mode = Environment.BG_CLEAR_COLOR
	cctv_env.sky = null
	cctv_env.volumetric_fog_enabled = false
	cctv_env.fog_enabled = false


## Updates the UI text displaying connected camera count and instructions.
func _update_tutorial_text() -> void:
	print("[CCTV] Refreshing tutorial text on screen.")
	if not is_instance_valid(tutorial_label):
		return

	var total_cams: int = camera_locations.size()
	var display_text: String = "CONTROLS:\n"
	display_text += "WASD - Move Camera\n"
	display_text += "Wheel - Zoom In / Out\n"
	display_text += "Left Click - Switch Camera\n"
	display_text += "Cameras Connected: %d" % total_cams

	tutorial_label.text = display_text


## Triggered when the player interacts with the screen, entering control mode.
## [param player] The player character interacting with the monitor.
func _on_interacted(player: CharacterBody3D) -> void:
	if is_controlling or _interaction_cooldown > 0.0:
		return

	print("[CCTV] Player attached to TV Screen! Disabling global weather systems.")
	is_controlling = true
	current_player = player
	_interaction_cooldown = 0.3
	_update_timer = 0.0

	if is_instance_valid(tutorial_label):
		tutorial_label.visible = true

	if disable_global_volumetrics and is_instance_valid(world_env):
		if is_instance_valid(world_env.compositor):
			print("[CCTV] Unhooking Compositor from WorldEnvironment.")
			_stored_compositor = world_env.compositor
			world_env.compositor = null

		if is_instance_valid(world_env.environment):
			print("[CCTV] Disabling standard volumetric fog.")
			_stored_volumetric_state = world_env.environment.volumetric_fog_enabled
			world_env.environment.volumetric_fog_enabled = false

	if is_instance_valid(current_player) and current_player.get("system_menu"):
		current_player.get("system_menu").is_stunned = true

	if replace_player_camera:
		_enable_fullscreen_mode()


## Detaches the player from the screen and restores previous visual states.
func _stop_controlling() -> void:
	print("[CCTV] Player detaching from screen. Restoring weather systems and freezing frame.")
	is_controlling = false
	_interaction_cooldown = 0.3

	if is_instance_valid(tutorial_label):
		tutorial_label.visible = false

	if disable_global_volumetrics and is_instance_valid(world_env):
		if is_instance_valid(_stored_compositor):
			print("[CCTV] Restoring Compositor to WorldEnvironment.")
			world_env.compositor = _stored_compositor
			_stored_compositor = null

		if is_instance_valid(world_env.environment):
			print("[CCTV] Restoring standard volumetric fog.")
			world_env.environment.volumetric_fog_enabled = _stored_volumetric_state

	if is_instance_valid(camera_vp):
		camera_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	if is_instance_valid(current_player) and current_player.get("system_menu"):
		current_player.get("system_menu").is_stunned = false

	if replace_player_camera:
		_disable_fullscreen_mode()

	current_player = null


## Creates a [CanvasLayer] overlay and disables player 3D rendering without resizing viewport.
func _enable_fullscreen_mode() -> void:
	print("[CCTV] Generating fullscreen overlay and culling player camera.")

	_fullscreen_canvas = CanvasLayer.new()
	_fullscreen_canvas.layer = 100
	add_child(_fullscreen_canvas)

	_fullscreen_rect = TextureRect.new()
	_fullscreen_rect.texture = camera_vp.get_texture()
	_fullscreen_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fullscreen_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_fullscreen_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fullscreen_canvas.add_child(_fullscreen_rect)

	if is_instance_valid(current_player) and current_player.get("camera_controller"):
		var cam_controller: Node = current_player.get("camera_controller")
		if is_instance_valid(cam_controller) and is_instance_valid(cam_controller.get("camera")):
			print("[CCTV] Disabling player camera rendering.")
			var p_cam: Camera3D = cam_controller.get("camera") as Camera3D
			_stored_player_cull_mask = p_cam.cull_mask
			p_cam.cull_mask = 0


## Removes the fullscreen overlay and restores the player's camera cull mask.
func _disable_fullscreen_mode() -> void:
	print("[CCTV] Destroying fullscreen overlay and restoring player camera.")

	if is_instance_valid(_fullscreen_canvas):
		_fullscreen_canvas.queue_free()
		_fullscreen_canvas = null
		_fullscreen_rect = null

	if is_instance_valid(current_player) and current_player.get("camera_controller"):
		var cam_controller: Node = current_player.get("camera_controller")
		if is_instance_valid(cam_controller) and is_instance_valid(cam_controller.get("camera")):
			print("[CCTV] Restoring player camera rendering.")
			var p_cam: Camera3D = cam_controller.get("camera") as Camera3D
			p_cam.cull_mask = _stored_player_cull_mask


## Snaps [member cctv_camera] to the specified index in [member camera_locations].
## [param index] The target camera location index.
func _set_camera(index: int) -> void:
	if index < 0 or index >= camera_locations.size():
		return

	var target_loc: Node3D = camera_locations[index]
	if not is_instance_valid(target_loc):
		return

	print("[CCTV] Setting active camera to index: ", index)
	active_cam_idx = index
	cctv_camera.global_position = target_loc.global_position

	var marker_rot: Vector3 = target_loc.global_rotation
	current_yaw = marker_rot.y
	current_pitch = marker_rot.x

	cctv_camera.rotation.y = current_yaw
	cctv_camera.rotation.x = current_pitch
	cctv_camera.rotation.z = 0.0

	if is_instance_valid(camera_vp):
		camera_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Cycles to the next available camera location index.
func _cycle_camera() -> void:
	if camera_locations.is_empty():
		return

	var next_idx: int = (active_cam_idx + 1) % camera_locations.size()
	print("[CCTV] Cycling to next camera...")
	_set_camera(next_idx)


## Translates input actions into camera yaw and pitch rotations.
## [param delta] Frame time in seconds.
func _pan_camera(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	if input_dir.length_squared() < 0.01:
		return

	var pan_rad: float = deg_to_rad(pan_speed)
	current_yaw += -input_dir.x * pan_rad * delta
	current_pitch += -input_dir.y * pan_rad * delta

	current_pitch = clampf(current_pitch, deg_to_rad(-80.0), deg_to_rad(80.0))

	cctv_camera.rotation.y = current_yaw
	cctv_camera.rotation.x = current_pitch
	cctv_camera.rotation.z = 0.0


## Smoothly interpolates the current field of view toward [member target_fov].
## [param delta] Frame time in seconds.
func _handle_zoom(delta: float) -> void:
	target_fov = clampf(target_fov, min_fov, max_fov)
	cctv_camera.fov = lerpf(cctv_camera.fov, target_fov, 10.0 * delta)
