## Manages async scene loading, shader warmup, and staged SDFGI activation.
class_name LoadingScreen
extends CanvasLayer

## Tracks whether an active loading screen transition is currently in flight.
static var is_transition_active: bool = false

## Maximum milliseconds budgeted per frame for material warmup.
const MAX_WARMUP_TIME_MS: int = 12

## Number of idle frames to wait for camera transform settling before SDFGI.
const SETTLING_FRAMES: int = 4

## The file path to the level scene that needs to be loaded in the background.
@export_file("*.tscn", "*.scn") var level_scene_path: String = ""

## A custom resource containing a list of materials to precompile.
@export var baked_shader_cache: ShaderCache

## Optional audio stream matching the first animation (bella_wrench).
@export var audio_bella_wrench: AudioStream

## Optional audio stream matching the second animation (priestess_twoface).
@export var audio_priestess_twoface: AudioStream

## The visual indicator container to fade smoothly without breaking root layout.
@onready var visual_root: Control = $VisualRoot

## The animated sprite showing random loading sequence loops.
@onready var animation: AnimatedSprite2D = $VisualRoot/CenterContainer/SpriteAnchor/AnimatedSprite2D

## The progress bar UI element that fills up as loading completes.
@onready var progress_bar: ProgressBar = $VisualRoot/CenterContainer/SpriteAnchor/ProgressBar

## The audio player responsible for loading screen background audio.
@onready var audio_player: AudioStreamPlayer = $VisualRoot/AudioStreamPlayer

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
var _warmup_viewport: SubViewport = null

## Node container holding temporary 3D meshes inside the warmup viewport.
var _warmup_container_3d: Node3D = null

## Node container holding temporary 2D elements inside the warmup viewport.
var _warmup_container_2d: Control = null

## Reusable dummy mesh instance used to warm up 3D materials.
var _warmup_mesh_instance: MeshInstance3D = null

## Reusable dummy color rect used to warm up 2D canvas materials.
var _warmup_color_rect: ColorRect = null

## Reusable quad geometry shared across 3D material warmup steps.
var _warmup_quad_mesh: QuadMesh = null


## Initializes background scene loading, animations, and sound playback.
func _ready() -> void:
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

	print("LoadingScreen: Starting background load for: ", level_scene_path)
	_select_random_presentation()

	var error: Error = ResourceLoader.load_threaded_request(level_scene_path, "", true)
	if error != OK:
		push_error("LoadingScreen: Request failed: " + error_string(error))
		_cleanup_warmup_viewport()
		set_process(false)
		return

	_status = ResourceLoader.load_threaded_get_status(level_scene_path)


## Selects and starts a random animation alongside its matching audio track.
func _select_random_presentation() -> void:
	print("LoadingScreen: Selecting random presentation pair.")
	var anim_options: PackedStringArray = PackedStringArray(["bella_wrench", "priestess_twoface"])
	var picked_anim: String = anim_options[randi() % anim_options.size()]
	animation.play(picked_anim)

	if picked_anim == "bella_wrench" and is_instance_valid(audio_bella_wrench):
		audio_player.stream = audio_bella_wrench
		audio_player.play()
	elif picked_anim == "priestess_twoface" and is_instance_valid(audio_priestess_twoface):
		audio_player.stream = audio_priestess_twoface
		audio_player.play()


## Cleans up allocated warmup resources when the node is removed from the tree.
func _exit_tree() -> void:
	print("LoadingScreen: Cleaning up resources on tree exit.")
	is_transition_active = false
	_cleanup_warmup_viewport()


## Monitors loading progress and coordinates the transition pipeline.
func _process(_delta: float) -> void:
	if not _is_resource_loaded:
		_status = ResourceLoader.load_threaded_get_status(level_scene_path, _progress_array)

		match _status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var target_val: float = _progress_array[0] * 70.0
				progress_bar.value = target_val

			ResourceLoader.THREAD_LOAD_LOADED:
				_is_resource_loaded = true
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

	elif _is_warmup_complete:
		_finalize_scene_transition()


## Sets up the isolated warmup viewport and begins pipeline compilation.
func _start_shader_warmup() -> void:
	if not baked_shader_cache or baked_shader_cache.materials.is_empty():
		print("LoadingScreen: No shader cache found. Skipping warmup phase.")
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


