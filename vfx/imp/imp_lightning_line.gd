@tool
## Direct line lightning beam between the Imp and its target using crossed billboarded quads.
class_name ImpLightningLine
extends Node3D

## Emitted when the lightning beam flash completes.
signal beam_finished

## Default render layer mask (Layer 1 Environment + Layer 10 Volumetrics).
const DEFAULT_RENDER_LAYERS: int = (1 << 0) | (1 << 9)
## Shader uniform controlling overall beam opacity.
const PARAM_BEAM_ALPHA: StringName = &"beam_alpha"
## Shader uniform randomizing the jagged lightning pattern.
const PARAM_SEED_OFFSET: StringName = &"seed_offset"

## Primary beam quad mesh.
@onready var _beam_a: MeshInstance3D = $BeamA
## Perpendicular crossed beam quad mesh for 3D visibility.
@onready var _beam_b: MeshInstance3D = $BeamB

var _tween: Tween = null


## Initializes render layers and disables per-frame processing.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(_beam_a != null, "ImpLightningLine: Missing BeamA child.")
	assert(_beam_b != null, "ImpLightningLine: Missing BeamB child.")
	_beam_a.layers = DEFAULT_RENDER_LAYERS
	_beam_b.layers = DEFAULT_RENDER_LAYERS
	if not Engine.is_editor_hint():
		visible = false


## Fires the lightning beam from [param from_pos] to [param to_pos] over [param duration] seconds.
func fire_beam(from_pos: Vector3, to_pos: Vector3, duration: float = 0.22) -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var delta: Vector3 = to_pos - from_pos
	var dist: float = delta.length()
	if dist < 0.01:
		return
	print("ImpLightningLine: Firing beam from ", from_pos, " to ", to_pos)

	var mid: Vector3 = (from_pos + to_pos) * 0.5
	global_position = mid
	var dir: Vector3 = delta / dist
	var up_ref: Vector3 = Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var basis_z: Vector3 = dir.cross(up_ref).normalized()
	var basis_x: Vector3 = basis_z.cross(dir).normalized()
	global_transform.basis = Basis(basis_x, dir, basis_z)

	_beam_a.scale = Vector3(1.0, dist, 1.0)
	_beam_b.scale = Vector3(1.0, dist, 1.0)

	var seed_val: float = randf() * 100.0
	var mat_a: ShaderMaterial = _beam_a.material_override as ShaderMaterial
	var mat_b: ShaderMaterial = _beam_b.material_override as ShaderMaterial
	for mat: ShaderMaterial in [mat_a, mat_b]:
		if mat != null:
			mat.set_shader_parameter(PARAM_SEED_OFFSET, seed_val)
			mat.set_shader_parameter(PARAM_BEAM_ALPHA, 1.0)

	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_beam_alpha, 1.0, 0.0, maxf(duration, 0.05))
	_tween.tween_callback(_on_beam_complete)


## Updates [member PARAM_BEAM_ALPHA] on both crossed beam materials.
func _set_beam_alpha(alpha_val: float) -> void:
	var mat_a: ShaderMaterial = _beam_a.material_override as ShaderMaterial
	var mat_b: ShaderMaterial = _beam_b.material_override as ShaderMaterial
	if mat_a != null:
		mat_a.set_shader_parameter(PARAM_BEAM_ALPHA, alpha_val)
	if mat_b != null:
		mat_b.set_shader_parameter(PARAM_BEAM_ALPHA, alpha_val)


## Hides the beam and emits [signal beam_finished].
func _on_beam_complete() -> void:
	visible = false
	beam_finished.emit()
