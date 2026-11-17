@tool
class_name FireFlipbookEmitter
extends Node3D
## Drives a live-previewed fire pit with flipbook flame, rising smoke, and heat distortion.
##
## Runs in the editor via [code]@tool[/code] and gates runtime [OmniLight3D] flicker via
## [VisibleOnScreenNotifier3D]. Assigns Render Layer 10 to all volumetric emitters.

## Enables or disables fire, smoke, heat distortion, and light emission.
@export var is_active: bool = true:
	set(value):
		is_active = value
		if is_inside_tree():
			_apply_active_state()
## Base light energy when idle.
@export var base_energy: float = 2.2
## Maximum random energy offset applied per flicker step.
@export var flicker_amplitude: float = 0.45
## Average duration in seconds between flicker targets.
@export var flicker_interval: float = 0.08
## Base color of the [OmniLight3D].
@export var light_color: Color = Color(1.0, 0.6, 0.24, 1.0)

var _flicker_tween: Tween = null
var _is_visible_on_screen: bool = true

@onready var _light: OmniLight3D = $FireLight
@onready var _particles: GPUParticles3D = $FlameParticles
@onready var _smoke: GPUParticles3D = $SmokeParticles
@onready var _heat_distortion: GasLeakEmitter = $HeatDistortion
@onready var _visibility_notifier: VisibleOnScreenNotifier3D = $VisibilityNotifier


## Initializes emitters, render layers, light state, and visibility gating.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(_light), "FireFlipbookEmitter requires FireLight child.")
	assert(is_instance_valid(_particles), "FireFlipbookEmitter requires FlameParticles child.")
	assert(is_instance_valid(_smoke), "FireFlipbookEmitter requires SmokeParticles child.")
	assert(
		is_instance_valid(_heat_distortion), "FireFlipbookEmitter requires HeatDistortion child."
	)
	assert(
		is_instance_valid(_visibility_notifier),
		"FireFlipbookEmitter requires VisibilityNotifier child."
	)
	assert(base_energy >= 0.0, "base_energy must be non-negative.")

	_particles.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
	_smoke.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
	_heat_distortion.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
	_light.light_color = light_color
	_light.light_energy = base_energy

	if not Engine.is_editor_hint():
		Utilities.safe_connect(_visibility_notifier.screen_entered, _on_screen_entered)
		Utilities.safe_connect(_visibility_notifier.screen_exited, _on_screen_exited)
		_is_visible_on_screen = _visibility_notifier.is_on_screen()
	else:
		_is_visible_on_screen = true

	_apply_active_state()


## Cleans up active flicker tween when leaving the scene tree.
func _exit_tree() -> void:
	if is_instance_valid(_flicker_tween):
		_flicker_tween.kill()


## Applies [member is_active] to all child emitters and light flicker.
func _apply_active_state() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_particles):
		_particles.emitting = is_active
	if is_instance_valid(_smoke):
		_smoke.emitting = is_active
	if is_instance_valid(_heat_distortion):
		_heat_distortion.is_leaking = is_active
	if is_instance_valid(_light):
		_light.visible = is_active
	if is_active and _is_visible_on_screen:
		_schedule_next_flicker()
	elif is_instance_valid(_flicker_tween):
		_flicker_tween.kill()


## Resumes light flicker when the emitter enters the camera frustum.
func _on_screen_entered() -> void:
	_is_visible_on_screen = true
	if is_active:
		_schedule_next_flicker()


## Pauses light flicker when the emitter exits the camera frustum.
func _on_screen_exited() -> void:
	_is_visible_on_screen = false
	if is_instance_valid(_flicker_tween):
		_flicker_tween.kill()


## Schedules the next randomized [Tween] step for [member _light] energy.
func _schedule_next_flicker() -> void:
	if (
		not is_active
		or not _is_visible_on_screen
		or not is_inside_tree()
		or not is_instance_valid(_light)
	):
		return
	if is_instance_valid(_flicker_tween):
		_flicker_tween.kill()

	var target_energy: float = maxf(
		0.1, base_energy + randf_range(-flicker_amplitude, flicker_amplitude)
	)
	var step_duration: float = flicker_interval * randf_range(0.7, 1.3)

	_flicker_tween = create_tween()
	_flicker_tween.set_trans(Tween.TRANS_SINE)
	_flicker_tween.set_ease(Tween.EASE_IN_OUT)
	_flicker_tween.tween_property(_light, ^"light_energy", target_energy, step_duration)
	_flicker_tween.tween_callback(_schedule_next_flicker)