## Prepares reusable dummy nodes to warm shaders without allocations.
func _setup_warmup_pipeline_nodes() -> void:
	print("LoadingScreen: Pre-allocating pooled nodes for shader warmup.")
	_warmup_quad_mesh = QuadMesh.new()
	_warmup_quad_mesh.size = Vector2(0.2, 0.2)

	_warmup_mesh_instance = MeshInstance3D.new()
	_warmup_mesh_instance.mesh = _warmup_quad_mesh
	_warmup_mesh_instance.layers = 1
	_warmup_container_3d.add_child(_warmup_mesh_instance)

	_warmup_color_rect = ColorRect.new()
	_warmup_color_rect.size = Vector2(16.0, 16.0)
	_warmup_container_2d.add_child(_warmup_color_rect)


## Processes materials across frames within [constant MAX_WARMUP_TIME_MS].
func _compile_materials_budgeted() -> void:
	print("LoadingScreen: Compiling cached shader pipelines...")
	var total_mats: int = baked_shader_cache.materials.size()

	while _compile_index < total_mats:
		var start_time: int = Time.get_ticks_msec()

		while _compile_index < total_mats:
			var res: Resource = baked_shader_cache.materials[_compile_index]
			if res is Material:
				_warmup_material(res as Material)
			_compile_index += 1

			var warmup_ratio: float = float(_compile_index) / float(total_mats)
			progress_bar.value = 70.0 + (warmup_ratio * 30.0)

			if (Time.get_ticks_msec() - start_time) >= MAX_WARMUP_TIME_MS:
				break

		await get_tree().process_frame

	print("LoadingScreen: Shader warmup completed. Freeing warmup viewport.")
	_cleanup_warmup_viewport()
	_is_warmup_complete = true


## Applies [param mat] to dummy nodes to trigger GPU shader compilation.
func _warmup_material(mat: Material) -> void:
	var is_2d: bool = mat is CanvasItemMaterial

	if mat is ShaderMaterial:
		var s_mat: ShaderMaterial = mat if mat is ShaderMaterial else null
		if not is_instance_valid(s_mat.shader):
			return
		if s_mat.shader.get_mode() == Shader.MODE_CANVAS_ITEM:
			is_2d = true

	if is_2d:
		_warmup_color_rect.visible = true
		_warmup_mesh_instance.visible = false
		_warmup_color_rect.material = mat
	else:
		_warmup_color_rect.visible = false
		_warmup_mesh_instance.visible = true
		_warmup_mesh_instance.material_override = mat


## Explicitly frees the warmup [SubViewport] and nullifies references.
func _cleanup_warmup_viewport() -> void:
	print("LoadingScreen: Cleaning up warmup viewport instances.")
	if is_instance_valid(_warmup_viewport):
		_warmup_viewport.queue_free()
		_warmup_viewport = null
		_warmup_container_3d = null
		_warmup_container_2d = null
		_warmup_mesh_instance = null
		_warmup_color_rect = null
		_warmup_quad_mesh = null


