## Stateless, synchronous graphics applier for window, viewport, and environment passes.
class_name VideoApplier
extends RefCounted

## Visual layer bitmask for isolated preview geometry (3D Render Layer 11).
const PREVIEW_LAYER_MASK: int = 1 << 10

## Visual layer bitmask for volumetric fog volumes (3D Render Layer 10).
const VOLUMETRIC_LAYER_MASK: int = 1 << 9

## Visual layer bitmask for primary static world geometry (3D Render Layer 1).
const ENVIRONMENT_LAYER_MASK: int = 1 << 0

## Default fallback density when volumetric fog is enabled on a zero-density environment.
const DEFAULT_MAIN_FOG_DENSITY: float = 0.015

## Fixed diorama viewport resolution width and height.
const DIORAMA_SIZE: Vector2i = Vector2i(640, 480)

## Fixed diorama shadow atlas size to prevent runtime buffer reallocation stalls.
const DIORAMA_SHADOW_ATLAS_SIZE: int = 1024

## Fixed diorama volumetric fog depth slice count.
const DIORAMA_FOG_DEPTH: int = 64

## Cached radial Variable Rate Shading density texture shared across viewports.
static var _cached_vrs_texture: ImageTexture = null

## Cached volumetric fog depth slice count to avoid redundant server calls.
static var _cached_fog_depth: int = -1


## Applies window display mode, active monitor index, and resolution synchronously.
static func apply_window_settings(
	window: Window, mode: DisplayServer.WindowMode, screen_idx: int, resolution: Vector2i
) -> void:
	if not is_instance_valid(window):
		return
	print("VideoApplier: Applying window settings -> mode: ", mode, " res: ", resolution)

	var screen_count: int = DisplayServer.get_screen_count()
	var valid_screen: int = clampi(screen_idx, 0, maxi(screen_count - 1, 0))
	if window.current_screen != valid_screen:
		window.current_screen = valid_screen

	var target_mode: Window.Mode = mode as Window.Mode
	if window.mode != target_mode:
		window.mode = target_mode

	if window.content_scale_size != resolution:
		window.content_scale_size = resolution

	if not window.is_embedded() and window.mode == Window.MODE_WINDOWED:
		window.borderless = false
		if window.size != resolution:
			window.size = resolution


## Applies VSync mode and framerate cap to [DisplayServer] and [Engine].
static func apply_engine_limits(vsync_mode: DisplayServer.VSyncMode, fps_limit: int) -> void:
	print("VideoApplier: Applying engine limits -> VSync: ", vsync_mode, " FPS: ", fps_limit)
	DisplayServer.window_set_vsync_mode(vsync_mode)
	Engine.max_fps = fps_limit


## Applies anisotropic filtering level to [ProjectSettings].
static func apply_anisotropy(level: int) -> void:
	var key: String = "rendering/textures/default_filters/anisotropic_filtering_level"
	if ProjectSettings.get_setting(key) != level:
		print("VideoApplier: Setting anisotropic filtering level: ", level)
		ProjectSettings.set_setting(key, level)


## Returns true if the active rendering backend supports Variable Rate Shading.
static func is_vrs_supported() -> bool:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if not is_instance_valid(rd):
		return false
	var raw_driver: Variant = ProjectSettings.get_setting_with_override(
		"rendering/renderer/rendering_method"
	)
	var driver: String = raw_driver if raw_driver is String else ""
	return driver != "gl_compatibility"


