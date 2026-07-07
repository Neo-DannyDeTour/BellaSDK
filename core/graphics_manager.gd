extends Node

## Manages automated graphics scaling to maintain performance targets.
## Checks FPS periodically and dials back rendering features if below 60.

## Emitted when the performance profile drops a level to regain FPS.
signal performance_profile_adjusted(downgrade_level: int)

## Emitted when switching between User and Auto-Optimized modes.
signal profile_mode_changed(is_optimized: bool)

## Time in seconds between checking the framerate.
const FPS_CHECK_INTERVAL: float = 1.5

## Minimum acceptable frames per second before triggering a downgrade.
const TARGET_FPS_MINIMUM: float = 59.0

## Tracks if the game is currently auto-optimizing settings.
var is_auto_optimizing: bool = false

var _is_low_end: bool = false
var _active_environment: Environment = null
var _fps_timer: Timer = null
var _sdfgi_downgrade_level: int = 0


func _ready() -> void:
	print("GraphicsManager: Initializing and detecting hardware.")
	_is_low_end = _detect_low_end_hardware()

	get_tree().node_added.connect(_on_node_added)

	var default_auto: bool = _is_low_end
	var use_auto: bool = GlobalSettings.get_setting("Settings", "use_auto_optimizer", default_auto) as bool

	if use_auto:
		print("GraphicsManager: Booting directly into Auto-Optimization mode.")
		enable_auto_mode()
	else:
		print("GraphicsManager: Booting into User Settings mode.")
		enable_user_mode()

	call_deferred("_emit_profile_state")


func enable_user_mode() -> void:
	print("GraphicsManager: Switching to User Defined Settings.")
	is_auto_optimizing = false
	_sdfgi_downgrade_level = 0
	GlobalSettings.save_setting("Settings", "use_auto_optimizer", false)
	
	if _fps_timer:
		_fps_timer.stop()
		
	profile_mode_changed.emit(is_auto_optimizing)


func enable_auto_mode() -> void:
	if is_auto_optimizing:
		return
		
	print("GraphicsManager: Switching to 60 FPS Target Auto-Optimization.")
	is_auto_optimizing = true
	GlobalSettings.save_setting("Settings", "use_auto_optimizer", true)
	
	if _fps_timer == null:
		_setup_fps_timer()
	else:
		_fps_timer.start()
		
	profile_mode_changed.emit(is_auto_optimizing)
	
	if _is_low_end:
		call_deferred("_apply_global_viewport_settings")

	var saved_level: int = GlobalSettings.get_setting("Settings", "optimized_downgrade_level", 0) as int
	if saved_level > 0:
		print("GraphicsManager: Restoring previous optimization level: ", saved_level)
		_fast_forward_downgrades(saved_level - 1)
		
		if _sdfgi_downgrade_level <= 7 and _fps_timer:
			_fps_timer.start()
	elif _is_low_end:
		var env: Environment = _get_current_environment()
		if is_instance_valid(env):
			_fast_forward_downgrades(7)


func _emit_profile_state() -> void:
	print("GraphicsManager: Emitting initial profile state.")
	profile_mode_changed.emit(is_auto_optimizing)


func _setup_fps_timer() -> void:
	print("GraphicsManager: Setting up periodic FPS check timer.")
	_fps_timer = Timer.new()
	_fps_timer.wait_time = FPS_CHECK_INTERVAL
	_fps_timer.one_shot = false
	_fps_timer.autostart = true

	_fps_timer.timeout.connect(_on_fps_timer_timeout)

	add_child(_fps_timer)


func _on_fps_timer_timeout() -> void:
	if not is_auto_optimizing:
		return

	_evaluate_runtime_performance()


func _detect_low_end_hardware() -> bool:
	print("GraphicsManager: Evaluating current video adapter.")
	var adapter_type: RenderingDevice.DeviceType = (
		RenderingServer.get_video_adapter_type() as RenderingDevice.DeviceType
	)
	var adapter_name: String = RenderingServer.get_video_adapter_name().to_lower()
	
	if adapter_type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or "intel" in adapter_name:
		print("GraphicsManager: Integrated GPU detected.")
		return true

	print("GraphicsManager: Discrete GPU detected.")
	return false


func _apply_global_viewport_settings() -> void:
	print("GraphicsManager: Applying global viewport limits for optimized mode.")
	var root_viewport: Window = get_tree().root
	root_viewport.msaa_3d = Viewport.MSAA_DISABLED
	RenderingServer.environment_set_volumetric_fog_volume_size(32, 32)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		print("GraphicsManager: WorldEnvironment added. Registering environment.")
		_active_environment = node.environment
		
		if is_auto_optimizing:
			var saved_level: int = GlobalSettings.get_setting("Settings", "optimized_downgrade_level", 0) as int
			if saved_level > 0:
				_fast_forward_downgrades(saved_level - 1)
			elif _is_low_end:
				_tweak_environment(_active_environment)
				_fast_forward_downgrades(7)


func _get_current_environment() -> Environment:
	var vp: Viewport = get_viewport()
	if vp and vp.find_world_3d():
		var world: World3D = vp.find_world_3d()
		if world.environment:
			return world.environment
		if world.fallback_environment:
			return world.fallback_environment
			
	return _active_environment


func _tweak_environment(env: Environment) -> void:
	print("GraphicsManager: Disabling heavy effects for optimization mode without saving to disk.")
	if env:
		env.ssao_enabled = false
		env.ssr_enabled = false


func _evaluate_runtime_performance() -> void:
	var current_fps: float = Engine.get_frames_per_second()
	
	if current_fps > 0.0 and current_fps < TARGET_FPS_MINIMUM:
		print("GraphicsManager: FPS (", current_fps, ") below target. Applying step down.")
		_apply_stepwise_downgrade()
	else:
		print("GraphicsManager: Performance is stable at ", current_fps, " FPS.")


func _fast_forward_downgrades(target_level: int) -> void:
	print("GraphicsManager: Bypassing timer, fast-forwarding to step ", target_level)
	while _sdfgi_downgrade_level <= target_level:
		_apply_stepwise_downgrade()
	
	if _fps_timer:
		_fps_timer.stop()


func _apply_stepwise_downgrade() -> void:
	print("GraphicsManager: Applying downgrade level: ", _sdfgi_downgrade_level)
	var vp: Viewport = get_tree().root
	var env: Environment = _get_current_environment()

	match _sdfgi_downgrade_level:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.use_taa = false
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		1:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.50
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		2:
			var win: Window = vp as Window
			if win and not win.is_embedded():
				win.size = Vector2i(1024, 768)
		3:
			if is_instance_valid(env):
				env.sdfgi_cascades = 2
				env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
			RenderingServer.gi_set_use_half_resolution(true)
		4:
			if is_instance_valid(env):
				env.volumetric_fog_enabled = false
				env.ssil_enabled = false
		5:
			if is_instance_valid(env):
				env.ssao_enabled = false
				env.ssr_enabled = false
		6:
			if is_instance_valid(env):
				env.sdfgi_enabled = false
		7:
			vp.positional_shadow_atlas_size = 0
			vp.mesh_lod_threshold = 2.0
			
			if _fps_timer and not _fps_timer.is_stopped():
				_fps_timer.stop()

	_sdfgi_downgrade_level += 1
	GlobalSettings.save_setting("Settings", "optimized_downgrade_level", _sdfgi_downgrade_level)
	performance_profile_adjusted.emit(_sdfgi_downgrade_level)
