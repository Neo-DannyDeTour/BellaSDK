## Full-screen HL2-style harsh black-and-white dream sequence contrast controller.
## Attach directly to a full-screen [ColorRect] with [code]harsh_contrast_transition.gdshader[/code]
# class_name HarshContrastEffect
extends ColorRect

## Emitted when a contrast transition pulse finishes and returns to idle state.
signal pulse_finished

## Preloaded harsh contrast transition screen-space shader.
const CONTRAST_SHADER: Shader = preload("res://vfx/harsh_contrast_transition.gdshader")

## Shader uniform identifier for overall contrast effect blend weight [0.0, 1.0].
const PARAM_INTENSITY: StringName = &"intensity"

## Shader uniform identifier for luminance cutoff threshold [0.0, 1.0].
const PARAM_THRESHOLD: StringName = &"threshold"

## Shader uniform identifier for transition edge softness band.
const PARAM_SOFTNESS: StringName = &"softness"

## Shader uniform identifier for high-frequency jitter shake strength.
const PARAM_JITTER: StringName = &"jitter_strength"

## Shader uniform identifier for white boost flash during peak pulse.
const PARAM_FLASH_BOOST: StringName = &"flash_boost"

## Active [Tween] orchestrating contrast wave transition and decay.
var _tween: Tween = null

## Cached [ShaderMaterial] driving the harsh contrast shader.
var _shader_mat: ShaderMaterial = null


## Validates shader material assignment, connects [Events], and disables idle processing.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	set_physics_process(false)
	_ensure_shader_material()
	assert(is_instance_valid(_shader_mat), "HarshContrastEffect requires a ShaderMaterial.")
	_shader_mat.set_shader_parameter(PARAM_INTENSITY, 0.0)
	_shader_mat.set_shader_parameter(PARAM_THRESHOLD, 0.45)
	_shader_mat.set_shader_parameter(PARAM_SOFTNESS, 0.04)
	_shader_mat.set_shader_parameter(PARAM_FLASH_BOOST, 0.0)
	_connect_signals()
	visible = false


## Disconnects global [Events] signals and kills active tweens on tree exit.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_tween)
	_tween = null
	if not is_instance_valid(Events):
		return
	if Events.has_signal(&"harsh_contrast_pulse_requested"):
		if Events.harsh_contrast_pulse_requested.is_connected(_on_pulse_requested):
			Events.harsh_contrast_pulse_requested.disconnect(_on_pulse_requested)
	if Events.has_signal(&"harsh_contrast_intensity_requested"):
		if Events.harsh_contrast_intensity_requested.is_connected(set_sustained_intensity):
			Events.harsh_contrast_intensity_requested.disconnect(set_sustained_intensity)


## Triggers a dynamic harsh contrast pulse that flashes in and decays smoothly.
func trigger_contrast_pulse(
	duration: float = 1.4,
	peak: float = 1.0,
	target_threshold: float = 0.45,
	peak_flash: float = 0.3
) -> void:
	var safe_duration: float = maxf(duration, 0.1)
	var safe_peak: float = clampf(peak, 0.0, 1.0)
	var safe_threshold: float = clampf(target_threshold, 0.0, 1.0)
	var safe_flash: float = clampf(peak_flash, 0.0, 1.0)
	print(
		"HarshContrastEffect: pulse triggered (duration=",
		safe_duration,
		", peak=",
		safe_peak,
		", threshold=",
		safe_threshold,
		")"
	)
	_ensure_shader_material()
	if not is_instance_valid(_shader_mat):
		return

	_shader_mat.set_shader_parameter(PARAM_THRESHOLD, safe_threshold)
	visible = true
	_tween = Utilities.reset_tween(self, _tween)
	if not is_instance_valid(_tween):
		return

	var in_time: float = safe_duration * 0.2
	var out_time: float = safe_duration * 0.8

	_tween.set_parallel(true)
	_tween.tween_method(_set_intensity, 0.0, safe_peak, in_time).set_trans(Tween.TRANS_EXPO)
	if safe_flash > 0.001:
		_tween.tween_method(_set_flash_boost, 0.0, safe_flash, in_time).set_trans(Tween.TRANS_QUAD)

	var seq_tween: Tween = _tween.chain()
	seq_tween.set_parallel(true)
	seq_tween.tween_method(_set_intensity, safe_peak, 0.0, out_time).set_trans(Tween.TRANS_SINE)
	if safe_flash > 0.001:
		seq_tween.tween_method(_set_flash_boost, safe_flash, 0.0, out_time * 0.5).set_trans(
			Tween.TRANS_QUAD
		)

	_tween.chain().tween_callback(_on_effect_finished)


