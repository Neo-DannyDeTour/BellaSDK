## Centralizes visual pipeline, window configuration, shadow atlases, and passes.
class_name VideoApplier
extends RefCounted

## Visual Layer bitmask for isolated preview geometry (3D Render Layer 11).
const PREVIEW_LAYER_MASK: int = 1 << 10

## Visual Layer bitmask for volumetric fog volumes (3D Render Layer 10).
const VOLUMETRIC_LAYER_MASK: int = 1 << 9

## Visual Layer bitmask for primary static world geometry (3D Render Layer 1).
const ENVIRONMENT_LAYER_MASK: int = CollisionLayers.RENDER_MASK_ENVIRONMENT

## Default fallback density when volumetric fog is enabled on a zero-density env.
const DEFAULT_MAIN_FOG_DENSITY: float = 0.015

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
	var raw_driver: Variant = ProjectSettings.get_setting_with_override(
		"rendering/renderer/rendering_method"
	)
	var driver: String = raw_driver if raw_driver is String else ""
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

	var raw_atlas: Variant = config.get("shadow_atlas", 4096)
	var requested_atlas: int = raw_atlas if raw_atlas is int else 4096
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
	var raw_filter_mode: Variant = config.get("texture_filter", 2)
	var filter_mode: int = raw_filter_mode if raw_filter_mode is int else 2
	var f_key: String = "rendering/textures/default_filters/texture_filter_mode"
	if ProjectSettings.get_setting(f_key) != filter_mode:
		ProjectSettings.set_setting(f_key, filter_mode)

	var raw_fsr_scale: Variant = config.get("fsr_scale", 1.0)
	var fsr_scale: float = raw_fsr_scale if raw_fsr_scale is float else 1.0
	var raw_res_scale: Variant = config.get("resolution_scale", 1.0)
	var raw_scale: float = raw_res_scale if raw_res_scale is float else 1.0
	var active_scale: float = fsr_scale if fsr_scale < 1.0 else raw_scale
	var active_scaling_mode: Viewport.Scaling3DMode = (
		Viewport.SCALING_3D_MODE_FSR2 if fsr_scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	)

	var raw_aa_settings: Variant = config.get("aa_settings", {})
	var aa_settings: Dictionary = raw_aa_settings if raw_aa_settings is Dictionary else {}
	var raw_msaa: Variant = aa_settings.get("msaa", Viewport.MSAA_DISABLED)
	var msaa_val: int = raw_msaa if raw_msaa is int else Viewport.MSAA_DISABLED
	var primary_msaa: Viewport.MSAA = msaa_val as Viewport.MSAA

	var raw_taa: Variant = aa_settings.get("taa", false)
	var taa_enabled: bool = raw_taa if raw_taa is bool else false
	var active_taa: bool = (fsr_scale >= 1.0) and taa_enabled

	var raw_fxaa: Variant = aa_settings.get("fxaa", Viewport.SCREEN_SPACE_AA_DISABLED)
	var fxaa_val: int = raw_fxaa if raw_fxaa is int else Viewport.SCREEN_SPACE_AA_DISABLED
	var active_fxaa: Viewport.ScreenSpaceAA = fxaa_val as Viewport.ScreenSpaceAA

	var sdfgi_dict: Dictionary = _resolve_feature_dict(config, "sdfgi", "", VideoConfig.SDFGI_MODES)
	var fog_dict: Dictionary = _resolve_feature_dict(
		config, "fog", "volumetric_fog", VideoConfig.FOG_MODES
	)
	var raw_sdfgi_en: Variant = sdfgi_dict.get("enabled", false)
	var raw_sdfgi_will: Variant = config.get("sdfgi_will_enable", false)
	var is_sdfgi_active: bool = (
		(raw_sdfgi_en if raw_sdfgi_en is bool else false)
		or (raw_sdfgi_will if raw_sdfgi_will is bool else false)
	)
	var raw_fog_en: Variant = fog_dict.get("enabled", false)
	var is_fog_active: bool = raw_fog_en if raw_fog_en is bool else false

	if (is_sdfgi_active or is_fog_active) and primary_msaa != Viewport.MSAA_DISABLED:
		print("VideoApplier: Disabling MSAA to prevent compute fill-rate stalls.")
		primary_msaa = Viewport.MSAA_DISABLED

	var raw_vrs_cfg: Variant = config.get("vrs_mode", Viewport.VRS_DISABLED)
	var vrs_val: int = raw_vrs_cfg if raw_vrs_cfg is int else Viewport.VRS_DISABLED
	var raw_vrs: Viewport.VRSMode = vrs_val as Viewport.VRSMode

	var raw_occ: Variant = config.get("occlusion_culling", true)
	var occ_cull: bool = raw_occ if raw_occ is bool else true
	var raw_lod: Variant = config.get("mesh_lod", 1.0)
	var mesh_lod: float = raw_lod if raw_lod is float else 1.0
	var raw_deband: Variant = config.get("debanding", true)
	var debanding_val: bool = raw_deband if raw_deband is bool else true

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
		if not is_instance_valid(diorama_vp.world_3d):
			diorama_vp.world_3d = World3D.new()
		diorama_vp.own_world_3d = true
		diorama_vp.use_occlusion_culling = occ_cull
		diorama_vp.scaling_3d_mode = active_scaling_mode
		diorama_vp.scaling_3d_scale = active_scale
		diorama_vp.use_taa = active_taa
		diorama_vp.msaa_3d = _clamp_preview_msaa(primary_msaa)
		diorama_vp.screen_space_aa = active_fxaa
		diorama_vp.use_debanding = debanding_val
		diorama_vp.mesh_lod_threshold = mesh_lod
		var raw_dio_atlas: Variant = config.get("shadow_atlas", 4096)
		var dio_atlas_req: int = raw_dio_atlas if raw_dio_atlas is int else 4096
		var requested_atlas: int = mini(dio_atlas_req, 1024)
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
	var raw_dyn: Variant = config.get("dynamic_light_shadows", true)
	var enable_dyn: bool = raw_dyn if raw_dyn is bool else true
	var raw_f_key: Variant = config.get("shadow_filter", "Soft Medium")
	var f_key: String = raw_f_key if raw_f_key is String else "Soft Medium"
	var raw_filter_mode: Variant = VideoConfig.SHADOW_FILTER_MODES.get(
		f_key, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	)
	var filter_val: int = (
		raw_filter_mode if raw_filter_mode is int else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	)
	var filter_mode: RenderingServer.ShadowQuality = filter_val as RenderingServer.ShadowQuality

	var raw_d_dist: Variant = config.get("directional_shadow_distance", 64.0)
	var d_dist: float = raw_d_dist if raw_d_dist is float else 64.0
	var raw_p_dist: Variant = config.get("positional_shadow_distance", 24.0)
	var p_dist: float = raw_p_dist if raw_p_dist is float else 24.0
	var preview_mask: int = PREVIEW_LAYER_MASK | VOLUMETRIC_LAYER_MASK
	var main_light_mask: int = ENVIRONMENT_LAYER_MASK | (1 << 1) | (1 << 2) | VOLUMETRIC_LAYER_MASK

	RenderingServer.positional_soft_shadow_filter_set_quality(filter_mode)
	RenderingServer.directional_soft_shadow_filter_set_quality(filter_mode)

	var dir_lights: Array[Node] = _get_nodes_by_group_or_type(
		tree, &"lights_directional", "DirectionalLight3D"
	)
	for d_node: Node in dir_lights:
		var d_light: DirectionalLight3D = d_node as DirectionalLight3D
		if is_instance_valid(d_light):
			d_light.shadow_enabled = enable_dyn
			d_light.directional_shadow_max_distance = d_dist
			if d_light.find_parent("DioramaViewport") != null:
				d_light.light_cull_mask = preview_mask
			else:
				d_light.light_cull_mask = main_light_mask
				d_light.shadow_bias = 0.03
				d_light.shadow_normal_bias = 1.5

	var omni_lights: Array[Node] = _get_nodes_by_group_or_type(tree, &"lights_omni", "OmniLight3D")
	var spot_lights: Array[Node] = _get_nodes_by_group_or_type(tree, &"lights_spot", "SpotLight3D")
	var all_pos_lights: Array[Node] = omni_lights + spot_lights

	for node: Node in all_pos_lights:
		var light: Light3D = node as Light3D
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
				light.light_cull_mask = main_light_mask


