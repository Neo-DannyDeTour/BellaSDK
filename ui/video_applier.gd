## Centralizes visual pipeline, window configuration, shadow atlases, and passes.
class_name VideoApplier
extends RefCounted

## Visual Layer bitmask for isolated preview geometry (3D Render Layer 11).
const PREVIEW_LAYER_MASK: int = 1 << 10
## Visual Layer bitmask for primary static world geometry (3D Render Layer 1).
const ENVIRONMENT_LAYER_MASK: int = 1 << 0

## Cached density texture instance shared across all viewports using VRS.
static var _cached_vrs_texture: ImageTexture = null
## Cached dictionary of active pipeline configuration to avoid redundant work.
static var _last_applied_config: Dictionary = {}
## Cached volumetric fog depth slice count to avoid pipeline rebuild stalls.
static var _cached_fog_depth: int = -1


## Updates the application display mode, screen assignment, and dimensions.
static func apply_window_settings(
	window: Window, mode: DisplayServer.WindowMode, screen_idx: int, resolution: Vector2i
) -> void:
	print("VideoApplier: Applying window and display settings.")
	if window.current_screen != screen_idx:
		window.current_screen = screen_idx

	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)

	if window.content_scale_size != resolution:
		window.content_scale_size = resolution

	if not window.is_embedded() and window.mode == Window.MODE_WINDOWED:
		if window.size != resolution:
			window.size = resolution


## Configures global engine limits including VSync mode and max framerate cap.
static func apply_engine_limits(vsync_mode: DisplayServer.VSyncMode, fps_limit: int) -> void:
	print("VideoApplier: Applying engine limits. FPS: ", fps_limit)
	if Engine.max_fps != fps_limit:
		Engine.max_fps = fps_limit

	if DisplayServer.window_get_vsync_mode() != vsync_mode:
		DisplayServer.window_set_vsync_mode(vsync_mode)


## Sets texture anisotropic filtering level in engine [ProjectSettings].
static func apply_anisotropy(level: int) -> void:
	print("VideoApplier: Setting anisotropic filtering level: ", level)
	var key: String = "rendering/textures/default_filters/anisotropic_filtering_level"
	var cur: Variant = ProjectSettings.get_setting(key)
	if cur == null or int(cur) != level:
		ProjectSettings.set_setting(key, level)


## Verifies whether the active GPU backend and graphics driver support VRS.
static func is_vrs_supported() -> bool:
	print("VideoApplier: Verifying VRS hardware and rendering driver support.")
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if not is_instance_valid(rd):
		return false
	var driver: String = ProjectSettings.get_setting_with_override(
		"rendering/renderer/rendering_method"
	)
	if driver == "gl_compatibility":
		return false
	return true


