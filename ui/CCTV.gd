## Interactive in-world security terminal displaying live camera feeds.
## Throttles update rates and isolates internal camera passes to sustain 60 FPS.
class_name CCTV
extends StaticBody3D

@export_category("CCTV Settings")
## Target [SubViewport] rendering the camera feed to the terminal monitor screen.
@export var camera_vp: SubViewport

## Marker points defining locations the CCTV camera perspective can cycle through.
@export var camera_locations: Array[Node3D] = []

## Panning rotational speed in degrees per second when handling input.
@export var pan_speed: float = 60.0

## FOV modification step applied during mouse wheel zoom inputs.
@export var zoom_speed: float = 5.0

## Minimum permitted field of view angle in degrees.
@export var min_fov: float = 30.0

## Maximum permitted field of view angle in degrees.
@export var max_fov: float = 75.0

## Replaces the main player view with a fullscreen HUD canvas overlay when active.
@export var replace_player_camera: bool = true

@export_category("Performance Optimization")
## The primary level [WorldEnvironment] to toggle heavy effects on during usage.
@export var world_env: WorldEnvironment

## Disables global volumetric fog while looking through security terminals.
@export var disable_global_volumetrics: bool = true

## Refresh frame rate cap of the CCTV viewport when actively operated.
@export var cctv_fps: float = 15.0

## Fixed buffer resolution applied to [member camera_vp] to prevent reallocations.
@export var internal_resolution: Vector2i = Vector2i(640, 360)

## Far clipping distance in meters applied to [member cctv_camera].
@export var camera_far_distance: float = 100.0

## Screen mesh display instance mapping the CCTV render target.
@onready var screen_mesh: MeshInstance3D = $ScreenMesh

## Interaction component receiving activation trigger events.
@onready var interact_comp: Node = $InteractComponent

## Perspective camera rendering the security feed inside [member camera_vp].
@onready var cctv_camera: Camera3D = $CameraViewport/CCTVCamera

## UI label presenting terminal controls and active camera indices.
@onready var tutorial_label: Label = $CameraViewport/CanvasLayer/MarginContainer/TutorialLabel

## Surface material override bound to [member screen_mesh].
var screen_mat_override: StandardMaterial3D = null

## Array index pointing to the active location inside [member camera_locations].
var active_cam_idx: int = 0

## Tracks whether the player character is currently operating the CCTV monitor.
var is_controlling: bool = false

## Reference to the player body currently controlling the security feed.
var current_player: CharacterBody3D = null

## Interpolation target field of view angle in degrees.
var target_fov: float = 75.0

## Current horizontal yaw angle of the camera in radians.
var current_yaw: float = 0.0

## Current vertical pitch angle of the camera in radians.
var current_pitch: float = 0.0

## Input debounce timer preventing instant exit upon terminal activation.
var _interaction_cooldown: float = 0.0

## Stored visual render mask of the player camera before fullscreen override.
var _stored_player_cull_mask: int = 0

## Dedicated [CanvasLayer] presenting the fullscreen camera overlay feed.
var _fullscreen_canvas: CanvasLayer = null

## Screen texture rect projecting the CCTV feed onto the fullscreen canvas.
var _fullscreen_rect: TextureRect = null

## Accumulator measuring elapsed frame time against target [member cctv_fps].
var _update_timer: float = 0.0

## Stored compositor resource removed to disable volumetrics during operation.
var _stored_compositor: Compositor = null

## Stored volumetric fog activation state restored when detaching from terminal.
var _stored_volumetric_state: bool = false

## Original sky resource cached to ensure visual state parity.
var _stored_cctv_sky: Sky = null

## Original background mode cached from the CCTV camera environment.
var _stored_bg_mode: Environment.BGMode = Environment.BG_KEEP


## Connects interactable components, initializes screen materials, and limits pipeline.
func _ready() -> void:
	print("[CCTV] Initializing security terminal instance: ", name)
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

	_configure_cctv_viewport()

	if is_instance_valid(cctv_camera):
		cctv_camera.far = camera_far_distance
		target_fov = cctv_camera.fov
		cctv_camera.current = true
		_force_clear_environment()

	_update_tutorial_text()

	if is_instance_valid(tutorial_label):
		tutorial_label.visible = false

	if not camera_locations.is_empty():
		_set_camera(0)


## Strips shadow maps and anti-aliasing features from the CCTV viewport.
func _configure_cctv_viewport() -> void:
	print("[CCTV] Applying stripped graphics pipeline limits to viewport.")
	if not is_instance_valid(camera_vp):
		return

	camera_vp.size = internal_resolution
	camera_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	camera_vp.positional_shadow_atlas_size = 0
	camera_vp.msaa_3d = Viewport.MSAA_DISABLED
	camera_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	camera_vp.use_taa = false
	camera_vp.use_debanding = false
	camera_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

	if is_instance_valid(screen_mat_override):
		screen_mat_override.albedo_texture = camera_vp.get_texture()


## Manages camera rotation, FOV interpolation, and throttles viewport redraw rate.
## [param delta] Frame duration in seconds.
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


## Intercepts camera navigation inputs and detaches player upon exit command.
## [param event] Input event to process.
func _input(event: InputEvent) -> void:
	if not is_controlling:
		return

	if event.is_action_pressed("interact") and _interaction_cooldown <= 0.0:
		print("[CCTV] Player pressed interact to disconnect.")
		_stop_controlling()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("shoot"):
		print("[CCTV] Player requested camera cycle.")
		_cycle_camera()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			print("[CCTV] Zooming camera IN.")
			target_fov -= zoom_speed
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			print("[CCTV] Zooming camera OUT.")
			target_fov += zoom_speed
			get_viewport().set_input_as_handled()