## Clamps preview viewport MSAA strictly to 2X to maintain 60 FPS headroom.
static func _clamp_preview_msaa(requested_msaa: Viewport.MSAA) -> Viewport.MSAA:
	print("VideoApplier: Clamping preview MSAA to 2X.")
	return mini(requested_msaa, Viewport.MSAA_2X) as Viewport.MSAA


## Configures global SSAO, SSIL, and volumetric fog on [RenderingServer].
static func _apply_rendering_server_qualities(config: Dictionary) -> void:
	print("VideoApplier: Updating RenderingServer graphic quality settings.")
	var ssao_dict: Dictionary = _resolve_feature_dict(config, "ssao", "", VideoConfig.SSAO_MODES)
	if not ssao_dict.is_empty():
		var raw_ssao_q: Variant = ssao_dict.get("quality", 1)
		var ssao_q: int = raw_ssao_q if raw_ssao_q is int else 1
		var raw_ssao_half: Variant = ssao_dict.get("half_size", false)
		var ssao_half: bool = raw_ssao_half if raw_ssao_half is bool else false
		RenderingServer.environment_set_ssao_quality(
			ssao_q as RenderingServer.EnvironmentSSAOQuality, ssao_half, 0.5, 2, 1.0, 50.0
		)

	var ssi_dict: Dictionary = _resolve_feature_dict(config, "ssi", "", VideoConfig.SSI_MODES)
	if not ssi_dict.is_empty():
		var raw_ssi_q: Variant = ssi_dict.get("quality", 1)
		var ssi_q: int = raw_ssi_q if raw_ssi_q is int else 1
		var raw_ssi_half: Variant = ssi_dict.get("half_size", false)
		var ssi_half: bool = raw_ssi_half if raw_ssi_half is bool else false
		RenderingServer.environment_set_ssil_quality(
			ssi_q as RenderingServer.EnvironmentSSILQuality, ssi_half, 0.5, 2, 1.0, 50.0
		)

	var fog_dict: Dictionary = _resolve_feature_dict(
		config, "fog", "volumetric_fog", VideoConfig.FOG_MODES
	)
	if not fog_dict.is_empty():
		var raw_depth: Variant = fog_dict.get("depth", 64)
		var depth: int = raw_depth if raw_depth is int else 64
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
		if not is_instance_valid(diorama_vp.world_3d):
			diorama_vp.world_3d = World3D.new()
		diorama_vp.own_world_3d = true
		var dio_w: World3D = diorama_vp.find_world_3d()
		if is_instance_valid(dio_w):
			if not is_instance_valid(dio_w.environment):
				dio_w.environment = Environment.new()
			diorama_environments.append(dio_w.environment)
		if (
			is_instance_valid(diorama_vp.world_3d)
			and is_instance_valid(diorama_vp.world_3d.environment)
		):
			if diorama_vp.world_3d.environment not in diorama_environments:
				diorama_environments.append(diorama_vp.world_3d.environment)

	var we_nodes: Array[Node] = _get_nodes_by_group_or_type(
		tree, &"world_environments", "WorldEnvironment"
	)
	for node: Node in we_nodes:
		var we: WorldEnvironment = node as WorldEnvironment
		if not is_instance_valid(we) or we.is_in_group("ignore_global_video_settings"):
			continue
		if is_instance_valid(we.environment):
			if is_instance_valid(diorama_vp) and diorama_vp.is_ancestor_of(we):
				if we.environment not in diorama_environments:
					diorama_environments.append(we.environment)
			else:
				if we.environment not in main_environments:
					main_environments.append(we.environment)

	var root_w: World3D = tree.root.find_world_3d()
	if is_instance_valid(root_w) and is_instance_valid(root_w.environment):
		if (
			root_w.environment not in main_environments
			and root_w.environment not in diorama_environments
		):
			main_environments.append(root_w.environment)

	var raw_exp: Variant = config.get("exposure", 1.0)
	var exp_val: float = raw_exp if raw_exp is float else 1.0
	var raw_dof: Variant = config.get("dof_amount", 0.0)
	var dof_amount: float = raw_dof if raw_dof is float else 0.0
	var is_dof_active: bool = dof_amount > 0.005

	RenderingServer.gi_set_use_half_resolution(true)

	for env: Environment in main_environments:
		_populate_environment_values(env, config, exp_val, false)

	for dio_env: Environment in diorama_environments:
		_populate_environment_values(dio_env, config, exp_val, true)

	var active_cams: Array[Node] = _get_nodes_by_group_or_type(tree, &"cameras", "Camera3D")
	for c_node: Node in active_cams:
		var cam: Camera3D = c_node as Camera3D
		if not is_instance_valid(cam):
			continue

		if is_instance_valid(cam.environment):
			var is_cam_preview: bool = (
				is_instance_valid(diorama_vp) and diorama_vp.is_ancestor_of(cam)
			)
			_populate_environment_values(cam.environment, config, exp_val, is_cam_preview)

		if not is_instance_valid(cam.attributes):
			var new_attr: CameraAttributesPractical = CameraAttributesPractical.new()
			new_attr.dof_blur_far_distance = 6.0
			new_attr.dof_blur_far_transition = 8.0
			cam.attributes = new_attr

		if cam.attributes is CameraAttributesPractical:
			var cam_attr: CameraAttributesPractical = cam.attributes as CameraAttributesPractical
			if cam_attr.dof_blur_far_enabled != is_dof_active:
				cam_attr.dof_blur_far_enabled = is_dof_active
			if not is_equal_approx(cam_attr.dof_blur_amount, dof_amount):
				cam_attr.dof_blur_amount = dof_amount

	var raw_mb: Variant = config.get("motion_blur", 0.0)
	var mb_factor: float = raw_mb if raw_mb is float else 0.0
	for c_node: Node in active_cams:
		if c_node is ExtendedCamera3D:
			(c_node as ExtendedCamera3D).set_motion_blur_strength(mb_factor)


