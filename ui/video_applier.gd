## Applies visual settings to display windows, viewports, materials, and environments.
class_name VideoApplier
extends RefCounted

## Cached density texture instance shared across all viewports.
static var _cached_vrs_texture: ImageTexture = null


## Updates the application display mode, screen assignment, and dimensions.
## [param window] Target [Window] to mutate.
## [param mode] Target [enum DisplayServer.WindowMode] enum.
## [param screen_idx] Target monitor display index.
## [param resolution] Target resolution pixel dimensions.
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


## Configures global engine limits including VSync and maximum framerate cap.
## [param vsync_mode] [enum DisplayServer.VSyncMode] mode to assign.
## [param fps_limit] Maximum FPS integer limit.
static func apply_engine_limits(vsync_mode: DisplayServer.VSyncMode, fps_limit: int) -> void:
	print("VideoApplier: Applying engine limits. FPS: ", fps_limit)
	if Engine.max_fps != fps_limit:
		Engine.max_fps = fps_limit

	if DisplayServer.window_get_vsync_mode() != vsync_mode:
		DisplayServer.window_set_vsync_mode(vsync_mode)


## Sets texture anisotropic filtering level in [ProjectSettings].
## [param level] Anisotropic filtering level integer.
static func apply_anisotropy(level: int) -> void:
	print("VideoApplier: Setting anisotropic filtering level: ", level)
	var setting_key: String = "rendering/textures/default_filters/anisotropic_filtering_level"
	var current: Variant = ProjectSettings.get_setting(setting_key)
	if current == null or int(current) != level:
		ProjectSettings.set_setting(setting_key, level)


## Checks if the current GPU backend supports VRS.
## [return] True if the GPU can execute VRS pipelines.
static func is_vrs_supported() -> bool:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if not is_instance_valid(rd):
		return false
	var driver: String = ProjectSettings.get_setting_with_override(
		"rendering/renderer/rendering_method"
	)
	if driver == "gl_compatibility":
		return false
	return true


## Applies rendering parameters across the main viewport and preview subviewports.
## [param tree] The active [SceneTree].
## [param main_viewport] The primary root [Viewport].
## [param config] Dictionary holding all active feature parameters.
static func apply_viewport_pipeline(
	tree: SceneTree, main_viewport: Viewport, config: Dictionary
) -> void:
	print("VideoApplier: Synchronizing rendering pipeline across viewports.")
	var target_viewports: Array[Viewport] = [main_viewport]
	var diorama_vp: SubViewport = (
		tree.root.find_child("DioramaViewport", true, false) as SubViewport
	)
	if is_instance_valid(diorama_vp) and diorama_vp not in target_viewports:
		target_viewports.append(diorama_vp)

	_apply_rendering_server_qualities(config)
	_apply_light_shadows(tree, config)

	var filter_mode: int = config.get("texture_filter", 2) as int
	var f_key: String = "rendering/textures/default_filters/texture_filter_mode"
	if ProjectSettings.get_setting(f_key) != filter_mode:
		ProjectSettings.set_setting(f_key, filter_mode)

	for vp: Viewport in target_viewports:
		vp.canvas_item_default_texture_filter = (
			filter_mode as Viewport.DefaultCanvasItemTextureFilter
		)

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
		vp.use_occlusion_culling = occ_cull

		if raw_vrs == Viewport.VRS_TEXTURE and is_instance_valid(_cached_vrs_texture):
			vp.vrs_texture = _cached_vrs_texture
			vp.vrs_mode = Viewport.VRS_TEXTURE
		else:
			vp.vrs_mode = Viewport.VRS_DISABLED
			vp.vrs_texture = null

		if fsr_scale < 1.0:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = fsr_scale
			vp.use_taa = false
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = raw_scale
			vp.use_taa = aa_settings.get("taa", false) as bool

		vp.msaa_3d = (_clamp_preview_msaa(primary_msaa) if vp is SubViewport else primary_msaa)
		vp.screen_space_aa = (
			aa_settings.get("fxaa", Viewport.SCREEN_SPACE_AA_DISABLED) as Viewport.ScreenSpaceAA
		)
		vp.use_debanding = config.get("debanding", true) as bool
		vp.mesh_lod_threshold = config.get("mesh_lod", 1.0) as float
		vp.positional_shadow_atlas_size = (config.get("shadow_atlas", 2048) as int)

	_apply_environment_and_materials(tree, config)


