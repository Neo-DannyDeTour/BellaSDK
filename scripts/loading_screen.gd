extends Control

# Change this to the exact path of your heavy level scene
@export_file("*.tscn") var level_scene_path: String = "res://scenes/levels/testbed.scn"

var _progress_array: Array[float] = [0.0]
var _status: ResourceLoader.ThreadLoadStatus = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

@onready var progress_bar: ProgressBar = $ProgressBar

func _ready() -> void:
	# Clean up any leftover load requests for this path
	_status = ResourceLoader.load_threaded_get_status(level_scene_path)
	
	# Start loading the level in the background using Godot's worker threads
	var error: Error = ResourceLoader.load_threaded_request(level_scene_path, "", false)
	if error != OK:
		push_error("Background load error: " + error_string(error))

func _process(_delta: float) -> void:
	# Query the status of the background loading thread
	_status = ResourceLoader.load_threaded_get_status(level_scene_path, _progress_array)
	
	match _status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# Update the visual bar. The progress is stored as a float from 0.0 to 1.0
			progress_bar.value = _progress_array[0] * 100.0
			
		ResourceLoader.THREAD_LOAD_LOADED:
			# The level is completely loaded into memory. Prevent further processing.
			set_process(false)
			_change_to_loaded_level()
			
		ResourceLoader.THREAD_LOAD_FAILED:
			set_process(false)
			push_error("Loading failed. Check if the file path is correct or if assets are corrupted.")
			
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			set_process(false)
			push_error("The resource path provided is invalid.")

func _change_to_loaded_level() -> void:
	# Retrieve the pre-loaded scene resource instantly from memory
	var loaded_scene: PackedScene = ResourceLoader.load_threaded_get(level_scene_path) as PackedScene
	
	if loaded_scene:
		get_tree().change_scene_to_packed(loaded_scene)
