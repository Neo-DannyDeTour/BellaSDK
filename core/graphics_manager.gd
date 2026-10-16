## Global autoload managing automatic graphics scaling and performance optimizations.
## Continuously tracks framerate and scales graphics to maintain 60 FPS.
extends Node

## Emitted when the performance profile drops a level to regain FPS.
## [param downgrade_level] The step index of the downgrade tier applied.
@warning_ignore("unused_signal")
signal performance_profile_adjusted(downgrade_level: int)

## Emitted when switching between User and Auto-Optimized modes.
## [param is_optimized] The running auto-optimization state.
@warning_ignore("unused_signal")
signal profile_mode_changed(is_optimized: bool)

## Emitted when the 60 FPS auto-tune benchmark finishes.
## [param optimal_level] The final downgrade tier index reached.
@warning_ignore("unused_signal")
signal benchmark_completed(optimal_level: int)

## Time in seconds between checking the framerate.
const FPS_CHECK_INTERVAL: float = 1.5

## Minimum acceptable frames per second before triggering a downgrade.
const TARGET_FPS_MINIMUM: float = 55.0

## Number of consecutive low-FPS samples required before stepping down quality.
const LOW_FPS_STRIKE_THRESHOLD: int = 2

## Grace period in seconds after level load before FPS polling begins.
const POST_LOAD_GRACE_SECONDS: float = 4.0

## Maximum number of downgrade levels available.
const MAX_DOWNGRADE_LEVEL: int = 7

## Tracks if the game is currently auto-optimizing settings.
var is_auto_optimizing: bool = false

## Tracks if the benchmark routine is currently running.
var is_benchmarking: bool = false

## Tracks if the user is running on an integrated GPU or low-end hardware.
var _is_low_end: bool = false

## Cached reference to the currently active gameplay [Environment].
var _active_environment: Environment = null

## Timer used for periodic FPS checking.
var _fps_timer: Timer = null

## The current integer step representing visual quality downgrade.
var _sdfgi_downgrade_level: int = 0

## Consecutive low-FPS sample counter to ignore single-frame hitches.
var _low_fps_strikes: int = 0

## Timestamp (msec) until which FPS evaluation is paused after scene changes.
var _grace_until_msec: int = 0

## Cached radial Variable Rate Shading density texture.
var _vrs_density_texture: ImageTexture = null


## Lifecycle method configuring low-end hardware checks and startup mode.
func _ready() -> void:
	print("GraphicsManager: Initializing and detecting hardware.")
	set_process(false)
	set_physics_process(false)
	_is_low_end = _detect_low_end_hardware()

	get_tree().node_added.connect(_on_node_added)

	var use_auto: bool = GlobalSettings.get_setting_bool("Settings", "use_auto_optimizer", false)

	if use_auto:
		print("GraphicsManager: Booting into Auto-Optimization mode.")
		enable_auto_mode()
	else:
		print("GraphicsManager: Booting into User Settings mode.")
		is_auto_optimizing = false
		_sdfgi_downgrade_level = 0
		GlobalSettings.save_setting("Settings", "optimized_downgrade_level", 0)

	call_deferred(&"_emit_profile_state")


## Disables the auto-optimizer and restores control to user-defined settings.
func enable_user_mode() -> void:
	print("GraphicsManager: Switching to User Defined Settings.")
	is_auto_optimizing = false
	_sdfgi_downgrade_level = 0
	_low_fps_strikes = 0
	GlobalSettings.save_setting("Settings", "use_auto_optimizer", false)
	GlobalSettings.save_setting("Settings", "optimized_downgrade_level", 0)

	if is_instance_valid(_fps_timer):
		_fps_timer.stop()

	profile_mode_changed.emit(is_auto_optimizing)


## Disarms auto-downgrades when the player manually edits graphics settings.
func notify_manual_user_override() -> void:
	if is_auto_optimizing and not is_benchmarking:
		print("GraphicsManager: Manual graphics edit detected. Switching to User Mode.")
		enable_user_mode()


## Enables the auto-optimizer to scale graphics in response to gameplay FPS.
func enable_auto_mode() -> void:
	if is_auto_optimizing:
		return

	print("GraphicsManager: Switching to 60 FPS Target Auto-Optimization.")
	is_auto_optimizing = true
	_low_fps_strikes = 0
	_grace_until_msec = Time.get_ticks_msec() + int(POST_LOAD_GRACE_SECONDS * 1000.0)
	GlobalSettings.save_setting("Settings", "use_auto_optimizer", true)

	if _fps_timer == null:
		_setup_fps_timer()
	elif is_instance_valid(_fps_timer):
		_fps_timer.start()

	profile_mode_changed.emit(is_auto_optimizing)

	if _is_low_end:
		call_deferred(&"_apply_global_viewport_settings")

	var saved_level: int = GlobalSettings.get_setting_int(
		"Settings", "optimized_downgrade_level", 0
	)
	if saved_level > 0:
		print("GraphicsManager: Restoring previous optimization level: ", saved_level)
		_fast_forward_downgrades(saved_level)