## Controls dynamic spotlights, omni lights, and positional shadow filters.
## [param tree] The active [SceneTree] to query lights from.
## [param config] Dictionary holding dynamic shadow preferences.
static func _apply_light_shadows(tree: SceneTree, config: Dictionary) -> void:
	print("VideoApplier: Synchronizing positional light shadows and filter.")
	var enable_dynamic_shadows: bool = config.get("dynamic_light_shadows", true) as bool
	var filter_key: String = config.get("shadow_filter", "Soft Medium") as String
	var filter_mode: RenderingServer.ShadowQuality = (
		VideoConfig.SHADOW_FILTER_MODES.get(filter_key, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		as RenderingServer.ShadowQuality
	)
	var d_dist: float = config.get("directional_shadow_distance", 64.0) as float

	RenderingServer.positional_soft_shadow_filter_set_quality(filter_mode)

	var dir_lights: Array[Node] = tree.root.find_children("*", "DirectionalLight3D", true, false)
	for d_node: Node in dir_lights:
		var d_light: DirectionalLight3D = d_node as DirectionalLight3D
		if is_instance_valid(d_light):
			d_light.directional_shadow_max_distance = d_dist

	var dynamic_nodes: Array[Node] = tree.get_nodes_in_group("dynamic_shadow_casters")
	if not dynamic_nodes.is_empty():
		for node: Node in dynamic_nodes:
			var light: Light3D = node as Light3D
			if is_instance_valid(light):
				light.shadow_enabled = enable_dynamic_shadows
				light.distance_fade_enabled = false
	else:
		var lights: Array[Node] = tree.root.find_children("*", "Light3D", true, false)
		for node: Node in lights:
			if node is DirectionalLight3D:
				continue
			var light: Light3D = node as Light3D
			if is_instance_valid(light):
				light.shadow_enabled = enable_dynamic_shadows
				light.distance_fade_enabled = false


## Clamps high MSAA modes for subviewports to ensure 60 FPS performance headroom.
## [param requested_msaa] Requested [enum Viewport.MSAA].
## [return] Clamped [enum Viewport.MSAA] value.
static func _clamp_preview_msaa(requested_msaa: Viewport.MSAA) -> Viewport.MSAA:
	print("VideoApplier: Clamping preview viewport MSAA.")
	if requested_msaa > Viewport.MSAA_2X:
		return Viewport.MSAA_2X
	return requested_msaa


## Configures global engine quality passes on [RenderingServer].
## [param config] Dictionary holding effect tier parameters.
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
		var grid_size: int = 64
		RenderingServer.environment_set_volumetric_fog_volume_size(grid_size, depth)


## Synchronizes environment tonemapping, lighting features, and debug overlays.
## [param tree] The active [SceneTree] to query.
## [param config] Dictionary holding environment flags and tonemapper key.
static func _apply_environment_and_materials(tree: SceneTree, config: Dictionary) -> void:
	print("VideoApplier: Applying environment features across scene tree.")
	var environments: Array[Environment] = []

	var we_nodes: Array[Node] = tree.root.find_children("*", "WorldEnvironment", true, false)
	for node: Node in we_nodes:
		var we: WorldEnvironment = node as WorldEnvironment
		if we.is_in_group("ignore_global_video_settings"):
			continue
		if is_instance_valid(we) and is_instance_valid(we.environment):
			if we.environment not in environments:
				environments.append(we.environment)

	if tree.root.find_world_3d():
		var root_w: World3D = tree.root.find_world_3d()
		if is_instance_valid(root_w.environment) and root_w.environment not in environments:
			environments.append(root_w.environment)
		elif (
			is_instance_valid(root_w.fallback_environment)
			and root_w.fallback_environment not in environments
		):
			environments.append(root_w.fallback_environment)

	var diorama_vp: SubViewport = (
		tree.root.find_child("DioramaViewport", true, false) as SubViewport
	)
	if is_instance_valid(diorama_vp) and diorama_vp.find_world_3d():
		var dio_w: World3D = diorama_vp.find_world_3d()
		if is_instance_valid(dio_w.environment) and dio_w.environment not in environments:
			environments.append(dio_w.environment)
		elif (
			is_instance_valid(dio_w.fallback_environment)
			and dio_w.fallback_environment not in environments
		):
			environments.append(dio_w.fallback_environment)

	var exp_val: float = config.get("exposure", 1.0) as float
	var dof_amount: float = config.get("dof_amount", 0.0) as float
	var is_dof_active: bool = dof_amount > 0.005

	for env: Environment in environments:
		env.tonemap_exposure = exp_val

		var ssao_dict: Dictionary = config.get("ssao", {}) as Dictionary
		env.ssao_enabled = ssao_dict.get("enabled", false) as bool

		var ssi_dict: Dictionary = config.get("ssi", {}) as Dictionary
		env.ssil_enabled = ssi_dict.get("enabled", false) as bool

		var ssr_dict: Dictionary = config.get("ssr", {}) as Dictionary
		env.ssr_enabled = ssr_dict.get("enabled", false) as bool
		if env.ssr_enabled:
			env.ssr_max_steps = ssr_dict.get("steps", 64) as int

		var sdfgi_dict: Dictionary = config.get("sdfgi", {}) as Dictionary
		env.sdfgi_enabled = sdfgi_dict.get("enabled", false) as bool
		if env.sdfgi_enabled:
			env.sdfgi_cascades = sdfgi_dict.get("cascades", 4) as int

		var fog_dict: Dictionary = config.get("fog", {}) as Dictionary
		env.volumetric_fog_enabled = fog_dict.get("enabled", false) as bool

		var glow_dict: Dictionary = config.get("glow", {}) as Dictionary
		env.glow_enabled = glow_dict.get("enabled", false) as bool
		if env.glow_enabled:
			var is_high: bool = (
				glow_dict.get("high_quality", false) as bool or glow_dict.get("bicubic", false)
				as bool
			)
			env.glow_blend_mode = (
				Environment.GLOW_BLEND_MODE_SOFTLIGHT
				if is_high
				else Environment.GLOW_BLEND_MODE_ADDITIVE
			)

	for node: Node in we_nodes:
		var we: WorldEnvironment = node as WorldEnvironment
		if is_instance_valid(we) and is_instance_valid(we.camera_attributes):
			if we.camera_attributes is CameraAttributesPractical:
				var attr: CameraAttributesPractical = (
					we.camera_attributes as CameraAttributesPractical
				)
				attr.dof_blur_far_enabled = is_dof_active
				attr.dof_blur_near_enabled = is_dof_active
				attr.dof_blur_amount = dof_amount

	var active_cams: Array[Node] = tree.root.find_children("*", "Camera3D", true, false)
	for c_node: Node in active_cams:
		var cam: Camera3D = c_node as Camera3D
		if is_instance_valid(cam) and is_instance_valid(cam.attributes):
			if cam.attributes is CameraAttributesPractical:
				var cam_attr: CameraAttributesPractical = (
					cam.attributes as CameraAttributesPractical
				)
				cam_attr.dof_blur_far_enabled = is_dof_active
				cam_attr.dof_blur_near_enabled = is_dof_active
				cam_attr.dof_blur_amount = dof_amount

	var motion_blur_factor: float = config.get("motion_blur", 0.0) as float
	for c_node: Node in active_cams:
		if c_node is ExtendedCamera3D:
			var ext_cam: ExtendedCamera3D = c_node as ExtendedCamera3D
			if is_instance_valid(ext_cam._motion_blur_material):
				ext_cam._motion_blur_material.set_shader_parameter(
					"motion_blur_strength", motion_blur_factor
				)
			if is_instance_valid(ext_cam.motion_blur_layer):
				ext_cam.motion_blur_layer.visible = motion_blur_factor > 0.005

	var post_nodes: Array[Node] = tree.root.find_children("*", "ColorRect", true, false)
	for p_node: Node in post_nodes:
		if p_node.material is ShaderMaterial:
			var smat: ShaderMaterial = p_node.material as ShaderMaterial
			smat.set_shader_parameter("motion_blur_strength", motion_blur_factor)
