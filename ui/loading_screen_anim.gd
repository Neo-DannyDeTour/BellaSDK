extends Control

@export_file("*.tscn") var level_scene_path: String = "res://shared/testbed.scn"
@export var baked_shader_cache: ShaderCache

# Assign all unique materials used in your level to this array in the Inspector.
@export var materials_to_precompile: Array[Material] = []

var _progress_array: Array[float] = [0.0]
var _status: ResourceLoader.ThreadLoadStatus = \
	ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
var _is_precompiling: bool = false

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
	if _is_precompiling:
		return
		
	_status = ResourceLoader.load_threaded_get_status(
		level_scene_path, 
		_progress_array
	)
	
	match _status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			progress_bar.value = _progress_array[0] * 100.0
			
		ResourceLoader.THREAD_LOAD_LOADED:
			print("Level loaded in background. Starting shader precompilation.")
			_is_precompiling = true
			_precompile_shaders_and_switch()
			
		ResourceLoader.THREAD_LOAD_FAILED:
			set_process(false)
			audio_player.stop()
			push_error("Loading failed. Check the file path or assets.")
			
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			set_process(false)
			audio_player.stop()
			push_error("The resource path provided is invalid.")


func _precompile_shaders_and_switch() -> void:
	print("Creating temporary instances to force shader compilation.")
	
	if not baked_shader_cache or baked_shader_cache.materials.is_empty():
		print("No shader cache found or cache is empty. Skipping precompile.")
		_change_to_loaded_level()
		return
		
	var dummy_parent: Node3D = Node3D.new()
	dummy_parent.position = Vector3(0.0, -1000.0, 0.0)
	add_child(dummy_parent)
	
	# CHANGED: Renamed 'material' to 'shader_mat' to prevent shadowing CanvasItem.material
	for shader_mat: Material in baked_shader_cache.materials:
		_create_dummy_mesh(shader_mat, dummy_parent)
		
	print("Waiting for renderer to compile materials...")
	
	for i: int in range(3):
		await get_tree().process_frame
		
	dummy_parent.queue_free()
	print("Precompilation finished. Proceeding to change scene.")
	_change_to_loaded_level()


func _create_dummy_mesh(mat: Material, parent: Node3D) -> void:
	print("Instantiating dummy mesh for material: ", mat.resource_path)
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.material = mat
	mesh_instance.mesh = quad
	parent.add_child(mesh_instance)


func _change_to_loaded_level() -> void:
	print("Instantiating and switching to the loaded packed scene.")
	set_process(false)
	audio_player.stop()
	
	var loaded_scene: PackedScene = \
		ResourceLoader.load_threaded_get(level_scene_path) as PackedScene
	
	if loaded_scene:
		get_tree().change_scene_to_packed(loaded_scene)
