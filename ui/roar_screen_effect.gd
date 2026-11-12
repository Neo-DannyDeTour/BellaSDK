## Controls the full-screen radial shockwave and blur shader during monster roars.
## Triggered via [signal Events.monster_roared].
# class_name RoarScreenEffect
extends ColorRect

## Shader uniform name for overall effect intensity.
const PARAM_INTENSITY: StringName = &"intensity"

## Attack ramp-up duration in seconds.
const ATTACK_DURATION: float = 0.1

## Decay fade-out duration in seconds.
const DECAY_DURATION: float = 0.3

## Active [Tween] animating the roar shockwave envelope.
var _tween: Tween

## Cached [ShaderMaterial] driving the shockwave distortion shader.
var _shader_mat: ShaderMaterial


## Validates [ShaderMaterial] assignment, disables per-frame ticks, and connects [Events].
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_shader_mat = material as ShaderMaterial
	assert(_shader_mat != null, "RoarScreenEffect requires a ShaderMaterial assigned to material.")

	_set_intensity(0.0)
	if is_instance_valid(Events):
		Utilities.safe_connect(Events.monster_roared, _on_monster_roared)


## Disconnects global signals when removed from the scene tree.
func _exit_tree() -> void:
	if is_instance_valid(Events) and Events.monster_roared.is_connected(_on_monster_roared):
		Events.monster_roared.disconnect(_on_monster_roared)
	Utilities.safe_kill_tween(_tween)
	_tween = null


## Triggers the roar envelope: attack -> sustain -> decay.
func _on_monster_roared(duration: float) -> void:
	var sustain_time: float = maxf(0.0, duration)
	print("RoarScreenEffect: triggered (sustain=%.2fs)" % sustain_time)

	_tween = Utilities.reset_tween(self, _tween)
	if not is_instance_valid(_tween):
		return

	visible = true
	(
		_tween
		. tween_method(_set_intensity, 0.0, 1.0, ATTACK_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	if sustain_time > 0.0:
		_tween.tween_interval(sustain_time)
	(
		_tween
		. tween_method(_set_intensity, 1.0, 0.0, DECAY_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	_tween.tween_callback(_on_roar_finished)


## Updates the shader intensity uniform.
func _set_intensity(value: float) -> void:
	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_INTENSITY, value)


## Hides the [ColorRect] once the decay tween completes to eliminate idle fill-rate cost.
func _on_roar_finished() -> void:
	visible = false
	print("RoarScreenEffect: finished")
