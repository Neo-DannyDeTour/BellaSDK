## Synchronized multi-emitter explosion controller implementing R4 Crysis specifications.
## Coordinates CoreFireball flipbook, LingeringSmoke plumes, ballistic sparks,
## omni light flash collapse, and screen-space heat distortion shockwave.
class_name ExplosionCrysis
extends Node3D

## Emitted when the detonation sequence starts.
signal detonation_started(origin: Vector3)

## Emitted when all particle emitters and transient passes finish emission.
signal detonation_finished(explosion_node: ExplosionCrysis)

## Pre-allocated instance uniform for shockwave progress.
const PARAM_PROGRESS: StringName = &"explosion_progress"
## Pre-allocated instance uniform for shockwave refraction distortion strength.
const PARAM_DISTORTION: StringName = &"distortion_strength"

## Peak detonation flash light energy.
const FLASH_PEAK_ENERGY: float = 16.0
## Duration in seconds of the omni light flash decay.
const FLASH_DURATION: float = 0.15
## Duration in seconds of the primary core fireball explosion.
const FIREBALL_DURATION: float = 1.1
## Duration in seconds of the screen-space refractive shockwave.
const SHOCKWAVE_DURATION: float = 0.4
## Maximum particle lifetime across emitters in seconds.
const MAX_PARTICLE_LIFETIME: float = 3.5
## Safety buffer in seconds before triggering node cleanup.
const CLEANUP_BUFFER: float = 0.3

## Automatically triggers detonation upon entering the scene tree.
@export var auto_play: bool = true
## Automatically frees the node from the tree once all emitters complete.
@export var free_on_finish: bool = true

## Active [Tween] managing flash decay and shockwave expansion.
var _active_tween: Tween = null
## Active [Tween] managing lifecycle timeout and deferred freeing.
var _cleanup_tween: Tween = null
## Flag indicating whether a detonation sequence is actively running.
var _is_detonating: bool = false

## Primary 8x8 flipbook core fireball emitter.
@onready var core_fireball: GPUParticles3D = $CoreFireball
## Slow rising lingering smoke puff emitter.
@onready var lingering_smoke: GPUParticles3D = $LingeringSmoke
## Ballistic high-speed bouncing sparks emitter.
@onready var sparks_and_debris: GPUParticles3D = $SparksAndDebris
## Transient warm orange detonation omni light.
@onready var detonation_flash: OmniLight3D = $DetonationFlash
## Refractive screen distortion shockwave sphere mesh.
@onready var heat_distortion: MeshInstance3D = $HeatDistortion


## Validates child node invariants, disables per-frame polling, and triggers auto-play.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(is_instance_valid(core_fireball), "ExplosionCrysis: missing CoreFireball.")
	assert(is_instance_valid(lingering_smoke), "ExplosionCrysis: missing LingeringSmoke.")
	assert(is_instance_valid(sparks_and_debris), "ExplosionCrysis: missing SparksAndDebris.")
	assert(is_instance_valid(detonation_flash), "ExplosionCrysis: missing DetonationFlash.")
	assert(is_instance_valid(heat_distortion), "ExplosionCrysis: missing HeatDistortion.")

	if auto_play:
		explode()
	else:
		reset()


## Ensures active tweens are cleanly killed when removed from the scene tree.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_active_tween)
	_active_tween = null
	Utilities.safe_kill_tween(_cleanup_tween)
	_cleanup_tween = null


## Triggers synchronized emission across all particle passes and begins tween sequences.
func explode() -> void:
	if not is_inside_tree():
		return

	_is_detonating = true
	detonation_started.emit(global_position)
	print("ExplosionCrysis: detonated at ", global_position)

	if is_instance_valid(core_fireball):
		core_fireball.one_shot = false
		core_fireball.restart()
		core_fireball.emitting = true
	if is_instance_valid(lingering_smoke):
		lingering_smoke.restart()
		lingering_smoke.emitting = true
	if is_instance_valid(sparks_and_debris):
		sparks_and_debris.restart()
		sparks_and_debris.emitting = true

	if is_instance_valid(detonation_flash):
		detonation_flash.visible = true
		detonation_flash.light_energy = FLASH_PEAK_ENERGY

	if is_instance_valid(heat_distortion):
		heat_distortion.visible = true
		heat_distortion.scale = Vector3(0.2, 0.2, 0.2)
		heat_distortion.set_instance_shader_parameter(PARAM_PROGRESS, 0.0)
		heat_distortion.set_instance_shader_parameter(PARAM_DISTORTION, 0.06)

	_start_detonation_tween()
	_schedule_lifecycle_cleanup()


