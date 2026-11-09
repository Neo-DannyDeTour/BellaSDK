## Manages async scene loading, dynamic SpriteFrames loading, adaptive shader warmup, and SDFGI.
class_name LoadingScreen
extends CanvasLayer

## Maximum number of materials compiled concurrently in a single frame.
const WARMUP_POOL_SIZE: int = 4

## Frame delta threshold in seconds above which warmup throttles to 1 slot.
const WARMUP_FRAME_BUDGET_SEC: float = 0.018

## Number of idle frames to wait for camera transform settling before SDFGI.
const SETTLING_FRAMES: int = 4

## Maximum visual progress bar fill rate per second to avoid jarring jumps.
const FILL_RATE_MAX: float = 75.0

## Smoothing speed multiplier for visual progress interpolation.
const SMOOTHING_SPEED: float = 6.0

## Minimum fill rate per second when approaching target progress.
const MIN_FILL_RATE: float = 12.0

## Animation playback framerate locked strictly to audio.
const ANIM_FPS: float = 24.0

## Total frame count per animation sequence (120 frames at 24 FPS = 5.0 seconds).
const TOTAL_ANIM_FRAMES: int = 120

## Animation name for the Bella Wrench loading sequence.
const ANIM_BELLA_WRENCH: StringName = &"bella_wrench"

## Animation name for the Priestess Two-Face loading sequence.
const ANIM_PRIESTESS_TWOFACE: StringName = &"priestess_twoface"

## Method name invoked on the player entity to activate its gameplay camera.
const METHOD_ACTIVATE_CAMERA: StringName = &"activate_gameplay_camera"

## Property name for the player's locomotion component reference.
const PROP_LOCOMOTION: StringName = &"locomotion_component"

## Property name for the player's camera controller reference.
const PROP_CAMERA_CONTROLLER: StringName = &"camera_controller"

## Tracks whether an active loading screen transition is currently in flight.
static var is_transition_active: bool = false

## The file path to the level scene that needs to be loaded in the background.
@export_file("*.tscn", "*.scn") var level_scene_path: String = ""

## File path to the bella wrench sprite frames resource.
@export_file("*.tres") var bella_wrench_frames_path: String = "res://ui/bella_wrench_frames.tres"

## File path to the priestess two-face sprite frames resource.
@export_file("*.tres")
var priestess_twoface_frames_path: String = "res://ui/priestess_twoface_frames.tres"

## A custom resource containing a list of materials to precompile.
@export var baked_shader_cache: ShaderCache

## Optional audio stream matching the first animation (bella_wrench).
@export var audio_bella_wrench: AudioStream

## Optional audio stream matching the second animation (priestess_twoface).
@export var audio_priestess_twoface: AudioStream

## Array receiving percentage progress from [ResourceLoader].
var _progress_array: Array[float] = [0.0]

## Tracks loading status returned by [ResourceLoader].
var _status: ResourceLoader.ThreadLoadStatus = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

## Target progress percentage budgeted across loading phases (0.0 to 100.0).
var _target_progress: float = 0.0

## File path of the selected animation's SpriteFrames resource.
var _selected_frames_path: String = ""

## Cached name of the randomly chosen animation.
var _selected_anim_name: StringName = &""

## Flag indicating whether the SpriteFrames resource has finished loading.
var _is_frames_loaded: bool = false

## Flag indicating whether background level disk streaming has finished.
var _is_resource_loaded: bool = false

## Flag indicating whether shader warmup has completed.
var _is_warmup_complete: bool = false

## Flag indicating whether the single playback animation cycle has finished.
var _is_animation_finished: bool = false

## Flag preventing duplicate transition execution.
var _is_transitioning_scene: bool = false

## Tracks the current material index being processed during warmup.
var _compile_index: int = 0

## Temporary off-screen viewport container used to force pipeline compilation.
var _warmup_viewport: SubViewport = null

## Node container holding temporary 3D meshes inside the warmup viewport.
var _warmup_container_3d: Node3D = null

## Node container holding temporary 2D elements inside the warmup viewport.
var _warmup_container_2d: Control = null