## Runs an active benchmark stepping through quality profiles until 60 FPS holds.
func run_benchmark_for_60fps() -> void:
	if is_benchmarking:
		return

	print("GraphicsManager: Starting automatic benchmark for 60 FPS target.")
	is_benchmarking = true
	if is_instance_valid(_fps_timer):
		_fps_timer.stop()

	_sdfgi_downgrade_level = 0
	var current_step: int = 0

	while current_step <= MAX_DOWNGRADE_LEVEL:
		_apply_downgrade_step(current_step)
		_sdfgi_downgrade_level = current_step
		await get_tree().create_timer(1.0).timeout

		var sample_fps: float = Engine.get_frames_per_second()
		print("GraphicsManager: Benchmark step ", current_step, " recorded ", sample_fps, " FPS.")

		if sample_fps >= TARGET_FPS_MINIMUM:
			print("GraphicsManager: Target 60 FPS achieved at level: ", current_step)
			break

		current_step += 1

	is_benchmarking = false
	var bulk_save: Dictionary = {
		"optimized_downgrade_level": _sdfgi_downgrade_level,
		"use_auto_optimizer": true,
	}
	GlobalSettings.save_settings_bulk("Settings", bulk_save)
	benchmark_completed.emit(_sdfgi_downgrade_level)


## Configures Variable Rate Shading texture and mode on root [Viewport].
## [param enabled] Whether to attach and activate VRS density mapping.
func apply_vrs_state(enabled: bool) -> void:
	print("GraphicsManager: Updating Variable Rate Shading state: ", enabled)
	if not VideoApplier.is_vrs_supported():
		return

	var vp: Viewport = get_tree().root
	if not is_instance_valid(vp):
		return

	if enabled:
		if not is_instance_valid(_vrs_density_texture):
			_vrs_density_texture = VrsTextureGenerator.create_radial_density_map()
		vp.vrs_texture = _vrs_density_texture
		vp.vrs_mode = Viewport.VRS_TEXTURE
	else:
		vp.vrs_mode = Viewport.VRS_DISABLED
		vp.vrs_texture = null


## Emits the current profile mode to any listeners safely after initialization.
func _emit_profile_state() -> void:
	print("GraphicsManager: Emitting initial profile state.")
	profile_mode_changed.emit(is_auto_optimizing)


## Instantiates and starts the internal timer used for FPS evaluation intervals.
func _setup_fps_timer() -> void:
	print("GraphicsManager: Setting up periodic FPS check timer.")
	_fps_timer = Timer.new()
	_fps_timer.wait_time = FPS_CHECK_INTERVAL
	_fps_timer.one_shot = false
	_fps_timer.autostart = true
	_fps_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_fps_timer.timeout.connect(_on_fps_timer_timeout)
	add_child(_fps_timer)


## Called by the FPS timer to trigger performance checks during active gameplay.
func _on_fps_timer_timeout() -> void:
	if not is_auto_optimizing or is_benchmarking:
		return

	if get_tree().paused or LoadingScreen.is_transition_active:
		_low_fps_strikes = 0
		return

	if Time.get_ticks_msec() < _grace_until_msec:
		return

	_evaluate_runtime_performance()


## Analyzes the [RenderingServer] video adapter string to detect integrated GPUs.
func _detect_low_end_hardware() -> bool:
	print("GraphicsManager: Evaluating current video adapter.")
	var adapter_name: String = RenderingServer.get_video_adapter_name().to_lower()
	var adapter_type: int = RenderingServer.get_video_adapter_type()

	if adapter_type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or "intel" in adapter_name:
		print("GraphicsManager: Integrated GPU detected.")
		return true

	print("GraphicsManager: Discrete GPU detected.")
	return false


## Forces initial global settings like MSAA limits for the root [Viewport].
func _apply_global_viewport_settings() -> void:
	print("GraphicsManager: Applying global viewport limits for optimized mode.")
	var root_viewport: Window = get_tree().root
	if is_instance_valid(root_viewport):
		root_viewport.msaa_3d = Viewport.MSAA_DISABLED
	RenderingServer.environment_set_volumetric_fog_volume_size(32, 32)
	apply_vrs_state(true)


