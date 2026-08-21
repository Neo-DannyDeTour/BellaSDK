## Spatially renders and manages an in-game video screen.
##
## Integrates a [SubViewport] and [VideoStreamPlayer] onto a 3D mesh surface.
## It handles performance by pausing playback when the screen is out of camera
## view or outside the maximum defined interaction distance.
class_name DannyCastScreen
extends Node3D

## The raw video asset to play on the mesh surface.
@export var video_stream: VideoStream

## Dictates if the stream should automatically begin playing when the node loads.
@export var auto_play: bool = true

## The maximum radial distance the player camera can be before the video pauses.
@export var max_view_distance: float = 10.0

## The 2D player rendering the stream internally.
@onready var video_player: VideoStreamPlayer = $VideoViewport/Player

## The viewport acting as a texture buffer for the 3D surface.
@onready var viewport: SubViewport = $VideoViewport

## The physical geometry the video texture is drawn onto.
@onready var monitor_mesh: MeshInstance3D = $MonitorMesh

## The volumetric box detecting if the screen is within the camera's frustum.
@onready var visibility_notifier: VisibleOnScreenNotifier3D = $VisibilityNotifier

## True if the screen is currently within the active camera frustum.
var _is_visible_on_screen: bool = true

## Tracks the logical playback intent, independent of frustum pausing.
var _is_intended_to_play: bool = false

## Cached Camera3D reference to avoid expensive [method Viewport.get_camera_3d] calls every frame.
var _cached_camera: Camera3D = null


## Prepares the 3D texture mapping and hooks up visibility optimization logic.
func _ready() -> void:
	# Connecting signals in code ensures they are always active and prevents editor errors.
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

	if auto_play:
		play_video()


## Interrogates distances to the player camera if currently playing and visible.
## [param _delta] Frame execution delta.
func _physics_process(_delta: float) -> void:
	# Only perform the distance check if the video is technically on screen
	# and is supposed to be playing. This saves CPU cycles.
	if _is_intended_to_play and _is_visible_on_screen:
		_check_distance_to_camera()


## Unpauses the video and resumes viewport rendering.
func play_video() -> void:
	print("VideoCast: play_video() called.")
	_is_intended_to_play = true
	_evaluate_playback_state()


## Stops the video execution entirely.
func stop_video() -> void:
	print("VideoCast: stop_video() called.")
	_is_intended_to_play = false
	_evaluate_playback_state()


## Maps the output of the internal [SubViewport] to the [MeshInstance3D] material override.
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


## Halts playback if the player retreats beyond the defined radius threshold.
func _check_distance_to_camera() -> void:
	var camera: Camera3D = _get_camera()
	if not camera:
		return

	# distance_squared_to is heavily optimized compared to distance_to
	var dist_squared: float = global_position.distance_squared_to(camera.global_position)
	var max_dist_squared: float = max_view_distance * max_view_distance

	if dist_squared <= max_dist_squared:
		if video_player.paused:
			print("VideoCast: Player in range. Resuming video.")
			video_player.paused = false
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		if not video_player.paused:
			print("VideoCast: Player out of range. Pausing video.")
			video_player.paused = true
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Resolves all pausing constraints to determine if the raw stream should actively push frames.
func _evaluate_playback_state() -> void:
	print("VideoCast: _evaluate_playback_state() called.")
	if _is_intended_to_play and _is_visible_on_screen:
		if not video_player.is_playing():
			print("VideoCast: Stream starting.")
			video_player.play()

		# Trigger an immediate distance check instead of blindly pausing.
		# This prevents the black screen lockup by allowing the viewport
		# to update if the player is already within range.
		_check_distance_to_camera()
	else:
		if not video_player.paused:
			print("VideoCast: Conditions not met. Pausing video.")
			video_player.paused = true

		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Fired automatically when the screen geometry enters camera frustum.
func _on_visibility_notifier_screen_entered() -> void:
	print("VideoCast: _on_visibility_notifier_screen_entered() called.")
	_is_visible_on_screen = true
	_evaluate_playback_state()


## Fired automatically when the screen geometry exits camera frustum.
func _on_visibility_notifier_screen_exited() -> void:
	print("VideoCast: _on_visibility_notifier_screen_exited() called.")
	_is_visible_on_screen = false
	_evaluate_playback_state()


## Returns a cached reference to the engine's active [Camera3D] node.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
	return _cached_camera
