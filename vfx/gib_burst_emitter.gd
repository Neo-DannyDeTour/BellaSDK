## Single-shot billboard flipbook emitter for radial gibbing and viscera splatter bursts.
##
## Drives [member anim_progress], [member ichor_tint], and [member rot_angle] via per-instance
## shader parameters on a [QuadMesh] child without duplicating materials.
class_name GibBurstEmitter
extends Node3D

## Per-instance shader parameter name for normalized flipbook playback progress.
const PARAM_ANIM_PROGRESS: StringName = &"anim_progress"

## Per-instance shader parameter name for albedo tint color.
const PARAM_ICHOR_TINT: StringName = &"ichor_tint"

## Per-instance shader parameter name for billboard Z-axis rotation in radians.
const PARAM_ROT_ANGLE: StringName = &"rot_angle"

## Default acid-yellow ichor tint applied when no custom tint is supplied.
const DEFAULT_TINT: Color = Color(0.72, 0.78, 0.08, 1.0)

## When true, hides on completion for ring-buffer reuse instead of freeing.
@export var pool_mode: bool = true

## Playback duration in seconds across the full flipbook sequence.
@export var duration: float = 0.45

## Active [Tween] driving flipbook playback progress.
var _active_tween: Tween = null

## Child [MeshInstance3D] rendering the billboard [QuadMesh].
@onready var _quad_mesh: MeshInstance3D = $QuadMeshInstance


## Disables per-frame processing and validates mandatory billboard mesh child.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(_quad_mesh), "GibBurstEmitter: Missing QuadMeshInstance.")
	if pool_mode:
		hide()


## Cleans up any active playback [Tween] when exiting the scene tree.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_active_tween)
	_active_tween = null


## Plays a single-shot flipbook splatter burst oriented along [param spray_dir].
func play(
	spray_dir: Vector3,
	scale_mult: float = 1.0,
	tint: Color = DEFAULT_TINT,
) -> void:
	if not is_instance_valid(_quad_mesh):
		return

	Utilities.safe_kill_tween(_active_tween)
	_active_tween = null

	if not spray_dir.is_zero_approx():
		global_position += spray_dir.normalized() * 0.12
	scale = Vector3.ONE * scale_mult

	_quad_mesh.set_instance_shader_parameter(PARAM_ROT_ANGLE, randf_range(0.0, TAU))
	_quad_mesh.set_instance_shader_parameter(PARAM_ICHOR_TINT, tint)
	_quad_mesh.set_instance_shader_parameter(PARAM_ANIM_PROGRESS, 0.0)
	show()

	var anim_tween: Tween = create_tween()
	_active_tween = anim_tween
	anim_tween.tween_method(_set_anim_progress, 0.0, 1.0, duration)
	anim_tween.finished.connect(_on_tween_finished)


## Updates the per-instance flipbook progress uniform from [Tween] interpolation.
func _set_anim_progress(progress: float) -> void:
	if is_instance_valid(_quad_mesh):
		_quad_mesh.set_instance_shader_parameter(PARAM_ANIM_PROGRESS, progress)


## Hides or frees the emitter when flipbook playback completes.
func _on_tween_finished() -> void:
	_active_tween = null
	if pool_mode:
		hide()
	else:
		queue_free()
