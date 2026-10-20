## Controls the Dishonored-style screen-space water sheet tearing and meniscus wipe overlay.
## Extracts [Camera3D] angular yaw velocity and pitch gravity modulation to drive
## [code]res://vfx/water_sheet_wipe.gdshader[/code] with zero idle fill-rate or CPU cost.
class_name WaterWipeController
extends ColorRect

## Preloaded screen-space water sheet meniscus wipe shader.
const WATER_WIPE_SHADER: Shader = preload("res://vfx/water_sheet_wipe.gdshader")

## Shader uniform identifier for primary downward drainage progression (0.0 to 1.5).
const PARAM_WIPE_PROGRESS: StringName = &"wipe_progress"

## Shader uniform identifier for overall water sheet opacity and refraction weight.
const PARAM_WASH_INTENSITY: StringName = &"wash_intensity"

## Shader uniform identifier for fluid visibility fade from 1.0 to 0.0.
const PARAM_VISIBILITY: StringName = &"visibility"

## Shader uniform identifier for horizontal camera yaw angular velocity.
const PARAM_ANGULAR_YAW_DELTA: StringName = &"angular_yaw_delta"

## Shader uniform identifier for camera pitch gravity acceleration modifier.
const PARAM_PITCH_GRAVITY_MOD: StringName = &"pitch_gravity_mod"

## Default duration in seconds for downward stream drainage and fluid dissolution.
const DEFAULT_WIPE_DURATION: float = 1.4

## Maximum clamped camera yaw angular velocity (rad/s) sent to the shader.
const MAX_YAW_VELOCITY: float = 10.0

## Exponential smoothing rate for camera yaw velocity extraction.
const YAW_SMOOTH_SPEED: float = 14.0

## Cached [ShaderMaterial] driving the meniscus wipe shader.
var _shader_material: ShaderMaterial = null

## Active [Tween] orchestrating stream drainage and fluid visibility dissolution.
var _wipe_tween: Tween = null

## Cached reference to the active viewport [Camera3D].
var _cached_camera: Camera3D = null

## Previous frame camera yaw angle in radians for angular velocity calculation.
var _prev_yaw: float = 0.0

## Smoothed horizontal yaw angular velocity injected into the shader.
var _smoothed_yaw_delta: float = 0.0

## Guard ensuring first frame after activation does not produce a yaw delta spike.
var _has_prev_yaw: bool = false

## Tracks whether the player is currently inside a continuous waterfall volume.
var _in_waterfall: bool = false


## Initializes full-screen layout, shader material, signal bindings, and idle sleep state.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_shader_material()
	assert(is_instance_valid(_shader_material), "WaterWipeController: ShaderMaterial required.")
	_reset_shader_uniforms()
	_connect_signals()
	set_process(false)
	hide()
	print("WaterWipeController: Initialized in idle sleep state.")


## Disconnects global [Events] signals when removed from the scene tree.
func _exit_tree() -> void:
	_kill_active_tween()
	if not is_instance_valid(Events):
		return
	if Events.player_camera_registered.is_connected(_on_camera_registered):
		Events.player_camera_registered.disconnect(_on_camera_registered)
	if Events.has_signal(&"water_sheet_wipe_requested"):
		if Events.water_sheet_wipe_requested.is_connected(start_surfacing_wipe):
			Events.water_sheet_wipe_requested.disconnect(start_surfacing_wipe)
	if Events.waterfall_vfx_toggled.is_connected(_on_waterfall_vfx_toggled):
		Events.waterfall_vfx_toggled.disconnect(_on_waterfall_vfx_toggled)
	if Events.underwater_vfx_toggled.is_connected(_on_underwater_vfx_toggled):
		Events.underwater_vfx_toggled.disconnect(_on_underwater_vfx_toggled)


