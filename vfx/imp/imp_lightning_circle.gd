@tool
## Expanding ground lightning circle AoE with telegraph and active damage phases (10m diameter).
class_name ImpLightningCircle
extends Node3D

## Emitted when the telegraph finishes and the active damage phase begins.
signal active_phase_started(center_pos: Vector3, radius: float)
## Emitted when the active phase fades out completely.
signal circle_finished

## Default render layer mask (Layer 1 Environment + Layer 10 Volumetrics).
const DEFAULT_RENDER_LAYERS: int = (1 << 0) | (1 << 9)
## Shader uniform controlling normalized circle expansion (0..1).
const PARAM_EXPAND_PROGRESS: StringName = &"expand_progress"
## Shader uniform switching between telegraph (0.0) and active damage (1.0) visuals.
const PARAM_ACTIVE_PHASE: StringName = &"active_phase"
## Shader uniform controlling overall circle fade alpha.
const PARAM_FADE_ALPHA: StringName = &"fade_alpha"

## Default maximum radius in meters (10m diameter = 5m radius).
@export var default_max_radius: float = 5.0

## Horizontal ground disc mesh.
@onready var _circle_mesh: MeshInstance3D = $CircleMesh

var _tween: Tween = null
var _active_center: Vector3 = Vector3.ZERO
var _active_radius: float = 5.0


## Initializes render layers and disables per-frame processing.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(_circle_mesh != null, "ImpLightningCircle: Missing CircleMesh child.")
	_circle_mesh.layers = DEFAULT_RENDER_LAYERS
	if not Engine.is_editor_hint():
		visible = false


## Triggers an expanding lightning circle at [param center_pos] up to [param target_radius].
func trigger_circle(
	center_pos: Vector3,
	telegraph_duration: float = 0.85,
	active_duration: float = 0.45,
	target_radius: float = -1.0
) -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var radius: float = default_max_radius if target_radius <= 0.0 else target_radius
	print("ImpLightningCircle: Telegraphing circle at ", center_pos, " radius=", radius)
	_active_center = center_pos
	_active_radius = radius
	global_position = center_pos + Vector3(0.0, 0.04, 0.0)
	var scale_factor: float = radius / 5.0
	_circle_mesh.scale = Vector3(scale_factor, 1.0, scale_factor)

	var mat: ShaderMaterial = _circle_mesh.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(PARAM_EXPAND_PROGRESS, 0.0)
		mat.set_shader_parameter(PARAM_ACTIVE_PHASE, 0.0)
		mat.set_shader_parameter(PARAM_FADE_ALPHA, 1.0)

	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(
		func(val: float) -> void:
			if mat != null:
				mat.set_shader_parameter(PARAM_EXPAND_PROGRESS, val),
		0.0,
		1.0,
		maxf(telegraph_duration, 0.05)
	)
	_tween.tween_callback(_begin_active_phase)
	_tween.tween_method(
		func(val: float) -> void:
			if mat != null:
				mat.set_shader_parameter(PARAM_FADE_ALPHA, val),
		1.0,
		0.0,
		maxf(active_duration, 0.05)
	)
	_tween.tween_callback(_on_circle_complete)


## Switches shader to active electric damage visuals and emits [signal active_phase_started].
func _begin_active_phase() -> void:
	var mat: ShaderMaterial = _circle_mesh.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(PARAM_ACTIVE_PHASE, 1.0)
	active_phase_started.emit(_active_center, _active_radius)


## Hides the circle and emits [signal circle_finished].
func _on_circle_complete() -> void:
	visible = false
	circle_finished.emit()
