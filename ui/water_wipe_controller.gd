## Controls the Dishonored-style screen-space water sheet tearing and meniscus wipe overlay.
## Purely event- and [Tween]-driven with zero per-frame CPU overhead and constant flow speed.
class_name WaterWipeController
extends ColorRect

## Preloaded screen-space water sheet meniscus wipe shader.
const WATER_WIPE_SHADER: Shader = preload("res://vfx/water_sheet_wipe.gdshader")

## Shader uniform identifier for primary downward drainage progression (0.0 to 1.5).
const PARAM_WIPE_PROGRESS: StringName = &"wipe_progress"

## Shader uniform identifier for overall water sheet distortion weight.
const PARAM_WASH_INTENSITY: StringName = &"wash_intensity"

## Shader uniform identifier for fluid visibility fade from 1.0 to 0.0.
const PARAM_VISIBILITY: StringName = &"visibility"

## Default duration in seconds for downward stream drainage and fluid dissolution.
const DEFAULT_WIPE_DURATION: float = 1.4

## Default distortion wash intensity during exit wipe sequence.
const WIPE_WASH_INTENSITY: float = 0.3

## Maximum clamped distortion wash intensity while inside a waterfall stream.
const MAX_WATERFALL_INTENSITY: float = 0.4

## Cached [ShaderMaterial] driving the meniscus wipe shader.
var _shader_material: ShaderMaterial = null

## Active [Tween] orchestrating stream drainage and fluid visibility dissolution.
var _wipe_tween: Tween = null

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
	set_physics_process(false)
	hide()
	print("WaterWipeController: Initialized in zero-cost event-driven state.")


## Disconnects global [Events] signals when removed from the scene tree.
func _exit_tree() -> void:
	_kill_active_tween()
	if not is_instance_valid(Events):
		return
	if Events.has_signal(&"water_sheet_wipe_requested"):
		if Events.water_sheet_wipe_requested.is_connected(start_surfacing_wipe):
			Events.water_sheet_wipe_requested.disconnect(start_surfacing_wipe)
	if Events.waterfall_vfx_toggled.is_connected(_on_waterfall_vfx_toggled):
		Events.waterfall_vfx_toggled.disconnect(_on_waterfall_vfx_toggled)
	if Events.underwater_vfx_toggled.is_connected(_on_underwater_vfx_toggled):
		Events.underwater_vfx_toggled.disconnect(_on_underwater_vfx_toggled)


## Triggers the Dishonored exit sequence: curtain drains top-to-bottom before trailing fade.
## [param duration] Time in seconds for the water streams to drain and dissolve.
func start_surfacing_wipe(duration: float = DEFAULT_WIPE_DURATION) -> void:
	_ensure_shader_material()
	if not is_instance_valid(_shader_material):
		return

	_in_waterfall = false
	_kill_active_tween()

	var safe_duration: float = maxf(duration, 0.1)
	var dissolve_delay: float = safe_duration * 0.7
	var dissolve_time: float = safe_duration * 0.3

	_shader_material.set_shader_parameter(PARAM_WIPE_PROGRESS, 0.0)
	_shader_material.set_shader_parameter(PARAM_WASH_INTENSITY, WIPE_WASH_INTENSITY)
	_shader_material.set_shader_parameter(PARAM_VISIBILITY, 1.0)

	show()
	print("WaterWipeController: Starting Dishonored exit wipe (duration=", safe_duration, "s).")

	_wipe_tween = create_tween()
	(
		_wipe_tween
		. tween_method(_set_wipe_progress, 0.0, 1.5, safe_duration)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	# Hold full distortion while curtain sweeps; dissolve trailing beads in final 30%
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
## [param intensity] Distortion multiplier clamped to [constant MAX_WATERFALL_INTENSITY].
func start_waterfall_wash(intensity: float = MAX_WATERFALL_INTENSITY) -> void:
	_ensure_shader_material()
	if not is_instance_valid(_shader_material):
		return

	_in_waterfall = true
	_kill_active_tween()

	_shader_material.set_shader_parameter(PARAM_WIPE_PROGRESS, 0.0)
	_shader_material.set_shader_parameter(
		PARAM_WASH_INTENSITY, clampf(intensity, 0.0, MAX_WATERFALL_INTENSITY)
	)
	_shader_material.set_shader_parameter(PARAM_VISIBILITY, 1.0)

	show()
	print("WaterWipeController: Continuous Dishonored waterfall waving streams engaged.")


## Immediately cancels any active wipe and puts the overlay into zero-cost sleep.
func stop_immediate() -> void:
	_in_waterfall = false
	_kill_active_tween()
	_reset_shader_uniforms()
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


## Resets all drainage and distortion shader uniforms to neutral drained defaults.
func _reset_shader_uniforms() -> void:
	if not is_instance_valid(_shader_material):
		return
	_shader_material.set_shader_parameter(PARAM_WIPE_PROGRESS, 1.5)
	_shader_material.set_shader_parameter(PARAM_WASH_INTENSITY, 0.0)
	_shader_material.set_shader_parameter(PARAM_VISIBILITY, 0.0)


## Connects global [Events] signals for water transitions.
func _connect_signals() -> void:
	if not is_instance_valid(Events):
		return
	if Events.has_signal(&"water_sheet_wipe_requested"):
		if not Events.water_sheet_wipe_requested.is_connected(start_surfacing_wipe):
			Events.water_sheet_wipe_requested.connect(start_surfacing_wipe)
	if not Events.waterfall_vfx_toggled.is_connected(_on_waterfall_vfx_toggled):
		Events.waterfall_vfx_toggled.connect(_on_waterfall_vfx_toggled)
	if not Events.underwater_vfx_toggled.is_connected(_on_underwater_vfx_toggled):
		Events.underwater_vfx_toggled.connect(_on_underwater_vfx_toggled)


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


## Hides the overlay once streams have fully cleared.
func _on_wipe_tween_finished() -> void:
	if _in_waterfall:
		return
	_reset_shader_uniforms()
	hide()
	print("WaterWipeController: Dishonored exit wipe complete, overlay hidden.")


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
