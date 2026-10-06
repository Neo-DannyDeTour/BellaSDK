## Centralizes visual pipeline, window configuration, shadow atlases, and passes.
class_name VideoApplier
extends RefCounted

## Visual Layer bitmask for isolated preview geometry (3D Render Layer 11).
const PREVIEW_LAYER_MASK: int = 1 << 10

## Visual Layer bitmask for primary static world geometry (3D Render Layer 1).
const ENVIRONMENT_LAYER_MASK: int = CollisionLayers.RENDER_MASK_ENVIRONMENT

## Cached density texture instance shared across all viewports using VRS.
static var _cached_vrs_texture: ImageTexture = null

## Cached dictionary of active pipeline configuration to avoid redundant work.
static var _last_applied_config: Dictionary = {}

## Cached volumetric fog depth slice count to avoid pipeline rebuild stalls.
static var _cached_fog_depth: int = -1

## Cached shadow atlas size to avoid redundant quadrant reallocations.
static var _cached_shadow_atlas_size: int = -1

## Monotonic execution token preventing race conditions during staggered setup.
static var _pipeline_run_id: int = 0


## Updates application display mode, screen assignment, and dimensions.
static func apply_window_settings(
	window: Window, mode: DisplayServer.WindowMode, screen_idx: int, resolution: Vector2i
) -> void:
	print("VideoApplier: Applying window settings -> ", mode, " at ", resolution)
	if window.current_screen != screen_idx:
		window.current_screen = screen_idx

	var target_mode: Window.Mode = mode as Window.Mode
	if window.mode != target_mode:
		window.mode = target_mode

	if window.content_scale_size != resolution:
		window.content_scale_size = resolution

	if not window.is_embedded() and window.mode == Window.MODE_WINDOWED:
		window.borderless = false
		if window.size != resolution:
			window.size = resolution


## Applies VSync mode and framerate limit cap to DisplayServer and Engine.
static func apply_engine_limits(vsync_mode: DisplayServer.VSyncMode, fps_limit: int) -> void:
	print("VideoApplier: Applying engine limits. FPS: ", fps_limit)
	DisplayServer.window_set_vsync_mode(vsync_mode)

	var active_vsync: DisplayServer.VSyncMode = DisplayServer.window_get_vsync_mode()
	if active_vsync != vsync_mode:
		print("VideoApplier: Display driver clamped VSync to: ", active_vsync)

	Engine.max_fps = fps_limit


## Sets texture anisotropic filtering level in ProjectSettings.
static func apply_anisotropy(level: int) -> void:
	print("VideoApplier: Setting anisotropic filtering level: ", level)
	var key: String = "rendering/textures/default_filters/anisotropic_filtering_level"
	var cur_val: Variant = ProjectSettings.get_setting(key)
	if cur_val != level:
		ProjectSettings.set_setting(key, level)


## Verifies whether active GPU backend and graphics driver support VRS.
static func is_vrs_supported() -> bool:
	print("VideoApplier: Checking VRS hardware support.")
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if not is_instance_valid(rd):
		return false
	var driver: String = ProjectSettings.get_setting_with_override(
		"rendering/renderer/rendering_method"
	)
	return driver != "gl_compatibility"


## Staggers rendering pipeline updates over frames to prevent Vulkan stalls.
static func apply_viewport_pipeline(
	tree: SceneTree, main_viewport: Viewport, config: Dictionary
) -> void:
	print("VideoApplier: Starting staggered pipeline synchronization.")
	_pipeline_run_id += 1
	var current_run_id: int = _pipeline_run_id
	_last_applied_config = config.duplicate(true)

	# Frame 1: Shadow Atlases, Filters, Light Configurations & Server Qualities
	_apply_stage_shadows_and_lighting(tree, main_viewport, config)

	if not is_instance_valid(tree):
		return
	await tree.process_frame
	if current_run_id != _pipeline_run_id:
		print("VideoApplier: Aborting superseded pipeline pass at Frame 2.")
		return

	# Frame 2: Anti-Aliasing, Scaling, VRS, Occlusion & Viewport Modes
	_apply_stage_viewport_aa_and_scaling(tree, main_viewport, config)

	if not is_instance_valid(tree):
		return
	await tree.process_frame
	if current_run_id != _pipeline_run_id:
		print("VideoApplier: Aborting superseded pipeline pass at Frame 3.")
		return

	# Frame 3: Environments, SDFGI Probes, Fog Voxels & Camera Attributes
	_apply_stage_environments(tree, config)
	print("VideoApplier: Staggered pipeline applied successfully.")