## Applies rendering parameters across the main viewport and preview subviewport.
static func apply_viewport_pipeline(
	tree: SceneTree, main_viewport: Viewport, config: Dictionary
) -> void:
	print("VideoApplier: Synchronizing rendering pipeline across viewports.")
	_last_applied_config = config.duplicate(true)

	print("VideoApplier: Synchronizing rendering pipeline across viewports.")
	var target_viewports: Array[Viewport] = [main_viewport]
	var diorama_vp: SubViewport = (
		tree.root.find_child("DioramaViewport", true, false) as SubViewport
	)
	if is_instance_valid(diorama_vp):
		if not diorama_vp.own_world_3d:
			print("VideoApplier: Isolating DioramaViewport with own_world_3d.")
			diorama_vp.own_world_3d = true
		if diorama_vp not in target_viewports:
			target_viewports.append(diorama_vp)

	_apply_rendering_server_qualities(config)
	_apply_light_shadows(tree, config)

	var filter_mode: int = config.get("texture_filter", 2) as int
	var f_key: String = "rendering/textures/default_filters/texture_filter_mode"
	if ProjectSettings.get_setting(f_key) != filter_mode:
		ProjectSettings.set_setting(f_key, filter_mode)

	var fsr_scale: float = config.get("fsr_scale", 1.0) as float
	var raw_scale: float = config.get("resolution_scale", 1.0) as float
	var aa_settings: Dictionary = config.get("aa_settings", {}) as Dictionary
	var primary_msaa: Viewport.MSAA = (
		aa_settings.get("msaa", Viewport.MSAA_DISABLED) as Viewport.MSAA
	)

	var raw_vrs: Viewport.VRSMode = (
		config.get("vrs_mode", Viewport.VRS_DISABLED) as Viewport.VRSMode
	)
	var occ_cull: bool = config.get("occlusion_culling", true) as bool

	var can_vrs: bool = is_vrs_supported()
	if not can_vrs:
		raw_vrs = Viewport.VRS_DISABLED

	if raw_vrs == Viewport.VRS_TEXTURE and not is_instance_valid(_cached_vrs_texture):
		_cached_vrs_texture = VrsTextureGenerator.create_radial_density_map()

	for vp: Viewport in target_viewports:
		var is_diorama: bool = vp is SubViewport
		vp.canvas_item_default_texture_filter = (
			filter_mode as Viewport.DefaultCanvasItemTextureFilter
		)
		if vp.use_occlusion_culling != (occ_cull if not is_diorama else false):
			vp.use_occlusion_culling = occ_cull if not is_diorama else false

		if raw_vrs == Viewport.VRS_TEXTURE and is_instance_valid(_cached_vrs_texture):
			if vp.vrs_texture != _cached_vrs_texture:
				vp.vrs_texture = _cached_vrs_texture
			if vp.vrs_mode != Viewport.VRS_TEXTURE:
				vp.vrs_mode = Viewport.VRS_TEXTURE
		else:
			if vp.vrs_mode != Viewport.VRS_DISABLED:
				vp.vrs_mode = Viewport.VRS_DISABLED
			if vp.vrs_texture != null:
				vp.vrs_texture = null

		if fsr_scale < 1.0 and not is_diorama:
			if vp.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			if not is_equal_approx(vp.scaling_3d_scale, fsr_scale):
				vp.scaling_3d_scale = fsr_scale
			if vp.use_taa:
				vp.use_taa = false
		else:
			if vp.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			var target_scale: float = raw_scale if not is_diorama else 1.0
			if not is_equal_approx(vp.scaling_3d_scale, target_scale):
				vp.scaling_3d_scale = target_scale
			var target_taa: bool = (
				(aa_settings.get("taa", false) as bool) if not is_diorama else false
			)
			if vp.use_taa != target_taa:
				vp.use_taa = target_taa

		var target_msaa: Viewport.MSAA = (
			_clamp_preview_msaa(primary_msaa) if is_diorama else primary_msaa
		)
		if vp.msaa_3d != target_msaa:
			vp.msaa_3d = target_msaa

		var target_fxaa: Viewport.ScreenSpaceAA = (
			aa_settings.get("fxaa", Viewport.SCREEN_SPACE_AA_DISABLED) as Viewport.ScreenSpaceAA
		)
		if vp.screen_space_aa != target_fxaa:
			vp.screen_space_aa = target_fxaa

		var target_deband: bool = config.get("debanding", true) as bool
		if vp.use_debanding != target_deband:
			vp.use_debanding = target_deband

		var target_lod: float = config.get("mesh_lod", 1.0) as float
		if not is_equal_approx(vp.mesh_lod_threshold, target_lod):
			vp.mesh_lod_threshold = target_lod

		if is_diorama:
			var dio_atlas: int = mini(config.get("shadow_atlas", 2048) as int, 512)
			if vp.positional_shadow_atlas_size != dio_atlas:
				vp.positional_shadow_atlas_size = dio_atlas
		else:
			var main_atlas: int = maxi(config.get("shadow_atlas", 4096) as int, 2048)
			if vp.positional_shadow_atlas_size != main_atlas:
				vp.positional_shadow_atlas_size = main_atlas
			vp.positional_shadow_atlas_16_bits = true
			vp.set_positional_shadow_atlas_quadrant_subdiv(
				0, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
			)
			vp.set_positional_shadow_atlas_quadrant_subdiv(
				1, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
			)
			vp.set_positional_shadow_atlas_quadrant_subdiv(
				2, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16
			)
			vp.set_positional_shadow_atlas_quadrant_subdiv(
				3, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64
			)

	_apply_environment_and_materials(tree, config)