## Pooled dummy mesh instances arranged in a 2x2 grid for 3D material warmup.
var _warmup_mesh_pool: Array[MeshInstance3D] = []

## Pooled dummy color rects arranged in a 2x2 grid for 2D canvas warmup.
var _warmup_rect_pool: Array[ColorRect] = []

## Reusable quad geometry shared across 3D material warmup steps.
var _warmup_quad_mesh: QuadMesh = null

## Active tween fading out the visual root container at transition end.
var _fade_tween: Tween = null

## The visual indicator container to fade smoothly without breaking root layout.
@onready var visual_root: Control = $VisualRoot

## Full-screen static splash image displayed after animation completion.
@onready var static_splash: TextureRect = $VisualRoot/StaticSplash

## The animated sprite showing random loading sequence loops.
@onready var animation: AnimatedSprite2D = $VisualRoot/CenterContainer/SpriteAnchor/AnimatedSprite2D

## The progress bar UI element that fills up as loading completes.
@onready var progress_bar: ProgressBar = $VisualRoot/CenterContainer/SpriteAnchor/ProgressBar

## The audio player responsible for loading screen background audio.
@onready var audio_player: AudioStreamPlayer = $VisualRoot/AudioStreamPlayer


## Initializes background animation asset loading and transition guards.
func _ready() -> void:
	assert(is_instance_valid(visual_root), "LoadingScreen: visual_root missing.")
	assert(is_instance_valid(static_splash), "LoadingScreen: static_splash missing.")
	assert(is_instance_valid(animation), "LoadingScreen: animation missing.")
	assert(is_instance_valid(progress_bar), "LoadingScreen: progress_bar missing.")
	assert(is_instance_valid(audio_player), "LoadingScreen: audio_player missing.")

	process_mode = Node.PROCESS_MODE_ALWAYS

	if is_transition_active:
		push_error("LoadingScreen: Duplicate transition rejected.")
		queue_free()
		return
	is_transition_active = true

	if level_scene_path.is_empty():
		push_error("LoadingScreen: No level_scene_path assigned!")
		set_process(false)
		return

	_select_random_presentation()

	# Threaded request for the level scene using worker subthreads immediately.
	var level_error: Error = ResourceLoader.load_threaded_request(level_scene_path, "", true)
	if level_error != OK:
		push_error("LoadingScreen: Level request failed: " + error_string(level_error))
		set_process(false)
		return

	# Threaded request for ONLY the selected animation's SpriteFrames resource.
	var frame_error: Error = ResourceLoader.load_threaded_request(_selected_frames_path, "", false)
	if frame_error != OK:
		push_error("LoadingScreen: SpriteFrames request failed: " + error_string(frame_error))
		set_process(false)
		return


## Cleans up allocated warmup resources and tweens when removed from the tree.
func _exit_tree() -> void:
	print("LoadingScreen: Cleaning up resources on tree exit.")
	is_transition_active = false
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
		_fade_tween = null
	_cleanup_warmup_viewport()


## Monitors loading progress for SpriteFrames, levels, and coordinates pipeline.
func _process(delta: float) -> void:
	_update_progress_bar_visual(delta)

	if not _is_frames_loaded:
		var frame_status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			_selected_frames_path
		)
		match frame_status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var loaded_frames: SpriteFrames = (
					ResourceLoader.load_threaded_get(_selected_frames_path) as SpriteFrames
				)
				if is_instance_valid(loaded_frames):
					animation.sprite_frames = loaded_frames
					animation.play(_selected_anim_name)
					animation.pause()
					animation.set_frame_and_progress(0, 0.0)
					_is_frames_loaded = true
					if is_instance_valid(audio_player.stream):
						audio_player.play()
					print("LoadingScreen: SpriteFrames loaded. Audio and animation started synced.")
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				set_process(false)
				push_error("LoadingScreen: Failed loading selected SpriteFrames resource.")
				return
	elif not _is_animation_finished:
		_sync_animation_with_audio()

	if not _is_resource_loaded:
		_status = ResourceLoader.load_threaded_get_status(level_scene_path, _progress_array)

		var has_shader_cache: bool = (
			is_instance_valid(baked_shader_cache) and not baked_shader_cache.materials.is_empty()
		)
		var disk_max: float = 30.0 if has_shader_cache else 40.0

		match _status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_target_progress = clampf(_progress_array[0] * disk_max, 0.0, disk_max)

			ResourceLoader.THREAD_LOAD_LOADED:
				_is_resource_loaded = true
				_target_progress = disk_max
				print("LoadingScreen: Disk streaming finished. Starting warmup.")
				_start_shader_warmup()

			ResourceLoader.THREAD_LOAD_FAILED:
				set_process(false)
				audio_player.stop()
				_cleanup_warmup_viewport()
				push_error("LoadingScreen: Failed loading assets from disk.")

			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				set_process(false)
				audio_player.stop()
				_cleanup_warmup_viewport()
				push_error("LoadingScreen: Invalid scene path provided.")

	elif _is_warmup_complete and _is_animation_finished and not _is_transitioning_scene:
		_is_transitioning_scene = true
		_finalize_scene_transition()