## Configures shadow atlas sizes, light masks, and RenderingServer settings.
static func _apply_stage_shadows_and_lighting(
	tree: SceneTree, main_viewport: Viewport, config: Dictionary
) -> void:
	print("VideoApplier: Executing Stage 1 (Shadows & Lights).")
	_apply_rendering_server_qualities(config)
	_apply_light_shadows(tree, config)

	var requested_atlas: int = config.get("shadow_atlas", 4096)
	if main_viewport.positional_shadow_atlas_size != requested_atlas:
		main_viewport.positional_shadow_atlas_size = requested_atlas
		_cached_shadow_atlas_size = requested_atlas
		if requested_atlas > 0:
			main_viewport.positional_shadow_atlas_16_bits = true
			main_viewport.set_positional_shadow_atlas_quadrant_subdiv(
				0, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
			)
			main_viewport.set_positional_shadow_atlas_quadrant_subdiv(
				1, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
			)
			main_viewport.set_positional_shadow_atlas_quadrant_subdiv(
				2, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16
			)
			main_viewport.set_positional_shadow_atlas_quadrant_subdiv(
				3, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64
			)

	var dir_atlas: int = maxi(requested_atlas, 1024)
	RenderingServer.directional_shadow_atlas_set_size(dir_atlas, true)


## Configures anti-aliasing, scaling mode, and viewport post-process flags.
static func _apply_stage_viewport_aa_and_scaling(
	tree: SceneTree, main_viewport: Viewport, config: Dictionary
) -> void:
	print("VideoApplier: Executing Stage 2 (Viewport AA & Scaling).")
	var filter_mode: int = config.get("texture_filter", 2)
	var f_key: String = "rendering/textures/default_filters/texture_filter_mode"
	if ProjectSettings.get_setting(f_key) != filter_mode:
		ProjectSettings.set_setting(f_key, filter_mode)

	var fsr_scale: float = config.get("fsr_scale", 1.0)
	var raw_scale: float = config.get("resolution_scale", 1.0)
	var active_scale: float = fsr_scale if fsr_scale < 1.0 else raw_scale
	var active_scaling_mode: Viewport.Scaling3DMode = (
		Viewport.SCALING_3D_MODE_FSR2 if fsr_scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	)

	var aa_settings: Dictionary = config.get("aa_settings", {})
	var primary_msaa: Viewport.MSAA = aa_settings.get("msaa", Viewport.MSAA_DISABLED)
	var taa_enabled: bool = aa_settings.get("taa", false)
	var active_taa: bool = (fsr_scale >= 1.0) and taa_enabled
	var active_fxaa: Viewport.ScreenSpaceAA = aa_settings.get(
		"fxaa", Viewport.SCREEN_SPACE_AA_DISABLED
	)

	var sdfgi_dict: Dictionary = config.get("sdfgi", {})
	var fog_dict: Dictionary = config.get("fog", {})
	var is_sdfgi_active: bool = sdfgi_dict.get("enabled", false)
	var is_fog_active: bool = fog_dict.get("enabled", false)

	if (is_sdfgi_active or is_fog_active) and primary_msaa != Viewport.MSAA_DISABLED:
		print("VideoApplier: Disabling MSAA to prevent compute fill-rate stalls.")
		primary_msaa = Viewport.MSAA_DISABLED

	var raw_vrs: Viewport.VRSMode = config.get("vrs_mode", Viewport.VRS_DISABLED)
	var occ_cull: bool = config.get("occlusion_culling", true)
	var mesh_lod: float = config.get("mesh_lod", 1.0)
	var debanding_val: bool = config.get("debanding", true)

	if not is_vrs_supported():
		raw_vrs = Viewport.VRS_DISABLED

	if raw_vrs == Viewport.VRS_TEXTURE and not is_instance_valid(_cached_vrs_texture):
		_cached_vrs_texture = VrsTextureGenerator.create_radial_density_map()

	main_viewport.canvas_item_default_texture_filter = (
		filter_mode as Viewport.DefaultCanvasItemTextureFilter
	)
	main_viewport.use_occlusion_culling = occ_cull
	main_viewport.scaling_3d_mode = active_scaling_mode
	main_viewport.scaling_3d_scale = active_scale
	main_viewport.use_taa = active_taa
	main_viewport.msaa_3d = primary_msaa
	main_viewport.screen_space_aa = active_fxaa
	main_viewport.use_debanding = debanding_val
	main_viewport.mesh_lod_threshold = mesh_lod

	if raw_vrs == Viewport.VRS_TEXTURE and is_instance_valid(_cached_vrs_texture):
		main_viewport.vrs_texture = _cached_vrs_texture
		main_viewport.vrs_mode = Viewport.VRS_TEXTURE
	else:
		main_viewport.vrs_mode = Viewport.VRS_DISABLED
		main_viewport.vrs_texture = null

	var diorama_vp: SubViewport = _resolve_diorama_viewport(tree)
	if is_instance_valid(diorama_vp):
		diorama_vp.own_world_3d = true
		if diorama_vp.world_3d == null:
			diorama_vp.world_3d = World3D.new()
		diorama_vp.use_occlusion_culling = occ_cull
		diorama_vp.scaling_3d_mode = active_scaling_mode
		diorama_vp.scaling_3d_scale = active_scale
		diorama_vp.use_taa = active_taa
		diorama_vp.msaa_3d = _clamp_preview_msaa(primary_msaa)
		diorama_vp.screen_space_aa = active_fxaa
		diorama_vp.use_debanding = debanding_val
		diorama_vp.mesh_lod_threshold = mesh_lod
		var requested_atlas: int = config.get("shadow_atlas", 4096)
		if diorama_vp.positional_shadow_atlas_size != requested_atlas:
			diorama_vp.positional_shadow_atlas_size = requested_atlas
			if requested_atlas > 0:
				diorama_vp.positional_shadow_atlas_16_bits = true


