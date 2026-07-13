extends Control

## The file path to the level scene that needs to be loaded in the background.
@export_file("*.tscn") var level_scene_path: String = "res://levels/testbed.scn"

## A custom resource containing a list of materials to precompile to prevent in-game hitches.
@export var baked_shader_cache: ShaderCache

## An array used to retrieve the background loading progress percentage from the ResourceLoader.
var _progress_array: Array[float] = [0.0]

## Tracks the current state of the threaded load operation (e.g., in progress, loaded, failed).
var _status: ResourceLoader.ThreadLoadStatus = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

## A flag indicating whether the loading screen has transitioned to the shader precompilation phase.
var _is_precompiling: bool = false

## The current index in the shader cache array being processed during precompilation.
var _current_compile_index: int = 0

## The maximum number of milliseconds allowed per frame for shader compilation to maintain smooth UI.
var _max_compile_time_ms: int = 8

## A hidden 3D node used to spawn temporary 3D meshes for forcing shader compilation.
var _dummy_parent_3d: Node3D

## A hidden 2D node used to spawn temporary CanvasItems for forcing 2D shader compilation.
var _dummy_parent_2d: Control

## The visual indicator showing loading progress to the player.
@onready var animation: AnimatedSprite2D = $AnimatedSprite2D

## The progress bar UI element that fills up as the background loading completes.
@onready var progress_bar: ProgressBar = $ProgressBar

## The audio player responsible for playing background music or sounds during the loading screen.
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer


func _ready() -> void:
	print("LoadingScreen: Initializing load screen. Requesting level: ", level_scene_path)
	animation.play("default")
	audio_player.play()

	var error: Error = ResourceLoader.load_threaded_request(level_scene_path, "", true)

	if error != OK:
		push_error("LoadingScreen: Background load error: " + error_string(error))
		return

	print("LoadingScreen: Threaded load requested successfully. Monitoring progress...")
	_status = ResourceLoader.load_threaded_get_status(level_scene_path)


func _process(_delta: float) -> void:
	if _is_precompiling:
		_process_shader_compilation()
		return

	_status = ResourceLoader.load_threaded_get_status(level_scene_path, _progress_array)

	match _status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			progress_bar.value = _progress_array[0] * 100.0

		ResourceLoader.THREAD_LOAD_LOADED:
			print("LoadingScreen: Level loaded in background. Starting shader precompilation.")
			_is_precompiling = true
			_setup_precompilation()

		ResourceLoader.THREAD_LOAD_FAILED:
			set_process(false)
			audio_player.stop()
			push_error("LoadingScreen: Loading failed. Check the file path or assets.")

		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			set_process(false)
			audio_player.stop()
			push_error("LoadingScreen: The resource path provided is invalid.")


func _setup_precompilation() -> void:
	print("LoadingScreen: Setting up temporary instances to force shader compilation.")

	if not baked_shader_cache or baked_shader_cache.materials.is_empty():
		print("LoadingScreen: No shader cache found or cache is empty. Skipping precompile.")
		_change_to_loaded_level()
		return

	_dummy_parent_3d = Node3D.new()
	_dummy_parent_3d.position = Vector3(0.0, -1000.0, 0.0)
	add_child(_dummy_parent_3d)

	_dummy_parent_2d = Control.new()
	_dummy_parent_2d.position = Vector2(-10000.0, -10000.0)
	add_child(_dummy_parent_2d)

	_current_compile_index = 0


func _process_shader_compilation() -> void:
	print("LoadingScreen: Processing shader compilation chunk...")
	var start_time: int = Time.get_ticks_msec()
	
	while _current_compile_index < baked_shader_cache.materials.size():
		var mat: Material = baked_shader_cache.materials[_current_compile_index]
		_create_dummy_element(mat)
		_current_compile_index += 1
		
		if (Time.get_ticks_msec() - start_time) >= _max_compile_time_ms:
			return 
			
	print("LoadingScreen: Precompilation finished. Cleaning up dummies.")
	_dummy_parent_3d.queue_free()
	_dummy_parent_2d.queue_free()
	_change_to_loaded_level()


func _create_dummy_element(mat: Material) -> void:
	print("LoadingScreen: Instantiating dummy for material: ", mat.resource_path)
	var is_2d: bool = false

	if mat is CanvasItemMaterial:
		is_2d = true
	elif mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = mat as ShaderMaterial
		if shader_mat.shader and shader_mat.shader.get_mode() == Shader.MODE_CANVAS_ITEM:
			is_2d = true

	if is_2d:
		var rect: ColorRect = ColorRect.new()
		rect.material = mat
		_dummy_parent_2d.add_child(rect)
	else:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var quad: QuadMesh = QuadMesh.new()
		quad.material = mat
		mesh_instance.mesh = quad
		_dummy_parent_3d.add_child(mesh_instance)


func _change_to_loaded_level() -> void:
	print("LoadingScreen: Instantiating and switching to the loaded packed scene.")
	set_process(false)
	audio_player.stop()

	var loaded_scene: PackedScene = (
		ResourceLoader.load_threaded_get(level_scene_path) as PackedScene
	)

	if loaded_scene:
		get_tree().change_scene_to_packed(loaded_scene)
