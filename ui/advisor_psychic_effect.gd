## Full-screen HL2 Episode Two Advisor psychic attack distortion controller.
## Attach directly to a full-screen [ColorRect] with [code]advisor_psychic.gdshader[/code].
# class_name AdvisorPsychicEffect
extends ColorRect

## Emitted when a psychic pulse animation finishes and returns to idle state.
signal pulse_finished

## Preloaded Advisor psychic distortion screen-space shader.
const ADVISOR_SHADER: Shader = preload("res://vfx/advisor_psychic.gdshader")

## Shader uniform identifier for overall psychic distortion weight [0.0, 1.0].
const PARAM_INTENSITY: StringName = &"intensity"

## Shader uniform identifier for radial zoom blur focal UV coordinates.
const PARAM_CENTER_UV: StringName = &"center_uv"

## Default screen-center UV coordinate for radial blur origin.
const DEFAULT_CENTER: Vector2 = Vector2(0.5, 0.5)

## Active [Tween] orchestrating psychic wave spike and decay.
var _tween: Tween = null

## Cached [ShaderMaterial] driving the psychic screen distortion shader.
var _shader_mat: ShaderMaterial = null


## Validates shader material assignment, connects [Events], and disables idle processing.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	set_physics_process(false)
	_ensure_shader_material()
	assert(is_instance_valid(_shader_mat), "AdvisorPsychicEffect requires a ShaderMaterial.")
	_shader_mat.set_shader_parameter(PARAM_INTENSITY, 0.0)
	_shader_mat.set_shader_parameter(PARAM_CENTER_UV, DEFAULT_CENTER)
	_connect_signals()
	visible = false


## Disconnects global [Events] signals and kills active tweens on tree exit.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_tween)
	_tween = null
	if not is_instance_valid(Events):
		return
	if Events.has_signal(&"advisor_psychic_pulse_requested"):
		if Events.advisor_psychic_pulse_requested.is_connected(_on_pulse_requested):
			Events.advisor_psychic_pulse_requested.disconnect(_on_pulse_requested)
	if Events.has_signal(&"advisor_psychic_pulse_from_requested"):
		if Events.advisor_psychic_pulse_from_requested.is_connected(_on_pulse_from_requested):
			Events.advisor_psychic_pulse_from_requested.disconnect(_on_pulse_from_requested)
	if Events.has_signal(&"advisor_psychic_intensity_requested"):
		if Events.advisor_psychic_intensity_requested.is_connected(set_sustained_intensity):
			Events.advisor_psychic_intensity_requested.disconnect(set_sustained_intensity)


## Triggers a psychic attack wave that spikes rapidly and decays over [param duration].
func trigger_psychic_pulse(duration: float = 1.2, peak: float = 1.0) -> void:
	var safe_duration: float = maxf(duration, 0.1)
	var safe_peak: float = clampf(peak, 0.0, 1.0)
	print(
		"AdvisorPsychicEffect: pulse triggered (duration=", safe_duration, ", peak=", safe_peak, ")"
	)
	_ensure_shader_material()
	if not is_instance_valid(_shader_mat):
		return

	visible = true
	_tween = Utilities.reset_tween(self, _tween)
	if not is_instance_valid(_tween):
		return
	_tween.tween_method(_set_intensity, 0.0, safe_peak, safe_duration * 0.15).set_trans(
		Tween.TRANS_EXPO
	)
	_tween.tween_method(_set_intensity, safe_peak, 0.0, safe_duration * 0.85).set_trans(
		Tween.TRANS_SINE
	)
	_tween.tween_callback(_on_effect_finished)


## Anchors focal UV to [param source_node] and triggers a psychic pulse wave.
func trigger_psychic_pulse_from_node(
	source_node: Node3D, duration: float = 1.2, peak: float = 1.0
) -> void:
	if is_instance_valid(source_node):
		set_source_world_pos(source_node.global_position)
	else:
		_ensure_shader_material()
		if is_instance_valid(_shader_mat):
			_shader_mat.set_shader_parameter(PARAM_CENTER_UV, DEFAULT_CENTER)
	trigger_psychic_pulse(duration, peak)


