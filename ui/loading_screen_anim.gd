## Manages async scene loading, shader warmup, and staged SDFGI activation.
class_name LoadingScreen
extends CanvasLayer

## Tracks whether an active loading screen transition is currently in flight.
static var is_transition_active: bool = false

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

## Maximum milliseconds budgeted per frame for material warmup.
const MAX_WARMUP_TIME_MS: int = 12

## Number of idle frames to wait for camera transform settling before SDFGI.
const SETTLING_FRAMES: int = 3

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
	get_tree().paused = true
	_select_random_presentation()

	var error: Error = ResourceLoader.load_threaded_request(level_scene_path, "", true)
	if error != OK:
		push_error("LoadingScreen: Request failed: " + error_string(error))
		get_tree().paused = false
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
				get_tree().paused = false
				audio_player.stop()
				_cleanup_warmup_viewport()
				push_error("LoadingScreen: Failed loading assets from disk.")

			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				set_process(false)
				get_tree().paused = false
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
	_warmup_viewport.own_world_3d = true
	_warmup_viewport.world_3d = World3D.new()
	_warmup_viewport.size = Vector2i(64, 64)
	_warmup_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_warmup_viewport.transparent_bg = true

	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 2.0)
	camera.cull_mask = 1
	_warmup_viewport.add_child(camera)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-45.0, 45.0, 0.0)
	_warmup_viewport.add_child(light)

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
			var mat: Material = baked_shader_cache.materials[_compile_index]
			if is_instance_valid(mat):
				_warmup_material(mat)
			_compile_index += 1

			var warmup_ratio: float = float(_compile_index) / float(total_mats)
			progress_bar.value = 70.0 + (warmup_ratio * 30.0)

			if (Time.get_ticks_msec() - start_time) >= MAX_WARMUP_TIME_MS:
				await get_tree().process_frame
				break

	await get_tree().process_frame

	print("LoadingScreen: Shader warmup completed. Freeing warmup viewport.")
	_cleanup_warmup_viewport()
	_is_warmup_complete = true


## Applies [param mat] to dummy nodes to trigger GPU shader compilation.
func _warmup_material(mat: Material) -> void:
	#print("LoadingScreen: Warming shader pipeline for: ", mat.resource_name)
	var is_2d: bool = mat is CanvasItemMaterial

	if mat is ShaderMaterial:
		var s_mat: ShaderMaterial = mat as ShaderMaterial
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


## Finalizes scene switch, stages SDFGI, and synchronizes video settings.
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
		get_tree().paused = false
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
		get_tree().paused = false
		return

	var world_env: WorldEnvironment = _find_world_environment(new_scene)
	var target_env: Environment = null
	var should_enable_sdfgi: bool = false

	if is_instance_valid(world_env) and is_instance_valid(world_env.environment):
		world_env.environment = world_env.environment.duplicate()
		target_env = world_env.environment
		should_enable_sdfgi = target_env.sdfgi_enabled
		target_env.sdfgi_enabled = false
		print("LoadingScreen: Staged SDFGI off on duplicated environment.")

	# Add scene to tree
	root.add_child(new_scene)
	get_tree().current_scene = new_scene

	var player_node: Player = new_scene.find_child("Player", true, false) as Player
	if is_instance_valid(player_node):
		if is_instance_valid(player_node.locomotion_component):
			player_node.locomotion_component.set_physics_active(false)
		player_node.velocity = Vector3.ZERO

	# Unpause first so PhysicsServer3D can process CSG collision generation
	get_tree().paused = false

	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	if is_instance_valid(player_node):
		_snap_player_to_floor(player_node)
		player_node.activate_gameplay_camera()
		if is_instance_valid(player_node.locomotion_component):
			player_node.locomotion_component.set_physics_active(true)

	for frame_idx: int in range(SETTLING_FRAMES):
		await get_tree().process_frame

	if is_instance_valid(target_env) and should_enable_sdfgi:
		target_env.sdfgi_enabled = true
		print("LoadingScreen: Camera settled. SDFGI enabled smoothly.")
		await get_tree().process_frame

	_reapply_active_video_settings()

	var fade_tween: Tween = create_tween()
	fade_tween.tween_property(visual_root, "modulate:a", 0.0, 0.25)
	await fade_tween.finished

	print("LoadingScreen: Transition complete. Freeing loading screen.")
	queue_free()