## Populates [Environment] properties respecting scene native fog and SDFGI.
static func _populate_environment_values(
	env: Environment, config: Dictionary, exposure: float, is_preview: bool
) -> void:
	print("VideoApplier: Populating environment settings. Preview: ", is_preview)
	env.tonemap_exposure = exposure

	var raw_tonemap_key: Variant = config.get("tonemap_key", "Filmic")
	var tonemap_key: String = raw_tonemap_key if raw_tonemap_key is String else "Filmic"
	if VideoConfig.TONEMAP_MODES.has(tonemap_key):
		var raw_tm_mode: Variant = VideoConfig.TONEMAP_MODES[tonemap_key]
		if raw_tm_mode is int:
			var tm_val: int = raw_tm_mode
			env.tonemap_mode = tm_val as Environment.ToneMapper

	var ssao_dict: Dictionary = _resolve_feature_dict(config, "ssao", "", VideoConfig.SSAO_MODES)
	var raw_ssao_en: Variant = ssao_dict.get("enabled", false)
	env.ssao_enabled = raw_ssao_en if raw_ssao_en is bool else false

	var ssi_dict: Dictionary = _resolve_feature_dict(config, "ssi", "", VideoConfig.SSI_MODES)
	var raw_ssi_en: Variant = ssi_dict.get("enabled", false)
	env.ssil_enabled = raw_ssi_en if raw_ssi_en is bool else false

	var ssr_dict: Dictionary = _resolve_feature_dict(config, "ssr", "", VideoConfig.SSR_MODES)
	var raw_ssr_en: Variant = ssr_dict.get("enabled", false)
	env.ssr_enabled = raw_ssr_en if raw_ssr_en is bool else false
	if env.ssr_enabled:
		var raw_steps: Variant = ssr_dict.get("steps", 64)
		var max_steps: int = raw_steps if raw_steps is int else 64
		env.ssr_max_steps = mini(max_steps, 32) if is_preview else max_steps

	var sdfgi_dict: Dictionary = _resolve_feature_dict(config, "sdfgi", "", VideoConfig.SDFGI_MODES)
	var raw_sdfgi_en: Variant = sdfgi_dict.get("enabled", false)
	var is_sdfgi: bool = raw_sdfgi_en if raw_sdfgi_en is bool else false
	var raw_will_sdfgi: Variant = config.get("sdfgi_will_enable", false)
	var will_enable_sdfgi: bool = raw_will_sdfgi if raw_will_sdfgi is bool else false
	if is_sdfgi or will_enable_sdfgi:
		var raw_cascades: Variant = sdfgi_dict.get("cascades", 2)
		var cascades: int = raw_cascades if raw_cascades is int else 2
		env.sdfgi_cascades = mini(cascades, 2) if is_preview else cascades
		if is_preview:
			env.sdfgi_min_cell_size = 0.5
		else:
			env.sdfgi_min_cell_size = maxf(env.sdfgi_min_cell_size, 1.0)
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		env.sdfgi_energy = 1.0
	env.sdfgi_enabled = is_sdfgi

	var fog_dict: Dictionary = _resolve_feature_dict(
		config, "fog", "volumetric_fog", VideoConfig.FOG_MODES
	)
	var raw_fog_en: Variant = fog_dict.get("enabled", false)
	var fog_active: bool = raw_fog_en if raw_fog_en is bool else false
	env.volumetric_fog_enabled = fog_active

	if is_preview:
		if fog_active:
			env.volumetric_fog_density = 0.02
			env.volumetric_fog_albedo = Color(0.85, 0.9, 0.95)
	else:
		if fog_active:
			if env.volumetric_fog_density <= 0.0001:
				env.volumetric_fog_density = DEFAULT_MAIN_FOG_DENSITY
			print(
				"VideoApplier: Volumetric fog enabled. Base density: ", env.volumetric_fog_density
			)

	var glow_dict: Dictionary = _resolve_feature_dict(config, "glow", "", VideoConfig.GLOW_MODES)
	var raw_glow_en: Variant = glow_dict.get("enabled", false)
	env.glow_enabled = raw_glow_en if raw_glow_en is bool else false
	if env.glow_enabled:
		var raw_glow_hq: Variant = glow_dict.get("high_quality", false)
		var glow_hq: bool = raw_glow_hq if raw_glow_hq is bool else false
		var raw_glow_bicubic: Variant = glow_dict.get("bicubic", false)
		var glow_bicubic: bool = raw_glow_bicubic if raw_glow_bicubic is bool else false
		var is_high: bool = glow_hq or glow_bicubic
		env.glow_blend_mode = (
			Environment.GLOW_BLEND_MODE_SOFTLIGHT
			if is_high and not is_preview
			else Environment.GLOW_BLEND_MODE_ADDITIVE
		)