## Selects a random presentation pair and queues its isolated resource path.
func _select_random_presentation() -> void:
	print("LoadingScreen: Selecting random presentation pair.")
	var anim_options: Array[StringName] = [ANIM_BELLA_WRENCH, ANIM_PRIESTESS_TWOFACE]
	_selected_anim_name = anim_options[randi() % anim_options.size()]

	if _selected_anim_name == ANIM_BELLA_WRENCH:
		_selected_frames_path = bella_wrench_frames_path
		if is_instance_valid(audio_bella_wrench):
			audio_player.stream = audio_bella_wrench
	elif _selected_anim_name == ANIM_PRIESTESS_TWOFACE:
		_selected_frames_path = priestess_twoface_frames_path
		if is_instance_valid(audio_priestess_twoface):
			audio_player.stream = audio_priestess_twoface


## Smoothly steps the visual progress bar towards [member _target_progress].
func _update_progress_bar_visual(delta: float) -> void:
	if not is_instance_valid(progress_bar):
		return
	var remaining: float = _target_progress - progress_bar.value
	if remaining > 0.001:
		var speed: float = maxf(remaining * SMOOTHING_SPEED, MIN_FILL_RATE)
		var step: float = minf(speed * delta, FILL_RATE_MAX * delta)
		progress_bar.value = clampf(progress_bar.value + step, 0.0, _target_progress)


## Synchronizes animation frame strictly to hardware audio playback at 24 FPS.
func _sync_animation_with_audio() -> void:
	if not is_instance_valid(animation) or not is_instance_valid(animation.sprite_frames):
		return

	if not audio_player.playing:
		_on_single_animation_cycle_finished()
		return

	var playback_pos: float = (
		audio_player.get_playback_position() + AudioServer.get_time_since_last_mix()
	)
	var target_frame: int = int(playback_pos * ANIM_FPS)

	if target_frame >= TOTAL_ANIM_FRAMES - 1:
		_on_single_animation_cycle_finished()
	else:
		animation.set_frame_and_progress(target_frame, 0.0)


## Halts animation and audio, evicts texture frames, and displays static splash.
func _on_single_animation_cycle_finished() -> void:
	_is_animation_finished = true
	print("LoadingScreen: Single 24 FPS cycle complete. Switching to Godiva splash.")
	if is_instance_valid(audio_player):
		audio_player.stop()
	if is_instance_valid(animation):
		animation.stop()
		animation.visible = false
		animation.sprite_frames = null
	if is_instance_valid(static_splash):
		static_splash.visible = true