## Synchronizes isolated environment tonemapping, SDFGI, and volumetric fog.
static func _apply_stage_environments(tree: SceneTree, config: Dictionary) -> void:
	print("VideoApplier: Executing Stage 3 (Environments & Materials).")
	_apply_environment_and_materials(tree, config)


## Synchronizes light shadow masks, atlas sizes, biases, and filter qualities.
static func _apply_light_shadows(tree: SceneTree, config: Dictionary) -> void:
	print("VideoApplier: Synchronizing light shadow configurations.")
	var enable_dyn: bool = config.get("dynamic_light_shadows", true)
	var f_key: String = config.get("shadow_filter", "Soft Medium")
	var filter_mode: RenderingServer.ShadowQuality = VideoConfig.SHADOW_FILTER_MODES.get(
		f_key, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	)
	var d_dist: float = config.get("directional_shadow_distance", 64.0)
	var p_dist: float = config.get("positional_shadow_distance", 24.0)
	var preview_mask: int = PREVIEW_LAYER_MASK | (1 << 9)

	RenderingServer.positional_soft_shadow_filter_set_quality(filter_mode)
	RenderingServer.directional_soft_shadow_filter_set_quality(filter_mode)

	var dir_lights: Array[Node] = _get_nodes_by_group_or_type(
		tree, &"lights_directional", "DirectionalLight3D"
	)
	for d_node: Node in dir_lights:
		var d_light: DirectionalLight3D = d_node if d_node is DirectionalLight3D else null
		if is_instance_valid(d_light):
			d_light.shadow_enabled = enable_dyn
			d_light.directional_shadow_max_distance = d_dist
			if d_light.find_parent("DioramaViewport") != null:
				d_light.light_cull_mask = preview_mask
			else:
				d_light.light_cull_mask = ENVIRONMENT_LAYER_MASK | (1 << 1) | (1 << 2)
				d_light.shadow_bias = 0.03
				d_light.shadow_normal_bias = 1.5

	var omni_lights: Array[Node] = _get_nodes_by_group_or_type(tree, &"lights_omni", "OmniLight3D")
	var spot_lights: Array[Node] = _get_nodes_by_group_or_type(tree, &"lights_spot", "SpotLight3D")
	var all_pos_lights: Array[Node] = omni_lights + spot_lights

	for node: Node in all_pos_lights:
		var light: Light3D = node if node is Light3D else null
		if not is_instance_valid(light):
			continue

		var is_diorama: bool = light.find_parent("DioramaViewport") != null
		if is_diorama or light.is_in_group("dynamic_shadow_casters"):
			light.shadow_enabled = enable_dyn
			light.distance_fade_enabled = true
			light.distance_fade_shadow = p_dist
			light.distance_fade_length = 4.0
			light.distance_fade_begin = maxf(p_dist - 4.0, 0.0)

			if is_diorama:
				light.light_cull_mask = preview_mask
			else:
				light.light_cull_mask = ENVIRONMENT_LAYER_MASK | (1 << 1) | (1 << 2)


