extends Node3D

@export var video_stream: VideoStream
@export var auto_play: bool = true

@onready var video_player: VideoStreamPlayer = $VideoViewport/Player
@onready var viewport: SubViewport = $VideoViewport
@onready var monitor_mesh: MeshInstance3D = $MonitorMesh
@onready var visibility_notifier: VisibleOnScreenNotifier3D = $VisibilityNotifier


func _ready() -> void:
	if video_stream:
		video_player.stream = video_stream

	# Enable looping natively on the VideoStreamPlayer
	video_player.loop = true

	_setup_screen_material()

	if auto_play:
		play_video()


func _setup_screen_material() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	var viewport_texture: ViewportTexture = viewport.get_texture()

	material.albedo_texture = viewport_texture
	material.emission_enabled = true
	material.emission_texture = viewport_texture
	material.emission_energy_multiplier = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	monitor_mesh.set_surface_override_material(0, material)


func play_video() -> void:
	video_player.play()
	# Force the viewport to update immediately to prevent the black screen bug
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func stop_video() -> void:
	video_player.stop()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


# --- Signal Connections from VisibleOnScreenNotifier3D ---


func _on_visibility_notifier_screen_entered() -> void:
	video_player.paused = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _on_visibility_notifier_screen_exited() -> void:
	video_player.paused = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