## Extracts [Camera3D] basis inertia (yaw shear and pitch gravity) while the wipe is active.
func _process(delta: float) -> void:
	if not is_instance_valid(_shader_material):
		return

	var cam: Camera3D = _get_active_camera()
	if not is_instance_valid(cam):
		return

	var cam_basis: Basis = cam.global_transform.basis
	var current_yaw: float = cam_basis.get_euler().y
	var safe_delta: float = maxf(delta, 0.0001)

	if _has_prev_yaw:
		var yaw_diff: float = wrapf(current_yaw - _prev_yaw, -PI, PI)
		var raw_yaw_vel: float = clampf(yaw_diff / safe_delta, -MAX_YAW_VELOCITY, MAX_YAW_VELOCITY)
		var lerp_weight: float = clampf(safe_delta * YAW_SMOOTH_SPEED, 0.0, 1.0)
		_smoothed_yaw_delta = lerpf(_smoothed_yaw_delta, raw_yaw_vel, lerp_weight)
	else:
		_smoothed_yaw_delta = 0.0
		_has_prev_yaw = true

	_prev_yaw = current_yaw

	var cam_forward: Vector3 = -cam_basis.z
	var up_dot: float = cam_forward.dot(Vector3.UP)
	var pitch_mod: float = clampf(remap(-up_dot, -1.0, 1.0, -0.5, 0.8), -0.5, 0.8)

	_shader_material.set_shader_parameter(PARAM_ANGULAR_YAW_DELTA, _smoothed_yaw_delta)
	_shader_material.set_shader_parameter(PARAM_PITCH_GRAVITY_MOD, pitch_mod)