## Clamps preview viewport MSAA strictly to 2X to maintain 60 FPS headroom.
static func _clamp_preview_msaa(requested_msaa: Viewport.MSAA) -> Viewport.MSAA:
	print("VideoApplier: Clamping preview MSAA to 2X.")
	return mini(requested_msaa, Viewport.MSAA_2X) as Viewport.MSAA


## Configures global SSAO, SSIL, and volumetric fog on [RenderingServer].
static func _apply_rendering_server_qualities(config: Dictionary) -> void:
	print("VideoApplier: Updating RenderingServer graphic quality settings.")
	var ssao_dict: Dictionary = config.get("ssao", {})
	if not ssao_dict.is_empty():
		var ssao_q: int = ssao_dict.get("quality", 1)
		var ssao_half: bool = ssao_dict.get("half_size", false)
		RenderingServer.environment_set_ssao_quality(
			ssao_q as RenderingServer.EnvironmentSSAOQuality, ssao_half, 0.5, 2, 1.0, 50.0
		)

	var ssi_dict: Dictionary = config.get("ssi", {})
	if not ssi_dict.is_empty():
		var ssi_q: int = ssi_dict.get("quality", 1)
		var ssi_half: bool = ssi_dict.get("half_size", false)
		RenderingServer.environment_set_ssil_quality(
			ssi_q as RenderingServer.EnvironmentSSILQuality, ssi_half, 0.5, 2, 1.0, 50.0
		)

	var fog_dict: Dictionary = config.get("fog", {})
	if not fog_dict.is_empty():
		var depth: int = fog_dict.get("depth", 64)
		if _cached_fog_depth != depth:
			_cached_fog_depth = depth
			RenderingServer.environment_set_volumetric_fog_volume_size(64, depth)


## Synchronizes environment tonemapping, lighting features, and cameras.
static func _apply_environment_and_materials(tree: SceneTree, config: Dictionary) -> void:
	print("VideoApplier: Synchronizing isolated environment parameters.")
	var main_environments: Array[Environment] = []
	var diorama_environments: Array[Environment] = []

	var diorama_vp: SubViewport = _resolve_diorama_viewport(tree)
	if is_instance_valid(diorama_vp):
		diorama_vp.own_world_3d = true
		if diorama_vp.find_world_3d():
			var dio_w: World3D = diorama_vp.find_world_3d()
			if not is_instance_valid(dio_w.environment):
				dio_w.environment = Environment.new()
			diorama_environments.append(dio_w.environment)

	var we_nodes: Array[Node] = _get_nodes_by_group_or_type(
		tree, &"world_environments", "WorldEnvironment"
	)
	for node: Node in we_nodes:
		var we: WorldEnvironment = node if node is WorldEnvironment else null
		if we.is_in_group("ignore_global_video_settings"):
			continue
		if is_instance_valid(we) and is_instance_valid(we.environment):
			if is_instance_valid(diorama_vp) and diorama_vp.is_ancestor_of(we):
				if we.environment not in diorama_environments:
					diorama_environments.append(we.environment)
			else:
				if we.environment not in main_environments:
					main_environments.append(we.environment)

	var root_w: World3D = tree.root.find_world_3d()
	if is_instance_valid(root_w) and is_instance_valid(root_w.environment):
		if root_w.environment not in main_environments:
			main_environments.append(root_w.environment)

	var exp_val: float = config.get("exposure", 1.0)
	var dof_amount: float = config.get("dof_amount", 0.0)
	var is_dof_active: bool = dof_amount > 0.005

	RenderingServer.gi_set_use_half_resolution(true)

	for env: Environment in main_environments:
		_populate_environment_values(env, config, exp_val, false)

	for dio_env: Environment in diorama_environments:
		_populate_environment_values(dio_env, config, exp_val, true)

	var active_cams: Array[Node] = _get_nodes_by_group_or_type(tree, &"cameras", "Camera3D")
	for c_node: Node in active_cams:
		var cam: Camera3D = c_node if c_node is Camera3D else null
		if not is_instance_valid(cam):
			continue

		if not is_instance_valid(cam.attributes):
			var new_attr: CameraAttributesPractical = CameraAttributesPractical.new()
			new_attr.dof_blur_far_distance = 6.0
			new_attr.dof_blur_far_transition = 8.0
			cam.attributes = new_attr

		if cam.attributes is CameraAttributesPractical:
			var cam_attr: CameraAttributesPractical = (
				cam.attributes if cam.attributes is CameraAttributesPractical else null
			)
			if cam_attr.dof_blur_far_enabled != is_dof_active:
				cam_attr.dof_blur_far_enabled = is_dof_active
			if not is_equal_approx(cam_attr.dof_blur_amount, dof_amount):
				cam_attr.dof_blur_amount = dof_amount

	var mb_factor: float = config.get("motion_blur", 0.0)
	for c_node: Node in active_cams:
		if c_node is ExtendedCamera3D:
			(c_node as ExtendedCamera3D).set_motion_blur_strength(mb_factor)


