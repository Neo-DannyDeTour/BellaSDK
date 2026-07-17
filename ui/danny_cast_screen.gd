extends Node3D

@export var video_stream: VideoStream
@export var auto_play: bool = true
@export var max_view_distance: float = 10.0

@onready var video_player: VideoStreamPlayer = $VideoViewport/Player
@onready var viewport: SubViewport = $VideoViewport
@onready var monitor_mesh: MeshInstance3D = $MonitorMesh
@onready var visibility_notifier: VisibleOnScreenNotifier3D = $VisibilityNotifier

# Optimistic default: assumes the screen is visible to guarantee the first frame renders.
# The visibility notifier will instantly correct this to false if the player is looking away.
var _is_visible_on_screen: bool = true
var _is_intended_to_play: bool = false


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


func play_video() -> void:
	print("VideoCast: play_video() called.")
	_is_intended_to_play = true
	_evaluate_playback_state()


func stop_video() -> void:
	print("VideoCast: stop_video() called.")
	_is_intended_to_play = false
	_evaluate_playback_state()


func _physics_process(_delta: float) -> void:
	# Only perform the distance check if the video is technically on screen
	# and is supposed to be playing. This saves CPU cycles.
	if _is_intended_to_play and _is_visible_on_screen:
		_check_distance_to_camera()


func _check_distance_to_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
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


func _on_visibility_notifier_screen_entered() -> void:
	print("VideoCast: _on_visibility_notifier_screen_entered() called.")
	_is_visible_on_screen = true
	_evaluate_playback_state()


func _on_visibility_notifier_screen_exited() -> void:
	print("VideoCast: _on_visibility_notifier_screen_exited() called.")
	_is_visible_on_screen = false
	_evaluate_playback_state()
