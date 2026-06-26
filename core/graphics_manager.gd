extends Node

const FPS_CHECK_INTERVAL: float = 3.0
const TARGET_FPS_MINIMUM: float = 55.0

var _is_low_end: bool = false
var _active_environment: Environment = null
var _performance_downgraded: bool = false
var _fps_timer: Timer = null


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
	print("GraphicsManager: FPS Timer timeout triggered.")
	if _performance_downgraded or _active_environment == null:
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
		print("GraphicsManager: FPS below target. Downgrading graphics dynamically.")
		_active_environment.volumetric_fog_enabled = false

		# If the system started as high-end but is failing, strip the heavy effects
		if not _is_low_end:
			_active_environment.ssao_enabled = false
			_active_environment.ssr_enabled = false

		_performance_downgraded = true
		
		# Stop the timer immediately to save CPU cycles once downgraded
		_fps_timer.stop()
		print("GraphicsManager: Downgrade complete. FPS timer stopped to optimize performance.")