## Overrides camera environment to permanently disable SDFGI, fog, and SSR passes.
func _force_clear_environment() -> void:
	print("[CCTV] Stripping camera environment of fog, sky, and SDFGI.")
	var cctv_env: Environment = cctv_camera.environment
	if not is_instance_valid(cctv_env):
		cctv_env = Environment.new()
		cctv_camera.environment = cctv_env
	else:
		cctv_env = cctv_env.duplicate() as Environment
		cctv_camera.environment = cctv_env

	_stored_cctv_sky = cctv_env.sky
	_stored_bg_mode = cctv_env.background_mode

	cctv_env.background_mode = Environment.BG_CLEAR_COLOR
	cctv_env.sky = null
	cctv_env.sdfgi_enabled = false
	cctv_env.volumetric_fog_enabled = false
	cctv_env.fog_enabled = false
	cctv_env.ssao_enabled = false
	cctv_env.ssil_enabled = false
	cctv_env.glow_enabled = false
	cctv_env.ssr_enabled = false


## Refreshes onscreen control keybind hints and total camera numbers.
func _update_tutorial_text() -> void:
	print("[CCTV] Refreshing onscreen terminal tutorial text.")
	if not is_instance_valid(tutorial_label):
		return

	var total_cams: int = camera_locations.size()
	var display_text: String = "CONTROLS:\n"
	display_text += "WASD - Move Camera\n"
	display_text += "Wheel - Zoom In / Out\n"
	display_text += "Left Click - Switch Camera\n"
	display_text += "Cameras Connected: %d" % total_cams

	tutorial_label.text = display_text


## Binds the player to CCTV controls and disables external volumetric systems.
## [param player] Character body claiming control of the terminal.
func _on_interacted(player: CharacterBody3D) -> void:
	if is_controlling or _interaction_cooldown > 0.0:
		return

	print("[CCTV] Player attached to terminal screen. Freezing outside systems.")
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
			print("[CCTV] Temporarily disabling volumetric fog.")
			_stored_volumetric_state = world_env.environment.volumetric_fog_enabled
			world_env.environment.volumetric_fog_enabled = false

	if is_instance_valid(current_player) and current_player.get("system_menu"):
		current_player.get("system_menu").is_stunned = true

	if replace_player_camera:
		_enable_fullscreen_mode()


## Detaches the player from terminal controls and restores previous visual states.
func _stop_controlling() -> void:
	print("[CCTV] Player detaching from monitor. Restoring world states.")
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
			print("[CCTV] Restoring volumetric fog state.")
			world_env.environment.volumetric_fog_enabled = _stored_volumetric_state

	if is_instance_valid(camera_vp):
		camera_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	if is_instance_valid(current_player) and current_player.get("system_menu"):
		current_player.get("system_menu").is_stunned = false

	if replace_player_camera:
		_disable_fullscreen_mode()

	current_player = null


## Spawns a fullscreen HUD overlay and hides the main 3D player camera.
func _enable_fullscreen_mode() -> void:
	print("[CCTV] Constructing fullscreen HUD overlay.")
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
			print("[CCTV] Disabling player camera cull mask.")
			var p_cam: Camera3D = cam_controller.get("camera") as Camera3D
			_stored_player_cull_mask = p_cam.cull_mask
			p_cam.cull_mask = 0


## Frees the fullscreen HUD overlay and restores the main player camera cull mask.
func _disable_fullscreen_mode() -> void:
	print("[CCTV] Freeing fullscreen HUD overlay and restoring player camera.")
	if is_instance_valid(_fullscreen_canvas):
		_fullscreen_canvas.queue_free()
		_fullscreen_canvas = null
		_fullscreen_rect = null

	if is_instance_valid(current_player) and current_player.get("camera_controller"):
		var cam_controller: Node = current_player.get("camera_controller")
		if is_instance_valid(cam_controller) and is_instance_valid(cam_controller.get("camera")):
			print("[CCTV] Restoring player camera cull mask.")
			var p_cam: Camera3D = cam_controller.get("camera") as Camera3D
			p_cam.cull_mask = _stored_player_cull_mask


## Snaps the security camera to the target index in [member camera_locations].
## [param index] Location marker index to align to.
func _set_camera(index: int) -> void:
	if index < 0 or index >= camera_locations.size():
		return

	var target_loc: Node3D = camera_locations[index]
	if not is_instance_valid(target_loc):
		return

	print("[CCTV] Setting active camera location to index: ", index)
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


## Increments through connected camera markers in sequential order.
func _cycle_camera() -> void:
	if camera_locations.is_empty():
		return

	print("[CCTV] Cycling camera feed index.")
	var next_idx: int = (active_cam_idx + 1) % camera_locations.size()
	_set_camera(next_idx)


## Rotates camera yaw and pitch axes based on directional axis inputs.
## [param delta] Frame duration in seconds.
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


## Interpolates camera field of view toward [member target_fov].
## [param delta] Frame duration in seconds.
func _handle_zoom(delta: float) -> void:
	target_fov = clampf(target_fov, min_fov, max_fov)
	cctv_camera.fov = lerpf(cctv_camera.fov, target_fov, 10.0 * delta)
