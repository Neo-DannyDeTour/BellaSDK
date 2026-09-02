## Manages asynchronous scene loading, background resource streaming,
## and shader precompilation to maintain smooth 60 FPS transitions.
class_name LoadingScreen
extends Control

## The file path to the level scene that needs to be loaded in the background.
@export_file("*.tscn", "*.scn") var level_scene_path: String = "res://levels/testbed.scn"

## A custom resource containing a list of materials to precompile.
@export var baked_shader_cache: ShaderCache

## The visual indicator showing loading progress to the player.
@onready var animation: AnimatedSprite2D = $AnimatedSprite2D

## The progress bar UI element that fills up as loading completes.
@onready var progress_bar: ProgressBar = $ProgressBar

## The audio player responsible for loading screen background audio.
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer

## Maximum milliseconds budgeted per frame for material warmup.
const MAX_WARMUP_TIME_MS: int = 12

## Array receiving percentage progress from [ResourceLoader].
var _progress_array: Array[float] = [0.0]

## Tracks loading status returned by [ResourceLoader].
var _status: ResourceLoader.ThreadLoadStatus = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

## Flag indicating whether background disk streaming has finished.
var _is_resource_loaded: bool = false

## Flag indicating whether shader warmup has completed.
var _is_warmup_complete: bool = false

## Tracks the current material index being processed during warmup.
var _compile_index: int = 0

## Temporary off-screen viewport container used to force pipeline compilation.
var _warmup_viewport: SubViewport

## Node container holding temporary 3D meshes inside the warmup viewport.
var _warmup_container_3d: Node3D

## Node container holding temporary 2D elements inside the warmup viewport.
var _warmup_container_2d: Control


## Initializes background scene loading, animations, and sound playback.
func _ready() -> void:
	print("LoadingScreen: Starting background load for: %s" % level_scene_path)
	animation.play("default")
	audio_player.play()

	# Enable sub-threads for multi-threaded asset streaming
	var error: Error = ResourceLoader.load_threaded_request(level_scene_path, "", true)
	if error != OK:
		push_error("LoadingScreen: Request failed: " + error_string(error))
		_cleanup_warmup_viewport()
		set_process(false)
		return

	_status = ResourceLoader.load_threaded_get_status(level_scene_path)


## Cleans up allocated warmup resources when the node is removed from the tree.
func _exit_tree() -> void:
	_cleanup_warmup_viewport()


## Monitors loading progress and coordinates the transition pipeline.
##
## [param _delta] Frame delta time in seconds.
func _process(_delta: float) -> void:
	if not _is_resource_loaded:
		_status = ResourceLoader.load_threaded_get_status(level_scene_path, _progress_array)

		match _status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				# 0% - 70%: Background disk streaming
				progress_bar.value = _progress_array[0] * 70.0

			ResourceLoader.THREAD_LOAD_LOADED:
				_is_resource_loaded = true
				print("LoadingScreen: Disk streaming finished. Starting warmup.")
				_start_shader_warmup()

			ResourceLoader.THREAD_LOAD_FAILED:
				set_process(false)
				audio_player.stop()
				_cleanup_warmup_viewport()
				push_error("LoadingScreen: Failed to load scene assets from disk.")

			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				set_process(false)
				audio_player.stop()
				_cleanup_warmup_viewport()
				push_error("LoadingScreen: Invalid scene path.")

	elif _is_warmup_complete:
		_finalize_scene_transition()


## Sets up the hidden 16x16 warmup viewport and begins pipeline compilation.
func _start_shader_warmup() -> void:
	if not baked_shader_cache or baked_shader_cache.materials.is_empty():
		print("LoadingScreen: No shader cache found. Skipping warmup phase.")
		_is_warmup_complete = true
		return

	_warmup_viewport = SubViewport.new()
	_warmup_viewport.size = Vector2i(16, 16)
	_warmup_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_warmup_viewport.transparent_bg = true

	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 2.0)
	_warmup_viewport.add_child(camera)

	_warmup_container_3d = Node3D.new()
	_warmup_viewport.add_child(_warmup_container_3d)

	_warmup_container_2d = Control.new()
	_warmup_viewport.add_child(_warmup_container_2d)

	add_child(_warmup_viewport)
	_compile_materials_budgeted()


## Processes materials across frames within [constant MAX_WARMUP_TIME_MS].
func _compile_materials_budgeted() -> void:
	var total_mats: int = baked_shader_cache.materials.size()

	while _compile_index < total_mats:
		var start_time: int = Time.get_ticks_msec()

		while _compile_index < total_mats:
			var mat: Material = baked_shader_cache.materials[_compile_index]
			if is_instance_valid(mat):
				_create_warmup_node(mat)
			_compile_index += 1

			var warmup_ratio: float = float(_compile_index) / float(total_mats)
			progress_bar.value = 70.0 + (warmup_ratio * 30.0)

			if (Time.get_ticks_msec() - start_time) >= MAX_WARMUP_TIME_MS:
				await get_tree().process_frame
				break

	# Await an extra frame so the GPU processes all added draw commands
	await get_tree().process_frame

	print("LoadingScreen: Shader warmup completed. Freeing warmup viewport.")
	_cleanup_warmup_viewport()
	_is_warmup_complete = true


## Instantiates the appropriate 2D or 3D dummy node to force pipeline building.
##
## [param mat] The target material to compile.
func _create_warmup_node(mat: Material) -> void:
	var is_2d: bool = mat is CanvasItemMaterial

	if mat is ShaderMaterial:
		var s_mat: ShaderMaterial = mat as ShaderMaterial
		if not is_instance_valid(s_mat.shader):
			return
		if s_mat.shader.get_mode() == Shader.MODE_CANVAS_ITEM:
			is_2d = true

	if is_2d:
		var rect: ColorRect = ColorRect.new()
		rect.material = mat
		rect.size = Vector2(16.0, 16.0)
		_warmup_container_2d.add_child(rect)
	else:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(0.2, 0.2)
		mesh_instance.mesh = quad
		mesh_instance.material_override = mat
		_warmup_container_3d.add_child(mesh_instance)


## Explicitly frees the warmup [SubViewport] and nullifies its references.
func _cleanup_warmup_viewport() -> void:
	if is_instance_valid(_warmup_viewport):
		_warmup_viewport.queue_free()
		_warmup_viewport = null
		_warmup_container_3d = null
		_warmup_container_2d = null


## Transitions the active scene tree to the loaded packed scene.
func _finalize_scene_transition() -> void:
	print("LoadingScreen: Switching to loaded scene.")
	set_process(false)
	progress_bar.value = 100.0
	audio_player.stop()

	var loaded_scene: PackedScene = (
		ResourceLoader.load_threaded_get(level_scene_path) as PackedScene
	)
	if is_instance_valid(loaded_scene):
		get_tree().change_scene_to_packed(loaded_scene)
	else:
		push_error("LoadingScreen: Failed to retrieve valid PackedScene.")