## Sets sustained psychic distortion [param intensity] directly or hides when zero.
func set_sustained_intensity(intensity: float) -> void:
	_ensure_shader_material()
	if not is_instance_valid(_shader_mat):
		return
	Utilities.safe_kill_tween(_tween)
	_tween = null
	var clamped: float = clampf(intensity, 0.0, 1.0)
	print("AdvisorPsychicEffect: sustained intensity set -> ", clamped)
	if clamped <= 0.001:
		_set_intensity(0.0)
		_shader_mat.set_shader_parameter(PARAM_CENTER_UV, DEFAULT_CENTER)
		visible = false
	else:
		visible = true
		_set_intensity(clamped)


## Updates psychic distortion intensity using squared proximity between player and source.
func set_intensity_from_distance(
	player_pos: Vector3, source_pos: Vector3, max_radius: float
) -> void:
	var max_radius_sq: float = max_radius * max_radius
	var dist_sq: float = player_pos.distance_squared_to(source_pos)
	if dist_sq >= max_radius_sq or max_radius_sq <= 0.0:
		_set_intensity(0.0)
		visible = false
		return

	Utilities.safe_kill_tween(_tween)
	_tween = null

	var weight: float = 1.0 - (dist_sq / max_radius_sq)
	visible = true
	_set_intensity(clampf(weight, 0.0, 1.0))


## Projects a 3D world position to screen UV to anchor the radial blur focal point.
func set_source_world_pos(world_pos: Vector3) -> void:
	_ensure_shader_material()
	if not is_instance_valid(_shader_mat):
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos):
		_shader_mat.set_shader_parameter(PARAM_CENTER_UV, DEFAULT_CENTER)
		return

	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	var vp_size: Vector2 = vp.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	var uv: Vector2 = (screen_pos / vp_size).clamp(Vector2.ZERO, Vector2.ONE)
	_shader_mat.set_shader_parameter(PARAM_CENTER_UV, uv)


## Ensures a valid [ShaderMaterial] with [constant ADVISOR_SHADER] is bound.
func _ensure_shader_material() -> void:
	if is_instance_valid(_shader_mat):
		return
	if material is ShaderMaterial:
		var existing_mat: ShaderMaterial = material as ShaderMaterial
		if existing_mat.shader == ADVISOR_SHADER or is_instance_valid(existing_mat.shader):
			_shader_mat = existing_mat
			return
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = ADVISOR_SHADER
	material = _shader_mat


## Connects global [Events] signals for psychic pulse and sustained distortion requests.
func _connect_signals() -> void:
	if not is_instance_valid(Events):
		return
	if Events.has_signal(&"advisor_psychic_pulse_requested"):
		Utilities.safe_connect(Events.advisor_psychic_pulse_requested, _on_pulse_requested)
	if Events.has_signal(&"advisor_psychic_pulse_from_requested"):
		Utilities.safe_connect(
			Events.advisor_psychic_pulse_from_requested, _on_pulse_from_requested
		)
	if Events.has_signal(&"advisor_psychic_intensity_requested"):
		Utilities.safe_connect(Events.advisor_psychic_intensity_requested, set_sustained_intensity)


## Handles [signal Events.advisor_psychic_pulse_requested] with UV center, duration, and peak.
func _on_pulse_requested(
	duration: float = 1.2, peak: float = 1.0, center_uv: Vector2 = DEFAULT_CENTER
) -> void:
	_ensure_shader_material()
	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(
			PARAM_CENTER_UV, center_uv.clamp(Vector2.ZERO, Vector2.ONE)
		)
	trigger_psychic_pulse(duration, peak)


## Handles [signal Events.advisor_psychic_pulse_from_requested] projecting 3D node position.
func _on_pulse_from_requested(
	source_node: Node3D, duration: float = 1.2, peak: float = 1.0
) -> void:
	trigger_psychic_pulse_from_node(source_node, duration, peak)


## Sets the shader intensity uniform directly.
func _set_intensity(value: float) -> void:
	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_INTENSITY, value)


## Disables node visibility when pulse finishes to stop screen-copy overhead.
func _on_effect_finished() -> void:
	visible = false
	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_CENTER_UV, DEFAULT_CENTER)
	pulse_finished.emit()
	if is_instance_valid(Events) and Events.has_signal(&"advisor_psychic_pulse_finished"):
		Events.advisor_psychic_pulse_finished.emit()