## Locks the diorama [SubViewport] to fixed buffer sizes and an isolated [World3D].
static func configure_diorama_sandbox(diorama_vp: SubViewport) -> void:
	if not is_instance_valid(diorama_vp):
		return
	print("VideoApplier: Configuring isolated diorama sandbox fixed buffers.")

	if diorama_vp.size != DIORAMA_SIZE:
		diorama_vp.size = DIORAMA_SIZE

	if not is_instance_valid(diorama_vp.world_3d):
		diorama_vp.world_3d = World3D.new()
	diorama_vp.own_world_3d = true

	if not is_instance_valid(diorama_vp.world_3d.environment):
		var dio_env: Environment = Environment.new()
		dio_env.background_mode = Environment.BG_COLOR
		dio_env.background_color = Color(0.12, 0.12, 0.14, 1.0)
		diorama_vp.world_3d.environment = dio_env

	if diorama_vp.positional_shadow_atlas_size != DIORAMA_SHADOW_ATLAS_SIZE:
		diorama_vp.positional_shadow_atlas_size = DIORAMA_SHADOW_ATLAS_SIZE
		diorama_vp.positional_shadow_atlas_16_bits = true

	diorama_vp.msaa_3d = Viewport.MSAA_DISABLED
	diorama_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	diorama_vp.scaling_3d_scale = 1.0
	diorama_vp.use_occlusion_culling = false


## Synchronously updates the diorama environment, lights, and camera without buffer reallocations.
static func apply_diorama_preview(diorama_vp: SubViewport, config: Dictionary) -> void:
	if not is_instance_valid(diorama_vp):
		return
	print("VideoApplier: Updating diorama preview uniforms synchronously.")

	_apply_server_filter_qualities(config, true)

	var debanding: bool = _get_bool(config, "debanding", VideoConfig.DEFAULT_DEBANDING)
	diorama_vp.use_debanding = debanding

	var aa_key: String = _get_str(config, "aa_mode", VideoConfig.DEFAULT_AA_MODE)
	var aa_dict: Dictionary = _get_dict(VideoConfig.AA_MODES, aa_key)
	var taa_on: bool = _get_bool(aa_dict, "taa", true)
	var fxaa_val: int = _get_int(aa_dict, "fxaa", Viewport.SCREEN_SPACE_AA_DISABLED)
	diorama_vp.use_taa = taa_on
	diorama_vp.screen_space_aa = fxaa_val as Viewport.ScreenSpaceAA
	diorama_vp.msaa_3d = Viewport.MSAA_DISABLED

	var lod: float = _get_float(config, "mesh_lod_threshold", VideoConfig.DEFAULT_MESH_LOD)
	diorama_vp.mesh_lod_threshold = lod

	var dio_world: World3D = diorama_vp.find_world_3d()
	if is_instance_valid(dio_world) and is_instance_valid(dio_world.environment):
		_populate_environment(dio_world.environment, config, true)

	var env_nodes: Array[Node] = diorama_vp.find_children("*", "WorldEnvironment", true, false)
	for node: Node in env_nodes:
		var we: WorldEnvironment = node as WorldEnvironment
		if is_instance_valid(we) and is_instance_valid(we.environment):
			_populate_environment(we.environment, config, true)

	_apply_lights_in_subtree(diorama_vp, config, true)
	_apply_cameras_in_subtree(diorama_vp, config, true)


## Atomically applies the full user graphics configuration to the gameplay viewport and world.
static func apply_gameplay_pipeline(
	tree: SceneTree, main_viewport: Viewport, config: Dictionary
) -> void:
	if not is_instance_valid(tree) or not is_instance_valid(main_viewport):
		return
	print("VideoApplier: Atomically committing full gameplay graphics pipeline.")

	var aniso_key: String = _get_str(config, "anisotropy", VideoConfig.DEFAULT_ANISOTROPY)
	var aniso_lvl: int = VideoConfig.ANISOTROPY_LEVELS.get(aniso_key, 2)
	apply_anisotropy(aniso_lvl)

	_apply_server_filter_qualities(config, false)
	_apply_gameplay_viewport_properties(main_viewport, config)

	var diorama_vp: SubViewport = resolve_diorama_viewport(tree)
	_apply_gameplay_environments(tree, diorama_vp, config)
	_apply_gameplay_lights(tree, diorama_vp, config)
	_apply_gameplay_cameras(tree, diorama_vp, config)