## Resolves a feature configuration dictionary whether passed as Dict or String.
static func _resolve_feature_dict(
	config: Dictionary, primary_key: String, alt_key: String, mode_map: Dictionary
) -> Dictionary:
	var raw: Variant = config.get(primary_key, null)
	if raw == null and not alt_key.is_empty():
		raw = config.get(alt_key, null)
	if raw is Dictionary:
		return raw
	if raw is String:
		var lookup: Variant = mode_map.get(raw, {})
		if lookup is Dictionary:
			return lookup
	if raw is bool:
		var enabled_flag: bool = raw
		return {"enabled": enabled_flag}
	return {}


## Toggles diorama viewport between dormant and active isolated render states.
static func set_diorama_active(tree: SceneTree, is_menu_active: bool) -> void:
	print("VideoApplier: Setting diorama active state: ", is_menu_active)
	var diorama_vp: SubViewport = _resolve_diorama_viewport(tree)
	if not is_instance_valid(diorama_vp):
		return

	if is_menu_active:
		if not is_instance_valid(diorama_vp.world_3d):
			diorama_vp.world_3d = World3D.new()
		diorama_vp.own_world_3d = true
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


## Retrieves all matching nodes by combining group registration and tree search.
static func _get_nodes_by_group_or_type(
	tree: SceneTree, group_name: StringName, type_name: String
) -> Array[Node]:
	var combined: Array[Node] = []
	var group_nodes: Array[Node] = tree.get_nodes_in_group(group_name)
	for g_node: Node in group_nodes:
		if is_instance_valid(g_node) and g_node not in combined:
			combined.append(g_node)

	var found_nodes: Array[Node] = tree.root.find_children("*", type_name, true, false)
	for f_node: Node in found_nodes:
		if is_instance_valid(f_node) and f_node not in combined:
			combined.append(f_node)

	return combined