## Triggers the Dishonored exit sequence: curtain drains top-to-bottom before trailing fade.
## [param duration] Time in seconds for the water streams to drain and dissolve.
func start_surfacing_wipe(duration: float = DEFAULT_WIPE_DURATION) -> void:
	_ensure_shader_material()
	if not is_instance_valid(_shader_material):
		return

	_in_waterfall = false
	_kill_active_tween()
	_prime_camera_inertia()

	var safe_duration: float = maxf(duration, 0.1)
	var dissolve_delay: float = safe_duration * 0.7
	var dissolve_time: float = safe_duration * 0.3

	_shader_material.set_shader_parameter(PARAM_WIPE_PROGRESS, 0.0)
	_shader_material.set_shader_parameter(PARAM_WASH_INTENSITY, 0.3)
	_shader_material.set_shader_parameter(PARAM_VISIBILITY, 1.0)

	show()
	set_process(true)
	print("WaterWipeController: Starting Dishonored exit wipe (duration=", safe_duration, "s).")

	_wipe_tween = create_tween()
	(
		_wipe_tween
		. tween_method(_set_wipe_progress, 0.0, 1.5, safe_duration)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	# Hold full refractive visibility while curtain sweeps; dissolve trailing beads in final 30%
	(
		_wipe_tween
		. parallel()
		. tween_method(_set_visibility, 1.0, 0.0, dissolve_time)
		. set_delay(dissolve_delay)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	_wipe_tween.finished.connect(_on_wipe_tween_finished)


## Engages continuous full-screen water stream waving while inside a waterfall stream.
## [param intensity] Opacity and refraction multiplier for the continuous streams (0.0 to 1.0).
func start_waterfall_wash(intensity: float = 1.0) -> void:
	_ensure_shader_material()
	if not is_instance_valid(_shader_material):
		return

	_in_waterfall = true
	_kill_active_tween()
	_prime_camera_inertia()

	_shader_material.set_shader_parameter(PARAM_WIPE_PROGRESS, 0.0)
	_shader_material.set_shader_parameter(PARAM_WASH_INTENSITY, clampf(intensity, 0.0, 0.4))
	_shader_material.set_shader_parameter(PARAM_VISIBILITY, 1.0)

	show()
	set_process(true)
	print("WaterWipeController: Continuous Dishonored waterfall waving streams engaged.")


## Immediately cancels any active wipe and puts the overlay into zero-cost sleep.
func stop_immediate() -> void:
	_in_waterfall = false
	_kill_active_tween()
	_reset_shader_uniforms()
	set_process(false)
	hide()


## Ensures a valid isolated [ShaderMaterial] with [constant WATER_WIPE_SHADER] is bound.
func _ensure_shader_material() -> void:
	if is_instance_valid(_shader_material):
		return

	if material is ShaderMaterial:
		var existing_mat: ShaderMaterial = material as ShaderMaterial
		if existing_mat.shader == WATER_WIPE_SHADER:
			_shader_material = existing_mat
			return

	_shader_material = ShaderMaterial.new()
	_shader_material.shader = WATER_WIPE_SHADER
	material = _shader_material


## Resets all drainage and motion shader uniforms to neutral drained defaults.
func _reset_shader_uniforms() -> void:
	if not is_instance_valid(_shader_material):
		return
	_shader_material.set_shader_parameter(PARAM_WIPE_PROGRESS, 1.5)
	_shader_material.set_shader_parameter(PARAM_WASH_INTENSITY, 0.0)
	_shader_material.set_shader_parameter(PARAM_VISIBILITY, 0.0)
	_shader_material.set_shader_parameter(PARAM_ANGULAR_YAW_DELTA, 0.0)
	_shader_material.set_shader_parameter(PARAM_PITCH_GRAVITY_MOD, 0.0)


## Connects global [Events] signals for camera registration and water transitions.
func _connect_signals() -> void:
	if not is_instance_valid(Events):
		return
	if not Events.player_camera_registered.is_connected(_on_camera_registered):
		Events.player_camera_registered.connect(_on_camera_registered)
	if Events.has_signal(&"water_sheet_wipe_requested"):
		if not Events.water_sheet_wipe_requested.is_connected(start_surfacing_wipe):
			Events.water_sheet_wipe_requested.connect(start_surfacing_wipe)
	if not Events.waterfall_vfx_toggled.is_connected(_on_waterfall_vfx_toggled):
		Events.waterfall_vfx_toggled.connect(_on_waterfall_vfx_toggled)
	if not Events.underwater_vfx_toggled.is_connected(_on_underwater_vfx_toggled):
		Events.underwater_vfx_toggled.connect(_on_underwater_vfx_toggled)


## Primes camera yaw tracking state prior to activating [method _process].
func _prime_camera_inertia() -> void:
	_smoothed_yaw_delta = 0.0
	var cam: Camera3D = _get_active_camera()
	if is_instance_valid(cam):
		_prev_yaw = cam.global_transform.basis.get_euler().y
		_has_prev_yaw = true
	else:
		_has_prev_yaw = false


## Safely kills the active wipe [Tween] if valid.
func _kill_active_tween() -> void:
	if _wipe_tween and _wipe_tween.is_valid():
		_wipe_tween.kill()
	_wipe_tween = null


## Updates the [constant PARAM_WIPE_PROGRESS] uniform during tween playback.
func _set_wipe_progress(value: float) -> void:
	if is_instance_valid(_shader_material):
		_shader_material.set_shader_parameter(PARAM_WIPE_PROGRESS, value)


## Updates the [constant PARAM_VISIBILITY] uniform during exit dissolution tween playback.
func _set_visibility(value: float) -> void:
	if is_instance_valid(_shader_material):
		_shader_material.set_shader_parameter(PARAM_VISIBILITY, value)


## Disables [method _process] and hides the overlay once streams have fully cleared.
func _on_wipe_tween_finished() -> void:
	if _in_waterfall:
		return
	_reset_shader_uniforms()
	set_process(false)
	hide()
	print("WaterWipeController: Dishonored exit wipe complete, overlay hidden.")


## Caches the newly registered player [Camera3D].
func _on_camera_registered(camera: Camera3D) -> void:
	_cached_camera = camera
	if is_instance_valid(camera):
		_prev_yaw = camera.global_transform.basis.get_euler().y
		_has_prev_yaw = true


## Resolves the active viewport [Camera3D], falling back to viewport lookup if needed.
func _get_active_camera() -> Camera3D:
	if is_instance_valid(_cached_camera) and _cached_camera.is_inside_tree():
		return _cached_camera
	var vp: Viewport = get_viewport()
	_cached_camera = vp.get_camera_3d() if is_instance_valid(vp) else null
	return _cached_camera


## Handles waterfall stream entry and exit transitions from [signal Events.waterfall_vfx_toggled].
func _on_waterfall_vfx_toggled(
	is_active: bool, wash_intensity: float, _clear_progress: float
) -> void:
	if is_active:
		start_waterfall_wash(wash_intensity)
	elif _in_waterfall:
		start_surfacing_wipe(DEFAULT_WIPE_DURATION)


## Cancels active surfacing wipes immediately if the camera submerges underwater again.
func _on_underwater_vfx_toggled(
	is_underwater: bool, _wash_intensity: float, _drop_intensity: float, _clear_progress: float
) -> void:
	if is_underwater:
		stop_immediate()