## Synchronously applies active settings to a single newly added gameplay [WorldEnvironment].
static func apply_to_world_environment(we: WorldEnvironment, config: Dictionary) -> void:
	if not is_instance_valid(we):
		return
	if not is_instance_valid(we.environment):
		we.environment = Environment.new()
	else:
		we.environment = we.environment.duplicate()

	print("VideoApplier: Injecting user video settings into WorldEnvironment: ", we.name)
	_apply_server_filter_qualities(config, false)
	_populate_environment(we.environment, config, false)


## Synchronously applies active shadow settings to a single gameplay [Light3D].
static func apply_to_light(light: Light3D, config: Dictionary, is_diorama: bool) -> void:
	if not is_instance_valid(light):
		return

	var shadow_key: String = _get_str(config, "shadow_quality", VideoConfig.DEFAULT_SHADOW_QUALITY)
	var shadow_dict: Dictionary = _get_dict(VideoConfig.SHADOW_QUALITIES, shadow_key)
	var atlas_size: int = _get_int(shadow_dict, "atlas_size", 4096)
	var dyn_shadows: bool = _get_bool(config, "dynamic_light_shadows", true) and (atlas_size > 0)
	var p_dist: float = _get_float(
		config, "positional_shadow_distance", VideoConfig.DEFAULT_POSITIONAL_SHADOW_DISTANCE
	)
	var d_dist: float = _get_float(
		config, "directional_shadow_distance", VideoConfig.DEFAULT_DIRECTIONAL_SHADOW_DISTANCE
	)

	var preview_mask: int = PREVIEW_LAYER_MASK | VOLUMETRIC_LAYER_MASK
	var main_mask: int = ENVIRONMENT_LAYER_MASK | (1 << 1) | (1 << 2) | VOLUMETRIC_LAYER_MASK

	if light is DirectionalLight3D:
		var d_light: DirectionalLight3D = light as DirectionalLight3D
		d_light.shadow_enabled = dyn_shadows
		d_light.directional_shadow_max_distance = d_dist
		if is_diorama:
			d_light.light_cull_mask = preview_mask
		else:
			d_light.light_cull_mask = main_mask
			d_light.shadow_bias = 0.03
			d_light.shadow_normal_bias = 1.5
	elif is_diorama or light.is_in_group(&"dynamic_shadow_casters") or light.shadow_enabled:
		light.shadow_enabled = dyn_shadows
		light.distance_fade_enabled = true
		light.distance_fade_shadow = p_dist
		light.distance_fade_length = 4.0
		light.distance_fade_begin = maxf(p_dist - 4.0, 0.0)
		light.light_cull_mask = preview_mask if is_diorama else main_mask


## Synchronously applies DoF and motion blur settings to a single [Camera3D].
static func apply_to_camera(cam: Camera3D, config: Dictionary, is_diorama: bool) -> void:
	if not is_instance_valid(cam):
		return

	if is_instance_valid(cam.environment):
		_populate_environment(cam.environment, config, is_diorama)

	var dof_enabled: bool = _get_bool(config, "dof_enabled", VideoConfig.DEFAULT_DOF)
	var dof_amount: float = _get_float(config, "dof_amount", VideoConfig.DEFAULT_DOF_AMOUNT)
	var effective_dof: float = dof_amount if dof_enabled else 0.0
	var is_dof_active: bool = dof_enabled and (effective_dof > 0.005)

	if not is_instance_valid(cam.attributes):
		var new_attr: CameraAttributesPractical = CameraAttributesPractical.new()
		new_attr.dof_blur_far_distance = 6.0
		new_attr.dof_blur_far_transition = 8.0
		cam.attributes = new_attr

	if cam.attributes is CameraAttributesPractical:
		var cam_attr: CameraAttributesPractical = cam.attributes as CameraAttributesPractical
		cam_attr.dof_blur_far_enabled = is_dof_active
		cam_attr.dof_blur_amount = effective_dof

	var mb_strength: float = _get_float(config, "motion_blur", VideoConfig.DEFAULT_MOTION_BLUR)
	if cam is ExtendedCamera3D:
		(cam as ExtendedCamera3D).set_motion_blur_strength(mb_strength)


