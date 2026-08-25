## Manages fast asynchronous scene streaming, multi-threaded node instantiation,
## and budgeted shader warmup to maintain consistent 60 FPS UI performance.
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

## Tracks loading status returned by [ResourceLoader].
var _status: ResourceLoader.ThreadLoadStatus = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

## Array receiving percentage progress from [method ResourceLoader.load_threaded_get_status].
var _progress_array: Array[float] = [0.0]

## Holds the instantiated root node of the level created on a background worker thread.
var _instantiated_scene: Node = null

## Task ID for the background scene instantiation task.
var _instantiation_task_id: int = -1

## Flag indicating whether background resource loading has completed.
var _is_resource_loaded: bool = false

## Flag indicating whether shader warmup has completed.
var _is_warmup_complete: bool = false

## Tracks the current material index being processed during warmup.
var _compile_index: int = 0

## Temporary off-screen viewport container used to force pipeline compilation.
var _warmup_viewport: SubViewport

## Node container holding temporary meshes inside the warmup viewport.
var _warmup_container: Node3D

## Maximum milliseconds allowed per frame for material warmup to preserve 60 FPS.
const MAX_WARMUP_TIME_MS: int = 12


## Initializes background scene loading, animations, and sound playback.
func _ready() -> void:
	print("LoadingScreen: Requesting threaded load without sub-threads to prevent deadlocks.")
	animation.play("default")
	audio_player.play()

	# Keep use_sub_threads set to false to avoid WorkerThreadPool resource deadlocks
	var error: Error = ResourceLoader.load_threaded_request(level_scene_path, "", false)
	if error != OK:
		push_error("LoadingScreen: Request failed: " + error_string(error))
		set_process(false)
		return

	_status = ResourceLoader.load_threaded_get_status(level_scene_path)


## Monitors loading progress, kicks off threaded instantiation, and awaits completion.
func _process(_delta: float) -> void:
	if not _is_resource_loaded:
		_status = ResourceLoader.load_threaded_get_status(level_scene_path, _progress_array)

		match _status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				# 0% - 60%: Background file loading
				progress_bar.value = _progress_array[0] * 60.0
				# Prints progress percentage to verify whether disk I/O is advancing
				print("LoadingScreen: In progress -> %.2f%%" % (_progress_array[0] * 100.0))

			ResourceLoader.THREAD_LOAD_LOADED:
				_is_resource_loaded = true
				print(
					"LoadingScreen: Disk load done. Starting threaded instantiation & shader warmup."
				)
				_start_background_instantiation()
				_start_shader_warmup()

			ResourceLoader.THREAD_LOAD_FAILED:
				set_process(false)
				audio_player.stop()
				push_error("LoadingScreen: Failed to load scene assets from disk.")

			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				set_process(false)
				audio_player.stop()
				push_error("LoadingScreen: Invalid scene path.")

	elif _is_warmup_complete and _instantiated_scene != null:
		_finalize_scene_transition()


## Spawns the scene tree instantiation onto a background worker thread.
func _start_background_instantiation() -> void:
	var loaded_scene: PackedScene = (
		ResourceLoader.load_threaded_get(level_scene_path) as PackedScene
	)
	if not loaded_scene:
		push_error("LoadingScreen: PackedScene retrieval returned null.")
		return

	_instantiation_task_id = WorkerThreadPool.add_task(
		func() -> void:
			var instance: Node = loaded_scene.instantiate()
			_instantiated_scene = instance
	)


## Sets up the hidden warmup viewport and iterates through cached materials.
func _start_shader_warmup() -> void:
	if not baked_shader_cache or baked_shader_cache.materials.is_empty():
		_is_warmup_complete = true
		return

	_warmup_viewport = SubViewport.new()
	_warmup_viewport.size = Vector2i(16, 16)
	_warmup_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 2.0)
	_warmup_viewport.add_child(camera)

	_warmup_container = Node3D.new()
	_warmup_viewport.add_child(_warmup_container)
	add_child(_warmup_viewport)

	_compile_materials_budgeted()


## Processes materials across multiple frames reusing a single mesh/rect instance.
func _compile_materials_budgeted() -> void:
	var total_mats: int = baked_shader_cache.materials.size()
	var quad_3d: MeshInstance3D = MeshInstance3D.new()
	quad_3d.mesh = QuadMesh.new()
	_warmup_container.add_child(quad_3d)

	while _compile_index < total_mats:
		var start_time: int = Time.get_ticks_msec()

		while _compile_index < total_mats:
			var mat: Material = baked_shader_cache.materials[_compile_index]
			if mat:
				quad_3d.material_override = mat
			_compile_index += 1

			var warmup_percent: float = float(_compile_index) / float(total_mats)
			progress_bar.value = 60.0 + (warmup_percent * 35.0)

			if (Time.get_ticks_msec() - start_time) >= MAX_WARMUP_TIME_MS:
				await get_tree().process_frame
				break

	_warmup_viewport.queue_free()
	_is_warmup_complete = true


## Generates a lightweight visual node mapped to the off-screen camera.
## [param mat] The material to warm up in the render pipeline.
func _create_warmup_node(mat: Material) -> void:
	if not mat:
		return

	# Skip uncompiled ShaderMaterials with broken or empty shader references
	if mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = mat as ShaderMaterial
		if not shader_mat.shader:
			return

	var is_2d: bool = (
		mat is CanvasItemMaterial
		or (
			mat is ShaderMaterial
			and (mat as ShaderMaterial).shader.get_mode() == Shader.MODE_CANVAS_ITEM
		)
	)

	if is_2d:
		var rect: ColorRect = ColorRect.new()
		rect.material = mat
		rect.size = Vector2(8.0, 8.0)
		_warmup_container.add_child(rect)
	else:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(0.2, 0.2)
		mesh_instance.material_override = mat
		mesh_instance.mesh = quad
		_warmup_container.add_child(mesh_instance)


## Transitions the tree to the pre-instantiated level.
func _finalize_scene_transition() -> void:
	print("LoadingScreen: Attaching pre-instantiated scene to root.")
	set_process(false)
	progress_bar.value = 100.0
	audio_player.stop()

	if _instantiation_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_instantiation_task_id)

	var root: Window = get_tree().root
	var current_scene: Node = get_tree().current_scene

	root.add_child(_instantiated_scene)
	get_tree().current_scene = _instantiated_scene

	if current_scene:
		current_scene.queue_free()
