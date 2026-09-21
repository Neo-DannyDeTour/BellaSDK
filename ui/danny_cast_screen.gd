## Spatially renders and manages an in-game video screen on a 3D mesh surface.
class_name DannyCastScreen
extends Node3D

# --------------------------------------
# EXPORTS
# --------------------------------------

## The raw video stream resource played on the mesh surface.
@export var video_stream: VideoStream

## Dictates if the stream begins playing automatically on load.
@export var auto_play: bool = true

## Maximum radial distance in meters before playback is paused.
@export var max_view_distance: float = 10.0

# --------------------------------------
# INTERNAL NODES & VARIABLES
# --------------------------------------

## The 2D video player rendering the stream internally.
@onready var video_player: VideoStreamPlayer = $VideoViewport/Player

## Viewport acting as an offscreen texture buffer for the 3D surface.
@onready var viewport: SubViewport = $VideoViewport

## Physical mesh geometry displaying the mapped video texture.
@onready var monitor_mesh: MeshInstance3D = $MonitorMesh

## Volumetric bounding notifier detecting camera frustum containment.
@onready var visibility_notifier: VisibleOnScreenNotifier3D = $VisibilityNotifier

## True if the screen is within the active camera frustum.
var _is_visible_on_screen: bool = true

## Logical playback intention independent of frustum culling.
var _is_intended_to_play: bool = false

## Cached camera reference preventing per-frame viewport lookups.
var _cached_camera: Camera3D = null

# --------------------------------------
# ENGINE METHODS
# --------------------------------------


## Prepares texture mapping, configures signals, and initiates auto-play.
func _ready() -> void:
	if not visibility_notifier.screen_entered.is_connected(_on_visibility_notifier_screen_entered):
		print("VideoCast: Connecting screen_entered signal.")
		visibility_notifier.screen_entered.connect(_on_visibility_notifier_screen_entered)

	if not visibility_notifier.screen_exited.is_connected(_on_visibility_notifier_screen_exited):
		print("VideoCast: Connecting screen_exited signal.")
		visibility_notifier.screen_exited.connect(_on_visibility_notifier_screen_exited)

	if video_stream:
		video_player.stream = video_stream

	video_player.loop = true
	_setup_screen_material()

	set_physics_process(false)

	if auto_play:
		play_video()


## Interrogates camera distance while screen is within camera frustum.
func _physics_process(_delta: float) -> void:
	if _is_intended_to_play and _is_visible_on_screen:
		_check_distance_to_camera()


# --------------------------------------
# PLAYBACK CONTROL
# --------------------------------------


## Initiates playback and evaluates current visibility and distance.
func play_video() -> void:
	print("VideoCast: play_video() called.")
	_is_intended_to_play = true
	_evaluate_playback_state()


## Stops video playback and disables viewport rendering.
func stop_video() -> void:
	print("VideoCast: stop_video() called.")
	_is_intended_to_play = false
	_evaluate_playback_state()


## Maps viewport texture directly to the monitor surface material.
func _setup_screen_material() -> void:
	print("VideoCast: _setup_screen_material() called.")
	var material: StandardMaterial3D = StandardMaterial3D.new()
	var viewport_texture: ViewportTexture = viewport.get_texture()

	material.albedo_texture = viewport_texture
	material.emission_enabled = true
	material.emission_texture = viewport_texture
	material.emission_energy_multiplier = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	monitor_mesh.set_surface_override_material(0, material)


## Pauses stream and disables viewport rendering beyond distance limits.
func _check_distance_to_camera() -> void:
	var camera: Camera3D = _get_camera()
	if not is_instance_valid(camera):
		return

	var dist_squared: float = global_position.distance_squared_to(camera.global_position)
	var max_dist_squared: float = max_view_distance * max_view_distance

	if dist_squared <= max_dist_squared:
		if video_player.paused:
			print("VideoCast: Player in range. Resuming video.")
			video_player.paused = false
			viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	else:
		if not video_player.paused:
			print("VideoCast: Player out of range. Pausing video.")
			video_player.paused = true
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Resolves playback parameters based on frustum and range constraints.
func _evaluate_playback_state() -> void:
	print("VideoCast: _evaluate_playback_state() called.")
	var can_run: bool = _is_intended_to_play and _is_visible_on_screen
	set_physics_process(can_run)

	if can_run:
		if not video_player.is_playing():
			print("VideoCast: Stream starting.")
			video_player.play()

		_check_distance_to_camera()
	else:
		if not video_player.paused:
			print("VideoCast: Conditions not met. Pausing video.")
			video_player.paused = true

		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Resumes checking when the mesh enters active camera frustum.
func _on_visibility_notifier_screen_entered() -> void:
	print("VideoCast: _on_visibility_notifier_screen_entered() called.")
	_is_visible_on_screen = true
	_evaluate_playback_state()


## Halts playback checks when the mesh exits active camera frustum.
func _on_visibility_notifier_screen_exited() -> void:
	print("VideoCast: _on_visibility_notifier_screen_exited() called.")
	_is_visible_on_screen = false
	_evaluate_playback_state()


## Returns cached active [Camera3D] reference from viewport.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		var vp: Viewport = get_viewport()
		_cached_camera = vp.get_camera_3d() if vp else null
	return _cached_camera