## Resolves the [SubViewport] used for the options menu diorama preview.
static func resolve_diorama_viewport(tree: SceneTree) -> SubViewport:
	if not is_instance_valid(tree) or not is_instance_valid(tree.root):
		return null
	var group_node: Node = tree.get_first_node_in_group(&"diorama_viewport")
	if group_node is SubViewport:
		return group_node as SubViewport
	return tree.root.find_child("DioramaViewport", true, false) as SubViewport


## Toggles diorama rendering state via the central [GraphicsManager] or direct fallback.
static func set_diorama_active(tree: SceneTree, is_menu_active: bool) -> void:
	if not is_instance_valid(tree):
		return
	var gm: Node = tree.root.get_node_or_null("GraphicsManager")
	if is_instance_valid(gm) and gm.has_method(&"set_diorama_mode"):
		gm.call(&"set_diorama_mode", is_menu_active)
		return

	var diorama_vp: SubViewport = resolve_diorama_viewport(tree)
	if not is_instance_valid(diorama_vp):
		return
	if is_menu_active:
		configure_diorama_sandbox(diorama_vp)
		diorama_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		diorama_vp.process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		diorama_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		diorama_vp.process_mode = Node.PROCESS_MODE_DISABLED


## Backwards-compatible synchronous wrapper for legacy callers of apply_viewport_pipeline.
static func apply_viewport_pipeline(
	tree: SceneTree, main_viewport: Viewport, config: Dictionary
) -> void:
	apply_gameplay_pipeline(tree, main_viewport, config)


## Configures global SSAO, SSIL, shadow filter, and volumetric fog on [RenderingServer].
static func _apply_server_filter_qualities(config: Dictionary, is_diorama: bool) -> void:
	var filter_key: String = _get_str(config, "shadow_filter", VideoConfig.DEFAULT_SHADOW_FILTER)
	var filter_q: RenderingServer.ShadowQuality = VideoConfig.SHADOW_FILTER_MODES.get(
		filter_key, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	)
	RenderingServer.positional_soft_shadow_filter_set_quality(filter_q)
	RenderingServer.directional_soft_shadow_filter_set_quality(filter_q)

	var ssao_key: String = _get_str(config, "ssao", VideoConfig.DEFAULT_SSAO)
	var ssao_dict: Dictionary = _get_dict(VideoConfig.SSAO_MODES, ssao_key)
	var ssao_q: int = _get_int(ssao_dict, "quality", 1)
	var ssao_half: bool = _get_bool(ssao_dict, "half_size", false)
	RenderingServer.environment_set_ssao_quality(
		ssao_q as RenderingServer.EnvironmentSSAOQuality, ssao_half, 0.5, 2, 1.0, 50.0
	)

	var ssi_key: String = _get_str(config, "ssi", VideoConfig.DEFAULT_SSI)
	var ssi_dict: Dictionary = _get_dict(VideoConfig.SSI_MODES, ssi_key)
	var ssi_q: int = _get_int(ssi_dict, "quality", 0)
	var ssi_half: bool = _get_bool(ssi_dict, "half_size", true)
	RenderingServer.environment_set_ssil_quality(
		ssi_q as RenderingServer.EnvironmentSSILQuality, ssi_half, 0.5, 2, 1.0, 50.0
	)

	RenderingServer.gi_set_use_half_resolution(true)

	var target_depth: int = DIORAMA_FOG_DEPTH
	if not is_diorama:
		var fog_key: String = _get_str(config, "volumetric_fog", VideoConfig.DEFAULT_FOG)
		var fog_dict: Dictionary = _get_dict(VideoConfig.FOG_MODES, fog_key)
		target_depth = _get_int(fog_dict, "depth", 64)

	if _cached_fog_depth != target_depth:
		_cached_fog_depth = target_depth
		RenderingServer.environment_set_volumetric_fog_volume_size(64, target_depth)


