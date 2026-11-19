## Applies per-instance tint and dampness to Soviet shelf [MeshInstance3D] without
## duplicating [ShaderMaterial].
# class_name SovietShelfProp
extends StaticBody3D

## Per-instance shader uniform for paint color modulation.
const PARAM_PAINT_TINT: StringName = &"paint_tint"
## Per-instance shader uniform for surface dampness.
const PARAM_DAMPNESS: StringName = &"dampness"

## Path to the child [MeshInstance3D] receiving per-instance shader parameters.
@export var mesh_path: NodePath = ^"Soviet_Shelf"
## Color multiplier applied to the shelf albedo via [constant PARAM_PAINT_TINT].
@export var paint_tint: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		paint_tint = value
		if is_inside_tree():
			_apply_instance_params()
## Surface dampness factor [0.0..1.0] driving roughness and darkening.
@export_range(0.0, 1.0, 0.01) var dampness: float = 0.0:
	set(value):
		dampness = value
		if is_inside_tree():
			_apply_instance_params()

## Cached reference to the target shelf [MeshInstance3D].
@onready var _mesh: MeshInstance3D = get_node_or_null(mesh_path) as MeshInstance3D


## Disables per-frame processing, validates [member _mesh], and applies initial params.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(_mesh != null, "SovietShelfProp: mesh_path must resolve to MeshInstance3D.")
	_apply_instance_params()


## Pushes [member paint_tint] and [member dampness] to [member _mesh] instance uniforms.
func _apply_instance_params() -> void:
	if not is_instance_valid(_mesh):
		return
	var tint_vec: Vector3 = Vector3(paint_tint.r, paint_tint.g, paint_tint.b)
	_mesh.set_instance_shader_parameter(PARAM_PAINT_TINT, tint_vec)
	_mesh.set_instance_shader_parameter(PARAM_DAMPNESS, dampness)