## Synchronizes light shadow masks, atlas sizes, biases, and filter qualities.
static func _apply_light_shadows(tree: SceneTree, config: Dictionary) -> void:
	print("VideoApplier: Synchronizing light shadows and filter qualities.")
	var enable_dyn: bool = config.get("dynamic_light_shadows", true) as bool
	var f_key: String = config.get("shadow_filter", "Soft Medium") as String
	var filter_mode: RenderingServer.ShadowQuality = (
		VideoConfig.SHADOW_FILTER_MODES.get(f_key, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		as RenderingServer.ShadowQuality
	)
	var d_dist: float = config.get("directional_shadow_distance", 64.0) as float
	var preview_and_vol_mask: int = PREVIEW_LAYER_MASK | (1 << 9)

	RenderingServer.positional_soft_shadow_filter_set_quality(filter_mode)
	RenderingServer.directional_soft_shadow_filter_set_quality(filter_mode)

	var dir_lights: Array[Node] = tree.root.find_children("*", "DirectionalLight3D", true, false)
	for d_node: Node in dir_lights:
		var d_light: DirectionalLight3D = d_node as DirectionalLight3D
		if is_instance_valid(d_light):
			d_light.shadow_enabled = enable_dyn
			if d_light.find_parent("DioramaViewport") != null:
				d_light.directional_shadow_max_distance = minf(d_dist, 16.0)
				d_light.light_cull_mask = preview_and_vol_mask
			else:
				d_light.directional_shadow_max_distance = d_dist
				d_light.light_cull_mask |= ENVIRONMENT_LAYER_MASK
				d_light.shadow_bias = 0.03
				d_light.shadow_normal_bias = 1.5

	var dynamic_nodes: Array[Node] = tree.get_nodes_in_group("dynamic_shadow_casters")
	for node: Node in dynamic_nodes:
		var light: Light3D = node as Light3D
		if is_instance_valid(light):
			light.shadow_enabled = enable_dyn
			if light.find_parent("DioramaViewport") != null:
				light.light_cull_mask = preview_and_vol_mask
			else:
				light.light_cull_mask |= ENVIRONMENT_LAYER_MASK
				light.shadow_bias = 0.03
				light.shadow_normal_bias = 1.5

	var diorama_vp: SubViewport = (
		tree.root.find_child("DioramaViewport", true, false) as SubViewport
	)
	if is_instance_valid(diorama_vp):
		var dio_lights: Array[Node] = diorama_vp.find_children("*", "Light3D", true, false)
		for l_node: Node in dio_lights:
			if l_node is DirectionalLight3D:
				continue
			var l3d: Light3D = l_node as Light3D
			if is_instance_valid(l3d):
				l3d.shadow_enabled = enable_dyn
				l3d.light_cull_mask = preview_and_vol_mask

		var sdfgi_dict: Dictionary = config.get("sdfgi", {}) as Dictionary
		var sdfgi_on: bool = sdfgi_dict.get("enabled", false) as bool
		var vgis: Array[Node] = diorama_vp.find_children("*", "VoxelGI", true, false)
		for v_node: Node in vgis:
			var vgi: VoxelGI = v_node as VoxelGI
			if is_instance_valid(vgi):
				vgi.visible = not sdfgi_on


## Clamps preview viewport MSAA strictly to 2X to maintain 60 FPS headroom.
static func _clamp_preview_msaa(requested_msaa: Viewport.MSAA) -> Viewport.MSAA:
	print("VideoApplier: Clamping preview viewport MSAA.")
	if requested_msaa > Viewport.MSAA_2X:
		return Viewport.MSAA_2X
	return requested_msaa


## Configures global SSAO, SSIL, and volumetric fog on [RenderingServer].
static func _apply_rendering_server_qualities(config: Dictionary) -> void:
	print("VideoApplier: Applying global RenderingServer quality steps.")
	var ssao_dict: Dictionary = config.get("ssao", {}) as Dictionary
	if not ssao_dict.is_empty():
		var ssao_q: int = ssao_dict.get("quality", 1) as int
		var ssao_half: bool = ssao_dict.get("half_size", false) as bool
		RenderingServer.environment_set_ssao_quality(
			ssao_q as RenderingServer.EnvironmentSSAOQuality, ssao_half, 0.5, 2, 1.0, 50.0
		)

	var ssi_dict: Dictionary = config.get("ssi", {}) as Dictionary
	if not ssi_dict.is_empty():
		var ssi_q: int = ssi_dict.get("quality", 1) as int
		var ssi_half: bool = ssi_dict.get("half_size", false) as bool
		RenderingServer.environment_set_ssil_quality(
			ssi_q as RenderingServer.EnvironmentSSILQuality, ssi_half, 0.5, 2, 1.0, 50.0
		)

	var fog_dict: Dictionary = config.get("fog", {}) as Dictionary
	if not fog_dict.is_empty():
		var depth: int = fog_dict.get("depth", 64) as int
		if _cached_fog_depth != depth:
			_cached_fog_depth = depth
			RenderingServer.environment_set_volumetric_fog_volume_size(64, depth)


## Synchronizes environment tonemapping, lighting features, and cameras.
static func _apply_environment_and_materials(tree: SceneTree, config: Dictionary) -> void:
	print("VideoApplier: Applying environment features across scene tree.")
	var main_environments: Array[Environment] = []
	var diorama_environments: Array[Environment] = []

	var diorama_vp: SubViewport = (
		tree.root.find_child("DioramaViewport", true, false) as SubViewport
	)

	var we_nodes: Array[Node] = tree.root.find_children("*", "WorldEnvironment", true, false)
	for node: Node in we_nodes:
		var we: WorldEnvironment = node as WorldEnvironment
		if we.is_in_group("ignore_global_video_settings"):
			continue
		if is_instance_valid(we) and is_instance_valid(we.environment):
			if is_instance_valid(diorama_vp) and diorama_vp.is_ancestor_of(we):
				if we.environment not in diorama_environments:
					diorama_environments.append(we.environment)
			else:
				if we.environment not in main_environments:
					main_environments.append(we.environment)

	if is_instance_valid(diorama_vp) and diorama_vp.find_world_3d():
		var dio_w: World3D = diorama_vp.find_world_3d()
		if is_instance_valid(dio_w.environment) and dio_w.environment not in diorama_environments:
			diorama_environments.append(dio_w.environment)
		elif (
			is_instance_valid(dio_w.fallback_environment)
			and dio_w.fallback_environment not in diorama_environments
		):
			diorama_environments.append(dio_w.fallback_environment)

	var active_cams: Array[Node] = tree.root.find_children("*", "Camera3D", true, false)
	for c_node: Node in active_cams:
		var cam: Camera3D = c_node as Camera3D
		if is_instance_valid(cam) and is_instance_valid(cam.environment):
			if is_instance_valid(diorama_vp) and diorama_vp.is_ancestor_of(cam):
				if cam.environment not in diorama_environments:
					diorama_environments.append(cam.environment)
			else:
				if cam.environment not in main_environments:
					main_environments.append(cam.environment)

	var exp_val: float = config.get("exposure", 1.0) as float
	var dof_amount: float = config.get("dof_amount", 0.0) as float
	var is_dof_active: bool = dof_amount > 0.01

	for env: Environment in main_environments:
		_populate_environment_values(env, config, exp_val, false)

	for dio_env: Environment in diorama_environments:
		_populate_environment_values(dio_env, config, exp_val, true)

	for node: Node in we_nodes:
		var we: WorldEnvironment = node as WorldEnvironment
		if is_instance_valid(we) and is_instance_valid(we.camera_attributes):
			if we.camera_attributes is CameraAttributesPractical:
				var attr: CameraAttributesPractical = (
					we.camera_attributes as CameraAttributesPractical
				)
				if attr.dof_blur_far_enabled != is_dof_active:
					attr.dof_blur_far_enabled = is_dof_active
				if attr.dof_blur_near_enabled != is_dof_active:
					attr.dof_blur_near_enabled = is_dof_active
				var target_dof: float = dof_amount if is_dof_active else 0.0
				if not is_equal_approx(attr.dof_blur_amount, target_dof):
					attr.dof_blur_amount = target_dof

	for c_node: Node in active_cams:
		var cam: Camera3D = c_node as Camera3D
		if is_instance_valid(cam) and is_instance_valid(cam.attributes):
			if cam.attributes is CameraAttributesPractical:
				var cam_attr: CameraAttributesPractical = (
					cam.attributes as CameraAttributesPractical
				)
				if cam_attr.dof_blur_far_enabled != is_dof_active:
					cam_attr.dof_blur_far_enabled = is_dof_active
				if cam_attr.dof_blur_near_enabled != is_dof_active:
					cam_attr.dof_blur_near_enabled = is_dof_active
				var target_dof: float = dof_amount if is_dof_active else 0.0
				if not is_equal_approx(cam_attr.dof_blur_amount, target_dof):
					cam_attr.dof_blur_amount = target_dof

	var mb_factor: float = config.get("motion_blur", 0.0) as float
	for c_node: Node in active_cams:
		if c_node is ExtendedCamera3D:
			var ext_cam: ExtendedCamera3D = c_node as ExtendedCamera3D
			ext_cam.set_motion_blur_strength(mb_factor)


## Populates target [Environment] resource properties clamped by preview context.
static func _populate_environment_values(
	env: Environment, config: Dictionary, exposure: float, is_preview: bool
) -> void:
	print("VideoApplier: Populating environment values for preview: ", is_preview)
	env.tonemap_exposure = exposure

	var ssao_dict: Dictionary = config.get("ssao", {}) as Dictionary
	env.ssao_enabled = ssao_dict.get("enabled", false) as bool

	var ssi_dict: Dictionary = config.get("ssi", {}) as Dictionary
	env.ssil_enabled = ssi_dict.get("enabled", false) as bool

	var ssr_dict: Dictionary = config.get("ssr", {}) as Dictionary
	env.ssr_enabled = ssr_dict.get("enabled", false) as bool
	if env.ssr_enabled:
		var max_steps: int = ssr_dict.get("steps", 64) as int
		env.ssr_max_steps = mini(max_steps, 32) if is_preview else max_steps

	var sdfgi_dict: Dictionary = config.get("sdfgi", {}) as Dictionary
	env.sdfgi_enabled = sdfgi_dict.get("enabled", false) as bool
	if env.sdfgi_enabled:
		var cascades: int = sdfgi_dict.get("cascades", 4) as int
		env.sdfgi_cascades = mini(cascades, 2) if is_preview else cascades

	var fog_dict: Dictionary = config.get("fog", {}) as Dictionary
	env.volumetric_fog_enabled = fog_dict.get("enabled", false) as bool

	var glow_dict: Dictionary = config.get("glow", {}) as Dictionary
	env.glow_enabled = glow_dict.get("enabled", false) as bool
	if env.glow_enabled:
		var is_high: bool = (
			glow_dict.get("high_quality", false) as bool or glow_dict.get("bicubic", false) as bool
		)
		env.glow_blend_mode = (
			Environment.GLOW_BLEND_MODE_SOFTLIGHT
			if is_high and not is_preview
			else Environment.GLOW_BLEND_MODE_ADDITIVE
		)


## Toggles the diorama viewport between dormant and active render states.
## [param tree] The active [SceneTree].
## [param is_menu_active] True if the menu is open, false during gameplay.
static func set_diorama_active(tree: SceneTree, is_menu_active: bool) -> void:
	print("VideoApplier: Setting diorama active state: ", is_menu_active)
	var diorama_vp: SubViewport = (
		tree.root.find_child("DioramaViewport", true, false) as SubViewport
	)
	if not is_instance_valid(diorama_vp):
		return

	if is_menu_active:
		if not diorama_vp.own_world_3d:
			diorama_vp.own_world_3d = true
		diorama_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		diorama_vp.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		diorama_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		diorama_vp.process_mode = Node.PROCESS_MODE_DISABLED
