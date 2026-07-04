extends Control

@export_file("*.tscn") var level_scene_path: String = "res://levels/testbed.scn"
@export var baked_shader_cache: ShaderCache

var _progress_array: Array[float] = [0.0]
var _status: ResourceLoader.ThreadLoadStatus = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
var _is_precompiling: bool = false
var _current_compile_index: int = 0

var _dummy_parent_3d: Node3D
var _dummy_parent_2d: Control

@onready var animation: AnimatedSprite2D = $AnimatedSprite2D
@onready var progress_bar: ProgressBar = $ProgressBar
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
	if _current_compile_index < baked_shader_cache.materials.size():
		var mat: Material = baked_shader_cache.materials[_current_compile_index]
		_create_dummy_element(mat)
		_current_compile_index += 1
	else:
		print("LoadingScreen: Precompilation finished. Cleaning up dummies.")
		_dummy_parent_3d.queue_free()
		_dummy_parent_2d.queue_free()
		_change_to_loaded_level()


func _create_dummy_element(mat: Material) -> void:
	var is_2d: bool = false

	if mat is CanvasItemMaterial:
		is_2d = true
	elif mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = mat as ShaderMaterial
		if shader_mat.shader and shader_mat.shader.get_mode() == Shader.MODE_CANVAS_ITEM:
			is_2d = true

	if is_2d:
		print("LoadingScreen: Instantiating 2D CanvasItem dummy for material: ", mat.resource_path)
		var rect: ColorRect = ColorRect.new()
		rect.material = mat
		_dummy_parent_2d.add_child(rect)
	else:
		print("LoadingScreen: Instantiating 3D Spatial dummy for material: ", mat.resource_path)
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
