extends Node

signal performance_profile_adjusted(downgrade_level: int)

const FPS_CHECK_INTERVAL: float = 3.0
const TARGET_FPS_MINIMUM: float = 59.0
const SAVE_PATH: String = "user://settings.cfg"

var _is_low_end: bool = false
var _active_environment: Environment = null
var _fps_timer: Timer = null
var _sdfgi_downgrade_level: int = 0


func _ready() -> void:
	print("GraphicsManager: Initializing and detecting hardware.")
	_is_low_end = _detect_low_end_hardware()
	_apply_global_viewport_settings()

	var error: Error = get_tree().node_added.connect(_on_node_added) as Error
	if error != OK:
		push_error("GraphicsManager: Failed to connect node_added signal.")

	_setup_fps_timer()


func _setup_fps_timer() -> void:
	print("GraphicsManager: Setting up periodic FPS check timer.")
	_fps_timer = Timer.new()
	_fps_timer.wait_time = FPS_CHECK_INTERVAL
	_fps_timer.one_shot = false
	_fps_timer.autostart = true

	var error: Error = _fps_timer.timeout.connect(_on_fps_timer_timeout) as Error
	if error != OK:
		push_error("GraphicsManager: Failed to connect Timer timeout signal.")

	add_child(_fps_timer)


func _on_fps_timer_timeout() -> void:
	if _active_environment == null:
		return

	_evaluate_runtime_performance()


func _detect_low_end_hardware() -> bool:
	print("GraphicsManager: Evaluating current video adapter.")

	var adapter_type: RenderingDevice.DeviceType = (
		RenderingServer.get_video_adapter_type() as RenderingDevice.DeviceType
	)

	if adapter_type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		print("GraphicsManager: Integrated GPU detected.")
		return true

	print("GraphicsManager: Discrete GPU detected.")
	return false


func _apply_global_viewport_settings() -> void:
	print("GraphicsManager: Applying global viewport settings.")
	var root_viewport: Window = get_tree().root

	if _is_low_end:
		print("GraphicsManager: Applying low-end viewport limits.")
		root_viewport.msaa_3d = Viewport.MSAA_DISABLED
		RenderingServer.environment_set_volumetric_fog_volume_size(32, 32)
	else:
		print("GraphicsManager: Applying hi-end viewport limits.")
		root_viewport.msaa_3d = Viewport.MSAA_4X
		RenderingServer.environment_set_volumetric_fog_volume_size(64, 64)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		print("GraphicsManager: WorldEnvironment added. Registering environment.")
		_active_environment = node.environment
		_tweak_environment(_active_environment)
		
		if _is_low_end:
			print("GraphicsManager: iGPU confirmed. Fast-forwarding profile adjustments.")
			_fast_forward_downgrades(7)


func _tweak_environment(env: Environment) -> void:
	print("GraphicsManager: Tweaking Environment based on capabilities.")
	if not env:
		return

	if _is_low_end:
		print("GraphicsManager: Disabling SSAO and SSR for low-end hardware.")
		env.ssao_enabled = false
		env.ssr_enabled = false
	else:
		print("GraphicsManager: Forcing SSAO, SSR, and Fog ON for hi-end hardware.")
		env.ssao_enabled = true
		env.ssr_enabled = true
		env.volumetric_fog_enabled = true


func _evaluate_runtime_performance() -> void:
	var current_fps: float = Engine.get_frames_per_second()
	print("GraphicsManager: Checking runtime performance. Current FPS: ", current_fps)

	if current_fps > 0.0 and current_fps < TARGET_FPS_MINIMUM:
		print("GraphicsManager: FPS below target. Applying dynamic downgrade step.")
		_apply_stepwise_downgrade()
	else:
		print("GraphicsManager: Performance is stable.")


func _fast_forward_downgrades(target_level: int) -> void:
	print("GraphicsManager: Bypassing timer, fast-forwarding to step ", target_level)
	while _sdfgi_downgrade_level <= target_level:
		_apply_stepwise_downgrade()
	
	if _fps_timer:
		_fps_timer.stop()
		print("GraphicsManager: Timer disabled after fast-forward.")


func _apply_stepwise_downgrade() -> void:
	print("GraphicsManager: Applying downgrade level: ", _sdfgi_downgrade_level)
	var vp: Viewport = get_tree().root

	match _sdfgi_downgrade_level:
		0:
			print("GraphicsManager: Disabling MSAA/TAA, enabling FXAA.")
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.use_taa = false
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		1:
			print("GraphicsManager: Enabling FSR Performance (Scale 0.50).")
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.50
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		2:
			print("GraphicsManager: Lowering Window Resolution to 1024x768.")
			var win: Window = vp as Window
			if win and not win.is_embedded():
				win.size = Vector2i(1024, 768)
		3:
			print("GraphicsManager: Reducing SDFGI cascades to 2 and half res.")
			_active_environment.sdfgi_cascades = 2
			_active_environment.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
			RenderingServer.gi_set_use_half_resolution(true)
		4:
			print("GraphicsManager: Disabling Volumetric Fog and SSIL.")
			_active_environment.volumetric_fog_enabled = false
			_active_environment.ssil_enabled = false
		5:
			print("GraphicsManager: Disabling SSAO and SSR.")
			_active_environment.ssao_enabled = false
			_active_environment.ssr_enabled = false
		6:
			print("GraphicsManager: Disabling SDFGI completely.")
			_active_environment.sdfgi_enabled = false
		7:
			print("GraphicsManager: Disabling shadows and lowering mesh LOD.")
			vp.positional_shadow_atlas_size = 0
			vp.mesh_lod_threshold = 2.0
			
			if _fps_timer and not _fps_timer.is_stopped():
				_fps_timer.stop()
				print("GraphicsManager: Max downgrades reached. Stopping timer.")

	_save_performance_settings()
	performance_profile_adjusted.emit(_sdfgi_downgrade_level)
	_sdfgi_downgrade_level += 1


func _save_performance_settings() -> void:
	print("GraphicsManager: Saving updated graphics state to settings.cfg.")
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(SAVE_PATH)
	
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("GraphicsManager: Could not load config file for writing.")
		return

	var vp: Viewport = get_tree().root
	
	# Map the current engine state to the UI string constants
	if vp.msaa_3d == Viewport.MSAA_DISABLED:
		if vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA:
			config.set_value("Settings", "aa_mode", "FXAA (Fast)")
		elif not vp.use_taa:
			config.set_value("Settings", "aa_mode", "Disabled")

	if vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2:
		config.set_value("Settings", "fsr_mode", "Performance")
	
	var win: Window = vp as Window
	if win and not win.is_embedded():
		config.set_value("Settings", "resolution_x", win.size.x)
		config.set_value("Settings", "resolution_y", win.size.y)
		
	config.save(SAVE_PATH)
	print("GraphicsManager: Settings saved successfully.")