## Alias for [method explode] maintaining backwards compatibility.
func detonate() -> void:
	explode()


## Stops active emissions, restores initial component states, and cancels tweens.
func reset() -> void:
	_is_detonating = false
	Utilities.safe_kill_tween(_active_tween)
	_active_tween = null
	Utilities.safe_kill_tween(_cleanup_tween)
	_cleanup_tween = null

	if is_instance_valid(core_fireball):
		core_fireball.emitting = false
		core_fireball.one_shot = true
	if is_instance_valid(lingering_smoke):
		lingering_smoke.emitting = false
	if is_instance_valid(sparks_and_debris):
		sparks_and_debris.emitting = false

	if is_instance_valid(detonation_flash):
		detonation_flash.visible = false
		detonation_flash.light_energy = 0.0

	if is_instance_valid(heat_distortion):
		heat_distortion.visible = false
		heat_distortion.scale = Vector3(0.2, 0.2, 0.2)
		heat_distortion.set_instance_shader_parameter(PARAM_PROGRESS, 0.0)


## Drives light collapse and shockwave scaling using a synchronized C++ [Tween].
func _start_detonation_tween() -> void:
	_active_tween = Utilities.reset_tween(self, _active_tween)
	if not is_instance_valid(_active_tween):
		return

	_active_tween.set_parallel(true)

	(
		_active_tween
		. tween_property(detonation_flash, "light_energy", 0.0, FLASH_DURATION)
		. set_trans(Tween.TRANS_EXPO)
		. set_ease(Tween.EASE_OUT)
	)

	_active_tween.tween_callback(_on_flash_complete).set_delay(FLASH_DURATION)
	_active_tween.tween_callback(_on_fireball_complete).set_delay(FIREBALL_DURATION)

	(
		_active_tween
		. tween_property(heat_distortion, "scale", Vector3(12.0, 12.0, 12.0), SHOCKWAVE_DURATION)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)

	(
		_active_tween
		. tween_method(_update_shockwave_progress, 0.0, 1.0, SHOCKWAVE_DURATION)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	_active_tween.tween_callback(_on_shockwave_complete).set_delay(SHOCKWAVE_DURATION)


## Updates per-instance shockwave progress parameter on [member heat_distortion].
func _update_shockwave_progress(progress: float) -> void:
	if is_instance_valid(heat_distortion):
		heat_distortion.set_instance_shader_parameter(PARAM_PROGRESS, progress)


## Hides transient detonation flash upon decay tween completion.
func _on_flash_complete() -> void:
	if is_instance_valid(detonation_flash):
		detonation_flash.visible = false


## Terminates fireball emission cycle and restores one_shot flag.
func _on_fireball_complete() -> void:
	if is_instance_valid(core_fireball):
		core_fireball.emitting = false
		core_fireball.one_shot = true


## Hides transient shockwave mesh upon expansion tween completion.
func _on_shockwave_complete() -> void:
	if is_instance_valid(heat_distortion):
		heat_distortion.visible = false


## Schedules deferred lifecycle cleanup once the longest particle pass completes.
func _schedule_lifecycle_cleanup() -> void:
	_cleanup_tween = Utilities.reset_tween(self, _cleanup_tween)
	if not is_instance_valid(_cleanup_tween):
		return
	var total_time: float = MAX_PARTICLE_LIFETIME + CLEANUP_BUFFER
	_cleanup_tween.tween_interval(total_time)
	_cleanup_tween.tween_callback(_on_detonation_lifecycle_finished)


## Emits [signal detonation_finished] and queues node destruction if enabled.
func _on_detonation_lifecycle_finished() -> void:
	_is_detonating = false
	detonation_finished.emit(self)
	if free_on_finish and is_inside_tree():
		queue_free()