## Finalizes scene switch, sweeps camera to compile PSOs, and stages SDFGI.
func _finalize_scene_transition() -> void:
	print("LoadingScreen: Evicting previous levels and mounting new scene.")
	set_process(false)
	progress_bar.value = 100.0
	audio_player.stop()

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

	var new_scene: Node = loaded_scene.instantiate()
	if not is_instance_valid(new_scene):
		push_error("LoadingScreen: Failed to instantiate PackedScene.")
		return

	var world_env: WorldEnvironment = _find_world_environment(new_scene)
	var target_env: Environment = null

	if is_instance_valid(world_env) and is_instance_valid(world_env.environment):
		world_env.environment = world_env.environment.duplicate()
		target_env = world_env.environment
		target_env.sdfgi_enabled = false
		print("LoadingScreen: Initialized environment with SDFGI staged off.")

	root.add_child(new_scene)
	get_tree().current_scene = new_scene

	var chunker: WorldChunkManager = (
		new_scene.find_child("WorldChunkManager", true, false) as WorldChunkManager
	)
	if is_instance_valid(chunker):
		print("LoadingScreen: Waiting for WorldChunkManager initial zone...")
		await chunker.initial_zone_ready

	var player_node: CharacterBody3D = (
		new_scene.find_child("Player", true, false) as CharacterBody3D
	)
	var locomotion: PlayerLocomotionComponent = _get_player_locomotion(player_node)
	if is_instance_valid(locomotion):
		locomotion.set_physics_active(false)
	if is_instance_valid(player_node):
		player_node.velocity = Vector3.ZERO

	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	if is_instance_valid(player_node):
		_snap_player_to_floor(player_node)
		if player_node.has_method(&"activate_gameplay_camera"):
			player_node.call(&"activate_gameplay_camera")

	print("LoadingScreen: Synchronizing viewport pipeline prior to GI activation.")
	await _reapply_active_video_settings()

	for frame_idx: int in range(SETTLING_FRAMES):
		await get_tree().process_frame

	var sdfgi_setting: String = _get_setting_string(
		"Settings", "sdfgi", str(VideoConfig.DEFAULT_SDFGI)
	)
	var sdfgi_dict: Dictionary = _get_config_dict(VideoConfig.SDFGI_MODES, sdfgi_setting)
	var should_enable_raw: Variant = sdfgi_dict.get("enabled", false)
	var should_enable_sdfgi: bool = should_enable_raw == true

	if is_instance_valid(target_env) and should_enable_sdfgi:
		target_env.sdfgi_enabled = true
		print("LoadingScreen: SDFGI enabled smoothly.")
		await get_tree().process_frame
		await get_tree().process_frame

	var cam_controller: CameraController = _get_camera_controller(player_node)
	if is_instance_valid(player_node) and is_instance_valid(cam_controller):
		print("LoadingScreen: Performing 360-degree frustum sweep to cache pipeline states.")
		var original_rot: float = player_node.rotation.y
		for angle_deg: float in [90.0, 180.0, 270.0, 0.0]:
			player_node.rotation.y = original_rot + deg_to_rad(angle_deg)
			await get_tree().process_frame
		player_node.rotation.y = original_rot
		await get_tree().process_frame

	var fade_tween: Tween = create_tween()
	fade_tween.tween_property(visual_root, "modulate:a", 0.0, 0.25)
	await fade_tween.finished

	if is_instance_valid(locomotion):
		locomotion.set_physics_active(true)
		print("LoadingScreen: Re-enabled player locomotion after visual fade.")

	print("LoadingScreen: Transition complete. Freeing loading screen.")
	queue_free()


