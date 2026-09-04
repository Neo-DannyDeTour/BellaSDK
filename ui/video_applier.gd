## Applies visual settings to display windows, viewports, materials, and environments.
class_name VideoApplier
extends RefCounted


## Updates the application display mode, screen assignment, and dimensions.
## [param window] Window reference to mutate.
## [param mode] Target window mode enum.
## [param screen_idx] Target monitor display index.
## [param resolution] Target resolution pixel dimensions.
static func apply_window_settings(
	window: Window, mode: DisplayServer.WindowMode, screen_idx: int, resolution: Vector2i
) -> void:
	print("VideoApplier: Applying window and display settings.")
	window.current_screen = screen_idx
	DisplayServer.window_set_mode(mode)
	window.content_scale_size = resolution
	if not window.is_embedded() and window.mode == Window.MODE_WINDOWED:
		window.size = resolution


## Configures global engine limits including VSync and maximum framerate cap.
## [param vsync_mode] VSync mode to assign.
## [param fps_limit] Maximum FPS integer limit.
static func apply_engine_limits(vsync_mode: DisplayServer.VSyncMode, fps_limit: int) -> void:
	print("VideoApplier: Applying engine limits. FPS: ", fps_limit)
	Engine.max_fps = fps_limit
	DisplayServer.window_set_vsync_mode(vsync_mode)


## Sets texture anisotropic filtering level in ProjectSettings.
## [param level] Anisotropic filtering level integer.
static func apply_anisotropy(level: int) -> void:
	print("VideoApplier: Setting anisotropic filtering level: ", level)
	ProjectSettings.set_setting(
		"rendering/textures/default_filters/anisotropic_filtering_level", level
	)


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

	var fsr_scale: float = config.get("fsr_scale", 1.0) as float
	var aa_settings: Dictionary = config.get("aa_settings", {}) as Dictionary
	var primary_msaa: Viewport.MSAA = (
		aa_settings.get("msaa", Viewport.MSAA_DISABLED) as Viewport.MSAA
	)

	for vp: Viewport in target_viewports:
		if fsr_scale >= 1.0:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.use_taa = false

		vp.scaling_3d_scale = fsr_scale
		vp.msaa_3d = (_clamp_preview_msaa(primary_msaa) if vp is SubViewport else primary_msaa)
		vp.screen_space_aa = (
			aa_settings.get("fxaa", Viewport.SCREEN_SPACE_AA_DISABLED) as Viewport.ScreenSpaceAA
		)
		vp.use_debanding = config.get("debanding", true) as bool
		vp.mesh_lod_threshold = config.get("mesh_lod", 1.0) as float

		if vp.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2:
			vp.use_taa = aa_settings.get("taa", false) as bool

		vp.positional_shadow_atlas_size = (config.get("shadow_atlas", 2048) as int)
		_apply_environment_and_materials(vp, config)


## Clamps high MSAA modes for subviewports to ensure 60 FPS performance headroom.
## [param requested_msaa] Requested [enum Viewport.MSAA].
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
		RenderingServer.environment_set_volumetric_fog_volume_size(depth, depth)


## Synchronizes environment tonemapping, lighting features, and debug overlays.
## [param vp] Target [Viewport] to inspect.
## [param config] Dictionary holding environment flags and tonemapper key.
static func _apply_environment_and_materials(vp: Viewport, config: Dictionary) -> void:
	print("VideoApplier: Applying environment features to viewport.")
	var env: Environment = null
	if vp.find_world_3d():
		var world: World3D = vp.find_world_3d()
		if is_instance_valid(world.environment):
			env = world.environment
		elif is_instance_valid(world.fallback_environment):
			env = world.fallback_environment

	var tonemap_key: String = config.get("tonemap_key", "Filmic") as String
	var is_agx: bool = tonemap_key == "AgX"
	var is_agx_punchy: bool = tonemap_key == "AgX (Punchy)"

	if is_instance_valid(env):
		if is_agx or is_agx_punchy:
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		else:
			match tonemap_key:
				"Linear":
					env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
				"Reinhard":
					env.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
				"Filmic":
					env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
				"ACES":
					env.tonemap_mode = Environment.TONE_MAPPER_ACES

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

	var vision_mesh: MeshInstance3D = (
		vp.find_child("VisionAssistMesh", true, false) as MeshInstance3D
	)
	if is_instance_valid(vision_mesh):
		var mat: ShaderMaterial = vision_mesh.get_surface_override_material(0) as ShaderMaterial
		if not is_instance_valid(mat):
			mat = vision_mesh.material_override as ShaderMaterial

		if is_instance_valid(mat):
			var is_va_enabled: bool = (
				GlobalSettings.get_setting("VisionAssist", "enabled", false) as bool
			)
			if is_va_enabled:
				var va_mode: int = GlobalSettings.get_setting("VisionAssist", "mode", 1) as int
				mat.set_shader_parameter("mode", va_mode)
				vision_mesh.visible = true
			elif is_agx:
				mat.set_shader_parameter("mode", 5)
				vision_mesh.visible = true
			elif is_agx_punchy:
				mat.set_shader_parameter("mode", 6)
				vision_mesh.visible = true
			else:
				mat.set_shader_parameter("mode", 7)
				vision_mesh.visible = false
