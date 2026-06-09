extends Control

@export_file("*.tscn") var level_scene_path: String = "res://shared/testbed.scn"

var _progress_array: Array[float] = [0.0]
var _status: ResourceLoader.ThreadLoadStatus = \
	ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

@onready var animation: AnimatedSprite2D = $AnimatedSprite2D
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer


func _ready() -> void:
	print("Initializing load screen. Requesting level: ", level_scene_path)
	animation.play("default")
	audio_player.play()
	
	# 1. Request the load FIRST. 
	# 2. Pass 'true' to use_sub_threads for parallel dependency loading.
	var error: Error = ResourceLoader.load_threaded_request(
		level_scene_path, 
		"", 
		true
	)
	
	if error != OK:
		push_error("Background load error: " + error_string(error))
		return
		
	print("Threaded load requested successfully. Monitoring progress...")
	_status = ResourceLoader.load_threaded_get_status(level_scene_path)


func _process(_delta: float) -> void:
	_status = ResourceLoader.load_threaded_get_status(
		level_scene_path, 
		_progress_array
	)
	
	match _status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			progress_bar.value = _progress_array[0] * 100.0
			
		ResourceLoader.THREAD_LOAD_LOADED:
			set_process(false)
			audio_player.stop()
			print("Level loading complete. Proceeding to change scene.")
			_change_to_loaded_level()
			
		ResourceLoader.THREAD_LOAD_FAILED:
			set_process(false)
			audio_player.stop()
			push_error("Loading failed. Check the file path or assets.")
			
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			set_process(false)
			audio_player.stop()
			push_error("The resource path provided is invalid.")


func _change_to_loaded_level() -> void:
	print("Instantiating and switching to the loaded packed scene.")
	var loaded_scene: PackedScene = \
		ResourceLoader.load_threaded_get(level_scene_path) as PackedScene
	
	if loaded_scene:
		get_tree().change_scene_to_packed(loaded_scene)