## Applies shadow atlas, scaling, AA, VRS, and LOD settings to the primary gameplay [Viewport].
static func _apply_gameplay_viewport_properties(
	main_viewport: Viewport, config: Dictionary
) -> void:
	var shadow_key: String = _get_str(config, "shadow_quality", VideoConfig.DEFAULT_SHADOW_QUALITY)
	var shadow_dict: Dictionary = _get_dict(VideoConfig.SHADOW_QUALITIES, shadow_key)
	var requested_atlas: int = _get_int(shadow_dict, "atlas_size", 4096)

	if main_viewport.positional_shadow_atlas_size != requested_atlas:
		main_viewport.positional_shadow_atlas_size = requested_atlas
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

	var tex_filter_key: String = _get_str(
		config, "texture_filter", VideoConfig.DEFAULT_TEXTURE_FILTER
	)
	var filter_mode: int = VideoConfig.TEXTURE_FILTER_MODES.get(tex_filter_key, 2)
	main_viewport.canvas_item_default_texture_filter = (
		filter_mode as Viewport.DefaultCanvasItemTextureFilter
	)

	var fsr_key: String = _get_str(config, "fsr_mode", VideoConfig.DEFAULT_FSR_MODE)
	var fsr_scale: float = VideoConfig.FSR_MODES.get(fsr_key, 1.0)
	var res_scale: float = _get_float(
		config, "resolution_scale", VideoConfig.DEFAULT_RESOLUTION_SCALE
	)
	var active_scale: float = fsr_scale if fsr_scale < 1.0 else res_scale
	var use_fsr2: bool = active_scale < 1.0
	main_viewport.scaling_3d_mode = (
		Viewport.SCALING_3D_MODE_FSR2 if use_fsr2 else Viewport.SCALING_3D_MODE_BILINEAR
	)
	main_viewport.scaling_3d_scale = active_scale

	var aa_key: String = _get_str(config, "aa_mode", VideoConfig.DEFAULT_AA_MODE)
	var aa_dict: Dictionary = _get_dict(VideoConfig.AA_MODES, aa_key)
	var msaa_val: int = _get_int(aa_dict, "msaa", Viewport.MSAA_DISABLED)
	var taa_enabled: bool = _get_bool(aa_dict, "taa", true)
	var fxaa_val: int = _get_int(aa_dict, "fxaa", Viewport.SCREEN_SPACE_AA_DISABLED)

	main_viewport.msaa_3d = msaa_val as Viewport.MSAA
	main_viewport.use_taa = (not use_fsr2) and taa_enabled
	main_viewport.screen_space_aa = fxaa_val as Viewport.ScreenSpaceAA

	main_viewport.use_occlusion_culling = _get_bool(
		config, "occlusion_culling", VideoConfig.DEFAULT_OCCLUSION_CULLING
	)
	main_viewport.use_debanding = _get_bool(config, "debanding", VideoConfig.DEFAULT_DEBANDING)
	main_viewport.mesh_lod_threshold = _get_float(
		config, "mesh_lod_threshold", VideoConfig.DEFAULT_MESH_LOD
	)

	var vrs_key: String = _get_str(config, "vrs_mode", VideoConfig.DEFAULT_VRS_MODE)
	var vrs_mode: Viewport.VRSMode = VideoConfig.VRS_MODES.get(vrs_key, Viewport.VRS_DISABLED)
	if not is_vrs_supported():
		vrs_mode = Viewport.VRS_DISABLED

	if vrs_mode == Viewport.VRS_TEXTURE:
		if not is_instance_valid(_cached_vrs_texture):
			_cached_vrs_texture = VrsTextureGenerator.create_radial_density_map()
		main_viewport.vrs_texture = _cached_vrs_texture
		main_viewport.vrs_mode = Viewport.VRS_TEXTURE
	else:
		main_viewport.vrs_mode = Viewport.VRS_DISABLED
		main_viewport.vrs_texture = null