## Scene tree signal callback checking for new gameplay [WorldEnvironment] nodes.
## [param node] The newly added node in the tree.
func _on_node_added(node: Node) -> void:
	if not (node is WorldEnvironment):
		return

	var we: WorldEnvironment = node as WorldEnvironment
	if not is_instance_valid(we) or we.find_parent("DioramaViewport") != null:
		return
	if we.is_in_group("ignore_global_video_settings"):
		return

	print("GraphicsManager: Gameplay WorldEnvironment added. Registering environment.")
	_active_environment = we.environment
	_grace_until_msec = Time.get_ticks_msec() + int(POST_LOAD_GRACE_SECONDS * 1000.0)
	_low_fps_strikes = 0

	if is_auto_optimizing:
		var saved_level: int = GlobalSettings.get_setting_int(
			"Settings", "optimized_downgrade_level", 0
		)
		if saved_level > 0:
			_sdfgi_downgrade_level = 0
			_fast_forward_downgrades(saved_level)
		elif _is_low_end:
			_tweak_environment(_active_environment)
			_sdfgi_downgrade_level = 0
			_fast_forward_downgrades(MAX_DOWNGRADE_LEVEL)


## Looks up the current [Environment] resource connected to the active 3D world.
func _get_current_environment() -> Environment:
	if is_instance_valid(_active_environment):
		return _active_environment

	var vp: Viewport = get_viewport()
	if is_instance_valid(vp) and vp.find_world_3d():
		var world: World3D = vp.find_world_3d()
		if is_instance_valid(world.environment):
			return world.environment
		if is_instance_valid(world.fallback_environment):
			return world.fallback_environment

	return null


## Applies immediate performance settings directly to the given [Environment].
## [param env] The environment to alter.
func _tweak_environment(env: Environment) -> void:
	print("GraphicsManager: Disabling heavy effects for optimization mode.")
	if is_instance_valid(env):
		env.ssao_enabled = false
		env.ssr_enabled = false


## Measures engine framerate and applies downgrades after sustained drops.
func _evaluate_runtime_performance() -> void:
	var current_fps: float = Engine.get_frames_per_second()

	if current_fps > 0.0 and current_fps < TARGET_FPS_MINIMUM:
		_low_fps_strikes += 1
		if _low_fps_strikes >= LOW_FPS_STRIKE_THRESHOLD:
			_low_fps_strikes = 0
			print("GraphicsManager: Sustained FPS (", current_fps, ") below target. Stepping down.")
			_apply_stepwise_downgrade()
	else:
		_low_fps_strikes = 0


## Applies multiple downgrades instantly up to the requested step index.
## [param target_level] The specific step level index to apply up to.
func _fast_forward_downgrades(target_level: int) -> void:
	var clamped_target: int = mini(target_level, MAX_DOWNGRADE_LEVEL)
	print("GraphicsManager: Fast-forwarding downgrades to step ", clamped_target)

	while _sdfgi_downgrade_level <= clamped_target:
		_apply_downgrade_step(_sdfgi_downgrade_level)
		_sdfgi_downgrade_level += 1

	GlobalSettings.save_setting("Settings", "optimized_downgrade_level", _sdfgi_downgrade_level)
	performance_profile_adjusted.emit(_sdfgi_downgrade_level)

	if _sdfgi_downgrade_level > MAX_DOWNGRADE_LEVEL and is_instance_valid(_fps_timer):
		_fps_timer.stop()


## Disables or reduces the quality of one major rendering setting to free frametime.
func _apply_stepwise_downgrade() -> void:
	if _sdfgi_downgrade_level > MAX_DOWNGRADE_LEVEL:
		return

	_apply_downgrade_step(_sdfgi_downgrade_level)
	_sdfgi_downgrade_level += 1

	GlobalSettings.save_setting("Settings", "optimized_downgrade_level", _sdfgi_downgrade_level)
	performance_profile_adjusted.emit(_sdfgi_downgrade_level)

	if _sdfgi_downgrade_level > MAX_DOWNGRADE_LEVEL and is_instance_valid(_fps_timer):
		_fps_timer.stop()


## Executes specific rendering quality reduction operations for a given step index.
## [param step] The downgrade tier index to apply.
func _apply_downgrade_step(step: int) -> void:
	print("GraphicsManager: Applying downgrade level: ", step)
	var vp: Viewport = get_tree().root
	var env: Environment = _get_current_environment()

	match step:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.use_taa = false
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		1:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.50
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			apply_vrs_state(true)
		2:
			var win: Window = vp as Window
			if (
				is_instance_valid(win)
				and not win.is_embedded()
				and win.mode == Window.MODE_WINDOWED
			):
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
			GlobalSettings.save_setting("Settings", "volumetric_fog", "Off")
			GlobalSettings.save_setting("Settings", "ssi", "Off")
		5:
			if is_instance_valid(env):
				env.ssao_enabled = false
				env.ssr_enabled = false
			GlobalSettings.save_setting("Settings", "ssao", "Off")
			GlobalSettings.save_setting("Settings", "ssr", "Off")
		6:
			if is_instance_valid(env):
				env.sdfgi_enabled = false
			GlobalSettings.save_setting("Settings", "sdfgi", "Off")
		7:
			vp.positional_shadow_atlas_size = 0
			vp.mesh_lod_threshold = 2.0