## Sets up the isolated warmup viewport and begins pipeline compilation.
func _start_shader_warmup() -> void:
	if not is_instance_valid(baked_shader_cache) or baked_shader_cache.materials.is_empty():
		print("LoadingScreen: No shader cache found. Skipping warmup phase.")
		_target_progress = maxf(_target_progress, 40.0)
		_is_warmup_complete = true
		return

	print("LoadingScreen: Allocating isolated warmup SubViewport.")
	_warmup_viewport = SubViewport.new()
	_warmup_viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	_warmup_viewport.own_world_3d = true
	_warmup_viewport.world_3d = World3D.new()
	_warmup_viewport.size = Vector2i(64, 64)
	_warmup_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_warmup_viewport.transparent_bg = true

	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 2.0)
	camera.cull_mask = 1
	_warmup_viewport.add_child(camera)

	var dir_light: DirectionalLight3D = DirectionalLight3D.new()
	dir_light.shadow_enabled = true
	dir_light.rotation_degrees = Vector3(-45.0, 45.0, 0.0)
	_warmup_viewport.add_child(dir_light)

	var omni_light: OmniLight3D = OmniLight3D.new()
	omni_light.position = Vector3(0.0, 1.0, 1.0)
	omni_light.omni_range = 5.0
	_warmup_viewport.add_child(omni_light)

	_warmup_container_3d = Node3D.new()
	_warmup_viewport.add_child(_warmup_container_3d)

	_warmup_container_2d = Control.new()
	_warmup_viewport.add_child(_warmup_container_2d)

	_setup_warmup_pipeline_nodes()
	add_child(_warmup_viewport)
	_compile_materials_budgeted()


## Prepares a 4-slot 2x2 non-overlapping grid of 3D and 2D nodes for shader warmup.
func _setup_warmup_pipeline_nodes() -> void:
	print("LoadingScreen: Pre-allocating 4-slot pooled nodes for shader warmup.")
	_warmup_quad_mesh = QuadMesh.new()
	_warmup_quad_mesh.size = Vector2(0.2, 0.2)

	_warmup_mesh_pool.clear()
	_warmup_rect_pool.clear()

	var offsets_3d: Array[Vector3] = [
		Vector3(-0.25, 0.25, 0.0),
		Vector3(0.25, 0.25, 0.0),
		Vector3(-0.25, -0.25, 0.0),
		Vector3(0.25, -0.25, 0.0),
	]
	var offsets_2d: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(16.0, 0.0),
		Vector2(0.0, 16.0),
		Vector2(16.0, 16.0),
	]

	for slot_idx: int in range(WARMUP_POOL_SIZE):
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		mesh_inst.mesh = _warmup_quad_mesh
		mesh_inst.layers = 1
		mesh_inst.position = offsets_3d[slot_idx]
		mesh_inst.visible = false
		_warmup_container_3d.add_child(mesh_inst)
		_warmup_mesh_pool.append(mesh_inst)

		var color_rect: ColorRect = ColorRect.new()
		color_rect.size = Vector2(16.0, 16.0)
		color_rect.position = offsets_2d[slot_idx]
		color_rect.visible = false
		_warmup_container_2d.add_child(color_rect)
		_warmup_rect_pool.append(color_rect)


## Processes materials across frames using previous-frame delta throttling.
func _compile_materials_budgeted() -> void:
	print("LoadingScreen: Compiling cached shader pipelines...")
	var total_mats: int = baked_shader_cache.materials.size()

	while _compile_index < total_mats:
		if not is_inside_tree():
			return

		var frame_delta: float = get_process_delta_time()
		var batch_limit: int = WARMUP_POOL_SIZE if frame_delta <= WARMUP_FRAME_BUDGET_SEC else 1
		var used_slots: int = 0

		while _compile_index < total_mats and used_slots < batch_limit:
			var res: Resource = baked_shader_cache.materials[_compile_index]
			if res is Material:
				if _assign_warmup_slot(used_slots, res as Material):
					used_slots += 1
			_compile_index += 1

		for slot_idx: int in range(used_slots, WARMUP_POOL_SIZE):
			_disable_warmup_slot(slot_idx)

		var warmup_ratio: float = float(_compile_index) / float(total_mats)
		_target_progress = 30.0 + (warmup_ratio * 15.0)

		await get_tree().process_frame

	print("LoadingScreen: Shader warmup completed. Freeing warmup viewport.")
	_cleanup_warmup_viewport()
	_target_progress = 45.0
	_is_warmup_complete = true