## Applies environment parameters strictly to gameplay [WorldEnvironment] nodes.
static func _apply_gameplay_environments(
	tree: SceneTree, diorama_vp: SubViewport, config: Dictionary
) -> void:
	var updated_envs: Array[Environment] = []
	var we_nodes: Array[Node] = tree.root.find_children("*", "WorldEnvironment", true, false)

	for node: Node in we_nodes:
		var we: WorldEnvironment = node as WorldEnvironment
		if not is_instance_valid(we) or we.is_in_group(&"ignore_global_video_settings"):
			continue
		if is_instance_valid(diorama_vp) and diorama_vp.is_ancestor_of(we):
			continue
		if is_instance_valid(we.environment) and we.environment not in updated_envs:
			_populate_environment(we.environment, config, false)
			updated_envs.append(we.environment)

	var root_w: World3D = tree.root.find_world_3d()
	if is_instance_valid(root_w) and is_instance_valid(root_w.environment):
		var dio_env: Environment = (
			diorama_vp.find_world_3d().environment
			if (is_instance_valid(diorama_vp) and is_instance_valid(diorama_vp.find_world_3d()))
			else null
		)
		if root_w.environment != dio_env and root_w.environment not in updated_envs:
			_populate_environment(root_w.environment, config, false)


## Applies shadow parameters strictly to gameplay [Light3D] nodes.
static func _apply_gameplay_lights(
	tree: SceneTree, diorama_vp: SubViewport, config: Dictionary
) -> void:
	var lights: Array[Node] = tree.root.find_children("*", "Light3D", true, false)
	for node: Node in lights:
		var light: Light3D = node as Light3D
		if not is_instance_valid(light):
			continue
		if is_instance_valid(diorama_vp) and diorama_vp.is_ancestor_of(light):
			continue
		apply_to_light(light, config, false)


## Applies DoF and motion blur parameters strictly to gameplay [Camera3D] nodes.
static func _apply_gameplay_cameras(
	tree: SceneTree, diorama_vp: SubViewport, config: Dictionary
) -> void:
	var cameras: Array[Node] = tree.root.find_children("*", "Camera3D", true, false)
	for node: Node in cameras:
		var cam: Camera3D = node as Camera3D
		if not is_instance_valid(cam):
			continue
		if is_instance_valid(diorama_vp) and diorama_vp.is_ancestor_of(cam):
			continue
		apply_to_camera(cam, config, false)


## Updates all [Light3D] nodes inside a specific subtree.
static func _apply_lights_in_subtree(root_node: Node, config: Dictionary, is_diorama: bool) -> void:
	var lights: Array[Node] = root_node.find_children("*", "Light3D", true, false)
	for node: Node in lights:
		var light: Light3D = node as Light3D
		if is_instance_valid(light):
			apply_to_light(light, config, is_diorama)


## Updates all [Camera3D] nodes inside a specific subtree.
static func _apply_cameras_in_subtree(
	root_node: Node, config: Dictionary, is_diorama: bool
) -> void:
	var cameras: Array[Node] = root_node.find_children("*", "Camera3D", true, false)
	for node: Node in cameras:
		var cam: Camera3D = node as Camera3D
		if is_instance_valid(cam):
			apply_to_camera(cam, config, is_diorama)