## Sets sustained harsh contrast intensity directly without tweening.
func set_sustained_intensity(
	intensity: float, custom_threshold: float = 0.45, custom_softness: float = 0.04
) -> void:
	var clamped: float = clampf(intensity, 0.0, 1.0)
	print("HarshContrastEffect: sustained intensity set -> ", clamped)
	_ensure_shader_material()
	if not is_instance_valid(_shader_mat):
		return

	Utilities.safe_kill_tween(_tween)
	_tween = null

	_shader_mat.set_shader_parameter(PARAM_THRESHOLD, clampf(custom_threshold, 0.0, 1.0))
	_shader_mat.set_shader_parameter(PARAM_SOFTNESS, clampf(custom_softness, 0.001, 0.5))
	_shader_mat.set_shader_parameter(PARAM_FLASH_BOOST, 0.0)
	_set_intensity(clamped)
	visible = clamped > 0.001


## Ensures a valid [ShaderMaterial] with [constant CONTRAST_SHADER] is bound.
func _ensure_shader_material() -> void:
	if is_instance_valid(_shader_mat):
		return
	if material is ShaderMaterial:
		var existing_mat: ShaderMaterial = material as ShaderMaterial
		if existing_mat.shader == CONTRAST_SHADER or is_instance_valid(existing_mat.shader):
			_shader_mat = existing_mat
			return
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = CONTRAST_SHADER
	material = _shader_mat


## Connects global [Events] signals for harsh contrast pulse and sustained requests.
func _connect_signals() -> void:
	if not is_instance_valid(Events):
		return
	if Events.has_signal(&"harsh_contrast_pulse_requested"):
		Utilities.safe_connect(Events.harsh_contrast_pulse_requested, _on_pulse_requested)
	if Events.has_signal(&"harsh_contrast_intensity_requested"):
		Utilities.safe_connect(Events.harsh_contrast_intensity_requested, _on_intensity_requested)


## Handles [signal Events.harsh_contrast_pulse_requested].
func _on_pulse_requested(
	duration: float = 1.4,
	peak: float = 1.0,
	target_threshold: float = 0.45,
	peak_flash: float = 0.3
) -> void:
	trigger_contrast_pulse(duration, peak, target_threshold, peak_flash)


## Handles [signal Events.harsh_contrast_intensity_requested].
func _on_intensity_requested(
	intensity: float, custom_threshold: float = 0.45, custom_softness: float = 0.04
) -> void:
	set_sustained_intensity(intensity, custom_threshold, custom_softness)


## Sets the shader intensity uniform directly.
func _set_intensity(value: float) -> void:
	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_INTENSITY, value)


## Sets the shader flash boost uniform directly.
func _set_flash_boost(value: float) -> void:
	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_FLASH_BOOST, value)


## Disables node visibility when pulse finishes to eliminate screen-copy overhead.
func _on_effect_finished() -> void:
	visible = false
	pulse_finished.emit()
	if is_instance_valid(Events) and Events.has_signal(&"harsh_contrast_pulse_finished"):
		Events.harsh_contrast_pulse_finished.emit()