## Assigns [param mat] to pool [param slot_idx] and returns true if scheduled for draw.
func _assign_warmup_slot(slot_idx: int, mat: Material) -> bool:
	var is_2d: bool = mat is CanvasItemMaterial

	if mat is ShaderMaterial:
		var s_mat: ShaderMaterial = mat as ShaderMaterial
		if not is_instance_valid(s_mat.shader):
			return false
		if s_mat.shader.get_mode() == Shader.MODE_CANVAS_ITEM:
			is_2d = true

	var mesh_inst: MeshInstance3D = _warmup_mesh_pool[slot_idx]
	var color_rect: ColorRect = _warmup_rect_pool[slot_idx]

	if is_2d:
		color_rect.material = mat
		color_rect.visible = true
		mesh_inst.visible = false
	else:
		mesh_inst.material_override = mat
		mesh_inst.visible = true
		color_rect.visible = false

	return true


## Hides both 2D and 3D warmup nodes at [param slot_idx].
func _disable_warmup_slot(slot_idx: int) -> void:
	if slot_idx < _warmup_mesh_pool.size() and is_instance_valid(_warmup_mesh_pool[slot_idx]):
		_warmup_mesh_pool[slot_idx].visible = false
	if slot_idx < _warmup_rect_pool.size() and is_instance_valid(_warmup_rect_pool[slot_idx]):
		_warmup_rect_pool[slot_idx].visible = false


## Explicitly frees the warmup [SubViewport] and nullifies pooled references.
func _cleanup_warmup_viewport() -> void:
	print("LoadingScreen: Cleaning up warmup viewport instances.")
	_warmup_mesh_pool.clear()
	_warmup_rect_pool.clear()
	_warmup_quad_mesh = null
	_warmup_container_3d = null
	_warmup_container_2d = null
	if is_instance_valid(_warmup_viewport):
		_warmup_viewport.queue_free()
		_warmup_viewport = null


## Finalizes scene switch with frame-spaced mounting, PSO sweep, and SDFGI staging.
func _finalize_scene_transition() -> void:
	print("LoadingScreen: Evicting previous levels and mounting new scene.")
	_target_progress = 45.0

	var loaded_scene: PackedScene = (
		ResourceLoader.load_threaded_get(level_scene_path) as PackedScene
	)
	if not is_instance_valid(loaded_scene):
		push_error("LoadingScreen: Failed to retrieve valid PackedScene.")
		return

	var root: Window = get_tree().root
	var scenes_to_evict: Array[Node] = []
	for child: Node in root.get_children():
		if child == self or ProjectSettings.has_setting("autoload/" + child.name):
			continue
		scenes_to_evict.append(child)

	for old_node: Node in scenes_to_evict:
		print("LoadingScreen: Evicting old scene from tree: ", old_node.name)
		old_node.queue_free()

	await get_tree().process_frame
	await get_tree().process_frame
	_target_progress = 50.0

	var new_scene: Node = loaded_scene.instantiate()
	if not is_instance_valid(new_scene):
		push_error("LoadingScreen: Failed to instantiate PackedScene.")
		return
	_target_progress = 58.0

	await get_tree().process_frame

	var world_env: WorldEnvironment = _find_world_environment(new_scene)
	if is_instance_valid(world_env) and is_instance_valid(world_env.environment):
		world_env.environment = world_env.environment.duplicate()

	var player_node: CharacterBody3D = (
		new_scene.find_child("Player", true, false) as CharacterBody3D
	)
	_target_progress = 64.0

	await get_tree().process_frame

	root.add_child(new_scene)
	get_tree().current_scene = new_scene
	_target_progress = 70.0

	var locomotion: PlayerLocomotionComponent = _get_player_locomotion(player_node)
	if is_instance_valid(locomotion):
		locomotion.set_physics_active(false)
	if is_instance_valid(player_node):
		player_node.velocity = Vector3.ZERO

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_target_progress = 78.0

	if is_instance_valid(player_node):
		_snap_player_to_floor(player_node)
		if player_node.has_method(METHOD_ACTIVATE_CAMERA):
			player_node.call(METHOD_ACTIVATE_CAMERA)
	_target_progress = 82.0

	await get_tree().process_frame

	print("LoadingScreen: Synchronizing viewport pipeline with active user video settings.")
	_reapply_active_video_settings()

	for frame_idx: int in range(SETTLING_FRAMES):
		await get_tree().process_frame
	_target_progress = 85.0

	var cam_controller: CameraController = _get_camera_controller(player_node)
	if is_instance_valid(player_node) and is_instance_valid(cam_controller):
		print("LoadingScreen: Sweeping frustum 360 deg to cache pipeline states.")
		var original_rot: float = player_node.rotation.y
		var sweep_angles: Array[float] = [90.0, 180.0, 270.0, 0.0]
		var sweep_step: float = (95.0 - 85.0) / float(sweep_angles.size())
		for sweep_idx: int in range(sweep_angles.size()):
			var angle_deg: float = sweep_angles[sweep_idx]
			player_node.rotation.y = original_rot + deg_to_rad(angle_deg)
			await get_tree().process_frame
			_target_progress = 85.0 + (sweep_step * float(sweep_idx + 1))
		player_node.rotation.y = original_rot
		await get_tree().process_frame
	else:
		_target_progress = 95.0

	_target_progress = 100.0

	while is_instance_valid(progress_bar) and progress_bar.value < 99.5:
		await get_tree().process_frame
	if is_instance_valid(progress_bar):
		progress_bar.value = 100.0

	audio_player.stop()

	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(visual_root, "modulate:a", 0.0, 0.25)
	await _fade_tween.finished

	if is_instance_valid(locomotion):
		locomotion.set_physics_active(true)
		print("LoadingScreen: Re-enabled player locomotion after visual fade.")

	print("LoadingScreen: Transition complete. Freeing loading screen.")
	set_process(false)
	queue_free()