## Applies saved video settings from [GlobalSettings] to the new scene tree.
func _reapply_active_video_settings() -> void:
	print("LoadingScreen: Re-applying active user video settings to new scene.")
	var shadow_key: String = _get_setting_string("Settings", "shadow_quality", "High (Smooth)")
	var shadow_data: Dictionary = _get_config_dict(VideoConfig.SHADOW_QUALITIES, shadow_key)
	var fsr_key: String = _get_setting_string(
		"Settings", "fsr_mode", str(VideoConfig.DEFAULT_FSR_MODE)
	)
	var aa_key: String = _get_setting_string(
		"Settings", "aa_mode", str(VideoConfig.DEFAULT_AA_MODE)
	)
	var vrs_key: String = _get_setting_string(
		"Settings", "vrs_mode", str(VideoConfig.DEFAULT_VRS_MODE)
	)
	var tex_filter: String = _get_setting_string(
		"Settings", "texture_filter", str(VideoConfig.DEFAULT_TEXTURE_FILTER)
	)
	var ssao_key: String = _get_setting_string("Settings", "ssao", str(VideoConfig.DEFAULT_SSAO))
	var ssi_key: String = _get_setting_string("Settings", "ssi", str(VideoConfig.DEFAULT_SSI))
	var ssr_key: String = _get_setting_string("Settings", "ssr", str(VideoConfig.DEFAULT_SSR))
	var fog_key: String = _get_setting_string(
		"Settings", "volumetric_fog", str(VideoConfig.DEFAULT_FOG)
	)
	var glow_key: String = _get_setting_string("Settings", "glow", str(VideoConfig.DEFAULT_GLOW))

	var raw_fsr: Variant = VideoConfig.FSR_MODES.get(fsr_key, 1.0)
	var fsr_scale: float = raw_fsr if raw_fsr is float else 1.0

	var raw_atlas: Variant = shadow_data.get("atlas_size", 4096)
	var shadow_atlas: int = raw_atlas if raw_atlas is int else 4096

	var shadow_filter_str: String = _get_setting_string("Settings", "shadow_filter", "Soft Medium")
	var tonemap_str: String = _get_setting_string("Settings", "tonemap_mode", "Filmic")

	var config: Dictionary = {
		"fsr_scale": fsr_scale,
		"aa_settings": _get_config_dict(VideoConfig.AA_MODES, aa_key),
		"shadow_atlas": shadow_atlas,
		"dynamic_light_shadows":
		GlobalSettings.get_setting_bool("Settings", "dynamic_light_shadows", true),
		"shadow_filter": shadow_filter_str,
		"positional_shadow_distance":
		GlobalSettings.get_setting_float("Settings", "positional_shadow_distance", 32.0),
		"directional_shadow_distance":
		GlobalSettings.get_setting_float("Settings", "directional_shadow_distance", 64.0),
		"occlusion_culling": GlobalSettings.get_setting_bool("Settings", "occlusion_culling", true),
		"vrs_mode": VideoConfig.VRS_MODES.get(vrs_key, Viewport.VRS_DISABLED),
		"texture_filter": VideoConfig.TEXTURE_FILTER_MODES.get(tex_filter, 2),
		"resolution_scale": GlobalSettings.get_setting_float("Settings", "resolution_scale", 1.0),
		"exposure": GlobalSettings.get_setting_float("Settings", "exposure", 1.0),
		"motion_blur": GlobalSettings.get_setting_float("Settings", "motion_blur", 0.0),
		"mesh_lod": GlobalSettings.get_setting_float("Settings", "mesh_lod_threshold", 1.0),
		"debanding": GlobalSettings.get_setting_bool("Settings", "debanding", true),
		"tonemap_key": tonemap_str,
		"dof_amount": GlobalSettings.get_setting_float("Settings", "dof_amount", 0.0),
		"dof_enabled": GlobalSettings.get_setting_bool("Settings", "dof_enabled", false),
		"ssao": _get_config_dict(VideoConfig.SSAO_MODES, ssao_key),
		"ssi": _get_config_dict(VideoConfig.SSI_MODES, ssi_key),
		"ssr": _get_config_dict(VideoConfig.SSR_MODES, ssr_key),
		"sdfgi": {"enabled": false},
		"fog": _get_config_dict(VideoConfig.FOG_MODES, fog_key),
		"glow": _get_config_dict(VideoConfig.GLOW_MODES, glow_key),
	}
	await VideoApplier.apply_viewport_pipeline(get_tree(), get_viewport(), config)


## Safely extracts a string setting from persistent [GlobalSettings].
func _get_setting_string(category: String, key: String, default_value: String) -> String:
	var raw: Variant = GlobalSettings.get_setting(category, key, default_value)
	var result: String = raw if raw is String else default_value
	return result


## Safely extracts a [Dictionary] configuration block by key.
func _get_config_dict(source: Dictionary, key: String) -> Dictionary:
	var raw: Variant = source.get(key, {})
	var result: Dictionary = raw if raw is Dictionary else {}
	return result


## Locates [WorldEnvironment] safely even if [param target] is outside tree.
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

	var env_nodes: Array[Node] = target.find_children("", "WorldEnvironment", true, false)
	if not env_nodes.is_empty():
		return env_nodes[0] as WorldEnvironment

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
	var raw: Variant = p_player.get(&"locomotion_component")
	if raw is PlayerLocomotionComponent and is_instance_valid(raw):
		var locomotion: PlayerLocomotionComponent = raw
		return locomotion
	return null


## Retrieves [CameraController] from the target player entity safely.
func _get_camera_controller(p_player: Node) -> CameraController:
	if not is_instance_valid(p_player):
		return null
	var raw: Variant = p_player.get(&"camera_controller")
	if raw is CameraController and is_instance_valid(raw):
		var controller: CameraController = raw
		return controller
	return null