## Populates [Environment] properties for either gameplay or isolated diorama preview.
static func _populate_environment(env: Environment, config: Dictionary, is_preview: bool) -> void:
	if not is_instance_valid(env):
		return

	env.tonemap_exposure = _get_float(config, "exposure", VideoConfig.DEFAULT_EXPOSURE)

	var tonemap_key: String = _get_str(config, "tonemap_mode", VideoConfig.DEFAULT_TONEMAP)
	if VideoConfig.TONEMAP_MODES.has(tonemap_key):
		env.tonemap_mode = VideoConfig.TONEMAP_MODES[tonemap_key]

	var ssao_key: String = _get_str(config, "ssao", VideoConfig.DEFAULT_SSAO)
	var ssao_dict: Dictionary = _get_dict(VideoConfig.SSAO_MODES, ssao_key)
	env.ssao_enabled = _get_bool(ssao_dict, "enabled", false)

	var ssi_key: String = _get_str(config, "ssi", VideoConfig.DEFAULT_SSI)
	var ssi_dict: Dictionary = _get_dict(VideoConfig.SSI_MODES, ssi_key)
	env.ssil_enabled = _get_bool(ssi_dict, "enabled", false)

	var ssr_key: String = _get_str(config, "ssr", VideoConfig.DEFAULT_SSR)
	var ssr_dict: Dictionary = _get_dict(VideoConfig.SSR_MODES, ssr_key)
	env.ssr_enabled = _get_bool(ssr_dict, "enabled", false)
	if env.ssr_enabled:
		var steps: int = _get_int(ssr_dict, "steps", 64)
		env.ssr_max_steps = mini(steps, 32) if is_preview else steps

	var sdfgi_key: String = _get_str(config, "sdfgi", VideoConfig.DEFAULT_SDFGI)
	var sdfgi_dict: Dictionary = _get_dict(VideoConfig.SDFGI_MODES, sdfgi_key)
	var sdfgi_on: bool = _get_bool(sdfgi_dict, "enabled", false)
	if sdfgi_on:
		var cascades: int = _get_int(sdfgi_dict, "cascades", 2)
		env.sdfgi_cascades = mini(cascades, 2) if is_preview else cascades
		env.sdfgi_min_cell_size = 0.5 if is_preview else maxf(env.sdfgi_min_cell_size, 1.0)
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		env.sdfgi_energy = 1.0
		env.sdfgi_use_occlusion = true
	env.sdfgi_enabled = sdfgi_on

	var fog_key: String = _get_str(config, "volumetric_fog", VideoConfig.DEFAULT_FOG)
	var fog_dict: Dictionary = _get_dict(VideoConfig.FOG_MODES, fog_key)
	var fog_on: bool = _get_bool(fog_dict, "enabled", false)
	env.volumetric_fog_enabled = fog_on
	if fog_on:
		if is_preview:
			env.volumetric_fog_density = 0.02
			env.volumetric_fog_albedo = Color(0.85, 0.9, 0.95)
		elif env.volumetric_fog_density <= 0.0001:
			env.volumetric_fog_density = DEFAULT_MAIN_FOG_DENSITY

	var glow_key: String = _get_str(config, "glow", VideoConfig.DEFAULT_GLOW)
	var glow_dict: Dictionary = _get_dict(VideoConfig.GLOW_MODES, glow_key)
	var glow_on: bool = _get_bool(glow_dict, "enabled", false)
	env.glow_enabled = glow_on
	if glow_on:
		var is_bicubic: bool = _get_bool(glow_dict, "bicubic", false)
		env.glow_blend_mode = (
			Environment.GLOW_BLEND_MODE_SOFTLIGHT
			if (is_bicubic and not is_preview)
			else Environment.GLOW_BLEND_MODE_ADDITIVE
		)


## Safely extracts a string value from [param dict] with [param default_val].
static func _get_str(dict: Dictionary, key: String, default_val: String) -> String:
	var raw: Variant = dict.get(key, default_val)
	if raw is String:
		return raw
	return default_val


## Safely extracts an integer value from [param dict] with [param default_val].
static func _get_int(dict: Dictionary, key: String, default_val: int) -> int:
	var raw: Variant = dict.get(key, default_val)
	if raw is int:
		return raw
	if raw is float:
		var f_val: float = raw
		return int(f_val)
	return default_val


## Safely extracts a float value from [param dict] with [param default_val].
static func _get_float(dict: Dictionary, key: String, default_val: float) -> float:
	var raw: Variant = dict.get(key, default_val)
	if raw is float:
		return raw
	if raw is int:
		var i_val: int = raw
		return float(i_val)
	return default_val


## Safely extracts a boolean value from [param dict] with [param default_val].
static func _get_bool(dict: Dictionary, key: String, default_val: bool) -> bool:
	var raw: Variant = dict.get(key, default_val)
	if raw is bool:
		return raw
	return default_val


## Safely extracts a sub-dictionary from [param source] mapped to [param key].
static func _get_dict(source: Dictionary, key: String) -> Dictionary:
	var raw: Variant = source.get(key, {})
	if raw is Dictionary:
		return raw
	return {}
