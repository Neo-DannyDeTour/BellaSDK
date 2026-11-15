@tool
## Plays the Imp Mantaflow plasma explosion flipbook and expanding electric shockwave.
class_name ImpExplosionVFX
extends Node3D

## Emitted when the explosion burst and shockwave finish playing.
signal explosion_finished

## Default render layer mask (Layer 1 Environment + Layer 10 Volumetrics).
const DEFAULT_RENDER_LAYERS: int = (1 << 0) | (1 << 9)
## Shader uniform for shockwave expansion progress.
const PARAM_EXPAND_PROGRESS: StringName = &"expand_progress"
## Shader uniform for shockwave active phase.
const PARAM_ACTIVE_PHASE: StringName = &"active_phase"
## Shader uniform for shockwave fade alpha.
const PARAM_FADE_ALPHA: StringName = &"fade_alpha"

## Flipbook particle burst node.
@onready var _flipbook_particles: GPUParticles3D = $FlipbookParticles
## Ground/air shockwave ring mesh.
@onready var _shockwave_mesh: MeshInstance3D = $ShockwaveMesh

var _tween: Tween = null


## Initializes render layers and disables per-frame processing.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(_flipbook_particles != null, "ImpExplosionVFX: Missing FlipbookParticles child.")
	assert(_shockwave_mesh != null, "ImpExplosionVFX: Missing ShockwaveMesh child.")
	_flipbook_particles.layers = DEFAULT_RENDER_LAYERS
	_shockwave_mesh.layers = DEFAULT_RENDER_LAYERS
	if not Engine.is_editor_hint():
		_shockwave_mesh.visible = false


## Triggers the Mantaflow explosion flipbook and shockwave at [param world_pos].
func trigger_explosion(world_pos: Vector3, scale_factor: float = 1.0) -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	print("ImpExplosionVFX: Triggering explosion at ", world_pos)
	global_position = world_pos
	scale = Vector3.ONE * maxf(scale_factor, 0.1)

	_flipbook_particles.restart()
	_flipbook_particles.emitting = true

	var mat: ShaderMaterial = _shockwave_mesh.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(PARAM_ACTIVE_PHASE, 1.0)
		mat.set_shader_parameter(PARAM_EXPAND_PROGRESS, 0.0)
		mat.set_shader_parameter(PARAM_FADE_ALPHA, 1.0)
	_shockwave_mesh.visible = true

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	if mat != null:
		_tween.tween_method(
			func(val: float) -> void: mat.set_shader_parameter(PARAM_EXPAND_PROGRESS, val),
			0.0,
			1.0,
			0.45
		)
		_tween.tween_method(
			func(val: float) -> void: mat.set_shader_parameter(PARAM_FADE_ALPHA, val),
			1.0,
			0.0,
			0.45
		)
	_tween.chain().tween_callback(_on_explosion_complete)


## Hides the shockwave mesh and emits [signal explosion_finished].
func _on_explosion_complete() -> void:
	if is_instance_valid(_shockwave_mesh):
		_shockwave_mesh.visible = false
	explosion_finished.emit()