## Applies saved video settings from GlobalSettings to the new scene tree.
func _reapply_active_video_settings() -> void:
	print("LoadingScreen: Re-applying active user video settings to new scene.")
	var shadow_key: String = (
		GlobalSettings.get_setting("Settings", "shadow_quality", "High (Smooth)") as String
	)
	var shadow_data: Dictionary = VideoConfig.SHADOW_QUALITIES.get(shadow_key, {}) as Dictionary
	var fsr_key: String = (
		GlobalSettings.get_setting("Settings", "fsr_mode", VideoConfig.DEFAULT_FSR_MODE) as String
	)
	var aa_key: String = (
		GlobalSettings.get_setting("Settings", "aa_mode", VideoConfig.DEFAULT_AA_MODE) as String
	)
	var vrs_key: String = (
		GlobalSettings.get_setting("Settings", "vrs_mode", VideoConfig.DEFAULT_VRS_MODE) as String
	)
	var tex_filter: String = (
		GlobalSettings.get_setting("Settings", "texture_filter", VideoConfig.DEFAULT_TEXTURE_FILTER)
		as String
	)
	var ssao_key: String = (
		GlobalSettings.get_setting("Settings", "ssao", VideoConfig.DEFAULT_SSAO) as String
	)
	var ssi_key: String = (
		GlobalSettings.get_setting("Settings", "ssi", VideoConfig.DEFAULT_SSI) as String
	)
	var ssr_key: String = (
		GlobalSettings.get_setting("Settings", "ssr", VideoConfig.DEFAULT_SSR) as String
	)
	var sdfgi_key: String = (
		GlobalSettings.get_setting("Settings", "sdfgi", VideoConfig.DEFAULT_SDFGI) as String
	)
	var fog_key: String = (
		GlobalSettings.get_setting("Settings", "volumetric_fog", VideoConfig.DEFAULT_FOG) as String
	)
	var glow_key: String = (
		GlobalSettings.get_setting("Settings", "glow", VideoConfig.DEFAULT_GLOW) as String
	)

	var config: Dictionary = {
		"fsr_scale": VideoConfig.FSR_MODES.get(fsr_key, 1.0) as float,
		"aa_settings": VideoConfig.AA_MODES.get(aa_key, {}) as Dictionary,
		"shadow_atlas": shadow_data.get("atlas_size", 4096) as int,
		"dynamic_light_shadows":
		bool(GlobalSettings.get_setting("Settings", "dynamic_light_shadows", true)),
		"shadow_filter":
		GlobalSettings.get_setting("Settings", "shadow_filter", "Soft Medium") as String,
		"positional_shadow_distance":
		float(GlobalSettings.get_setting("Settings", "positional_shadow_distance", 32.0)),
		"directional_shadow_distance":
		float(GlobalSettings.get_setting("Settings", "directional_shadow_distance", 64.0)),
		"occlusion_culling":
		bool(GlobalSettings.get_setting("Settings", "occlusion_culling", true)),
		"vrs_mode": VideoConfig.VRS_MODES.get(vrs_key, Viewport.VRS_DISABLED),
		"texture_filter": VideoConfig.TEXTURE_FILTER_MODES.get(tex_filter, 2),
		"resolution_scale": float(GlobalSettings.get_setting("Settings", "resolution_scale", 1.0)),
		"exposure": float(GlobalSettings.get_setting("Settings", "exposure", 1.0)),
		"motion_blur": float(GlobalSettings.get_setting("Settings", "motion_blur", 0.0)),
		"mesh_lod": float(GlobalSettings.get_setting("Settings", "mesh_lod_threshold", 1.0)),
		"debanding": bool(GlobalSettings.get_setting("Settings", "debanding", true)),
		"tonemap_key": GlobalSettings.get_setting("Settings", "tonemap_mode", "Filmic") as String,
		"dof_amount": float(GlobalSettings.get_setting("Settings", "dof_amount", 0.0)),
		"dof_enabled": bool(GlobalSettings.get_setting("Settings", "dof_enabled", false)),
		"ssao": VideoConfig.SSAO_MODES.get(ssao_key, {}) as Dictionary,
		"ssi": VideoConfig.SSI_MODES.get(ssi_key, {}) as Dictionary,
		"ssr": VideoConfig.SSR_MODES.get(ssr_key, {}) as Dictionary,
		"sdfgi": VideoConfig.SDFGI_MODES.get(sdfgi_key, {}) as Dictionary,
		"fog": VideoConfig.FOG_MODES.get(fog_key, {}) as Dictionary,
		"glow": VideoConfig.GLOW_MODES.get(glow_key, {}) as Dictionary,
	}
	VideoApplier.apply_viewport_pipeline(get_tree(), get_viewport(), config)


## Locates the active [WorldEnvironment] inside [param target] branch.
func _find_world_environment(target: Node) -> WorldEnvironment:
	print("LoadingScreen: Locating WorldEnvironment in scene hierarchy.")
	if target is WorldEnvironment:
		return target as WorldEnvironment
	var env_nodes: Array[Node] = target.find_children("", "WorldEnvironment", true, false)
	if not env_nodes.is_empty():
		return env_nodes[0] as WorldEnvironment
	return null


## Snaps player position downward using direct space state raycast.
func _snap_player_to_floor(player: Player) -> void:
	print("LoadingScreen: Snapping player position to collision floor.")
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var ray_origin: Vector3 = player.global_position + Vector3(0.0, 0.5, 0.0)
	var ray_end: Vector3 = player.global_position - Vector3(0.0, 5.0, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin, ray_end, 1
	)
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		player.global_position = (hit.position as Vector3) + Vector3(0.0, 0.05, 0.0)
		print("LoadingScreen: Player aligned to floor at: ", player.global_position)