## Applies saved video settings from [GraphicsManager] to the new scene tree synchronously.
func _reapply_active_video_settings() -> void:
	print("LoadingScreen: Committing active user video settings via GraphicsManager.")
	GraphicsManager.set_diorama_mode(false)
	GraphicsManager.commit_gameplay_pipeline()


## Locates [WorldEnvironment] safely while ignoring preview diorama nodes.
func _find_world_environment(target: Node) -> WorldEnvironment:
	print("LoadingScreen: Locating WorldEnvironment in scene hierarchy.")
	if target is WorldEnvironment:
		return target as WorldEnvironment

	var direct_env: WorldEnvironment = (
		target.get_node_or_null("WorldEnvironment") as WorldEnvironment
	)
	if is_instance_valid(direct_env):
		return direct_env

	for child: Node in target.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment

	var env_nodes: Array[Node] = target.find_children("*", "WorldEnvironment", true, false)
	for node: Node in env_nodes:
		var candidate: WorldEnvironment = node as WorldEnvironment
		if is_instance_valid(candidate) and candidate.find_parent("DioramaViewport") == null:
			return candidate

	return null


## Snaps player position downward using direct space state raycast.
func _snap_player_to_floor(player: CharacterBody3D) -> void:
	print("LoadingScreen: Snapping player position to collision floor.")
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var ray_origin: Vector3 = player.global_position + Vector3(0.0, 0.5, 0.0)
	var ray_end: Vector3 = player.global_position - Vector3(0.0, 5.0, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin, ray_end, 1
	)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		var raw_pos: Variant = hit.get("position", player.global_position)
		var hit_pos: Vector3 = raw_pos if raw_pos is Vector3 else player.global_position
		player.global_position = hit_pos + Vector3(0.0, 0.05, 0.0)
		print("LoadingScreen: Player aligned to floor at: ", player.global_position)


## Retrieves [PlayerLocomotionComponent] from the target player entity safely.
func _get_player_locomotion(p_player: Node) -> PlayerLocomotionComponent:
	if not is_instance_valid(p_player):
		return null
	var raw: Variant = p_player.get(PROP_LOCOMOTION)
	if raw is PlayerLocomotionComponent and is_instance_valid(raw):
		var locomotion: PlayerLocomotionComponent = raw
		return locomotion
	return null


## Retrieves [CameraController] from the target player entity safely.
func _get_camera_controller(p_player: Node) -> CameraController:
	if not is_instance_valid(p_player):
		return null
	var raw: Variant = p_player.get(PROP_CAMERA_CONTROLLER)
	if raw is CameraController and is_instance_valid(raw):
		var controller: CameraController = raw
		return controller
	return null