## Populates [Environment] properties respecting scene native fog and SDFGI.
static func _populate_environment_values(
	env: Environment, config: Dictionary, exposure: float, is_preview: bool
) -> void:
	print("VideoApplier: Populating environment settings. Preview: ", is_preview)
	env.tonemap_exposure = exposure

	var tonemap_key: String = config.get("tonemap_key", "Filmic")
	if VideoConfig.TONEMAP_MODES.has(tonemap_key):
		env.tonemap_mode = VideoConfig.TONEMAP_MODES[tonemap_key]

	var ssao_dict: Dictionary = config.get("ssao", {})
	env.ssao_enabled = ssao_dict.get("enabled", false)

	var ssi_dict: Dictionary = config.get("ssi", {})
	env.ssil_enabled = ssi_dict.get("enabled", false)

	var ssr_dict: Dictionary = config.get("ssr", {})
	env.ssr_enabled = ssr_dict.get("enabled", false)
	if env.ssr_enabled:
		var max_steps: int = ssr_dict.get("steps", 64)
		env.ssr_max_steps = mini(max_steps, 32) if is_preview else max_steps

	var sdfgi_dict: Dictionary = config.get("sdfgi", {})
	var is_sdfgi: bool = sdfgi_dict.get("enabled", false)
	env.sdfgi_enabled = is_sdfgi
	if is_sdfgi:
		var cascades: int = sdfgi_dict.get("cascades", 2)
		env.sdfgi_cascades = mini(cascades, 2) if is_preview else cascades
		if is_preview:
			env.sdfgi_min_cell_size = 0.5
		else:
			env.sdfgi_min_cell_size = maxf(env.sdfgi_min_cell_size, 1.0)
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		env.sdfgi_energy = 1.0

	var fog_dict: Dictionary = config.get("fog", {})
	var fog_active: bool = fog_dict.get("enabled", false)
	env.volumetric_fog_enabled = fog_active

	if is_preview:
		if fog_active:
			env.volumetric_fog_density = 0.02
			env.volumetric_fog_albedo = Color(0.85, 0.9, 0.95)
	else:
		if fog_active:
			print(
				"VideoApplier: Volumetric fog enabled. Base density: ", env.volumetric_fog_density
			)

	var glow_dict: Dictionary = config.get("glow", {})
	env.glow_enabled = glow_dict.get("enabled", false)
	if env.glow_enabled:
		var glow_hq: bool = glow_dict.get("high_quality", false)
		var glow_bicubic: bool = glow_dict.get("bicubic", false)
		var is_high: bool = glow_hq or glow_bicubic
		env.glow_blend_mode = (
			Environment.GLOW_BLEND_MODE_SOFTLIGHT
			if is_high and not is_preview
			else Environment.GLOW_BLEND_MODE_ADDITIVE
		)


## Toggles diorama viewport between dormant and active isolated render states.
static func set_diorama_active(tree: SceneTree, is_menu_active: bool) -> void:
	print("VideoApplier: Setting diorama active state: ", is_menu_active)
	var diorama_vp: SubViewport = _resolve_diorama_viewport(tree)
	if not is_instance_valid(diorama_vp):
		return

	if is_menu_active:
		diorama_vp.own_world_3d = true
		if diorama_vp.world_3d == null:
			diorama_vp.world_3d = World3D.new()
		diorama_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		diorama_vp.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		diorama_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		diorama_vp.process_mode = Node.PROCESS_MODE_DISABLED


## Resolves [SubViewport] for diorama via group or scene tree fallback.
static func _resolve_diorama_viewport(tree: SceneTree) -> SubViewport:
	var single: Node = NodeQuery.get_single_node_in_group(tree, &"diorama_viewport")
	if single is SubViewport:
		return single as SubViewport
	return tree.root.find_child("DioramaViewport", true, false) as SubViewport


## Retrieves nodes by group if populated, otherwise falls back to tree search.
static func _get_nodes_by_group_or_type(
	tree: SceneTree, group_name: StringName, type_name: String
) -> Array[Node]:
	var nodes: Array[Node] = tree.get_nodes_in_group(group_name)
	if not nodes.is_empty():
		return nodes
	return tree.root.find_children("*", type_name, true, false)
