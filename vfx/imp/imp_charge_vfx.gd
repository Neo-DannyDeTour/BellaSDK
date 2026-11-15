@tool
## Telegraph charging aura and crackling electric sparks around the Imp before firing.
class_name ImpChargeVFX
extends Node3D

## Emitted when a timed charge sequence finishes.
signal charge_completed

## Default render layer mask (Layer 1 Environment + Layer 10 Volumetrics).
const DEFAULT_RENDER_LAYERS: int = (1 << 0) | (1 << 9)

## Crackling lightning flipbook particle emitter.
@onready var _aura_particles: GPUParticles3D = $AuraParticles
## Secondary radial electric spark particle emitter.
@onready var _spark_particles: GPUParticles3D = $SparkParticles

var _tween: Tween = null


## Initializes render layers and disables per-frame processing.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(_aura_particles != null, "ImpChargeVFX: Missing AuraParticles child.")
	assert(_spark_particles != null, "ImpChargeVFX: Missing SparkParticles child.")
	_aura_particles.layers = DEFAULT_RENDER_LAYERS
	_spark_particles.layers = DEFAULT_RENDER_LAYERS
	if not Engine.is_editor_hint():
		stop_charge()


## Starts the telegraph charging aura for [param duration] seconds (<= 0 loops until stopped).
func start_charge(duration: float = 0.75) -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	print("ImpChargeVFX: Starting charge telegraph for ", duration, "s")
	visible = true
	_aura_particles.emitting = true
	_spark_particles.emitting = true

	if _tween != null and _tween.is_valid():
		_tween.kill()
	if duration > 0.0:
		_tween = create_tween()
		_tween.tween_interval(duration)
		_tween.tween_callback(_on_charge_timer_done)


## Immediately stops the charging aura and spark emitters.
func stop_charge() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if is_instance_valid(_aura_particles):
		_aura_particles.emitting = false
	if is_instance_valid(_spark_particles):
		_spark_particles.emitting = false
	visible = false


## Stops particles and emits [signal charge_completed].
func _on_charge_timer_done() -> void:
	stop_charge()
	charge_completed.emit()
