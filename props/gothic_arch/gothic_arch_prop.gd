@tool
# class_name GothicArchProp
extends StaticBody3D

## Configures per-instance shader parameters and layer invariants for GothicArch props.

## Shader parameter key for per-instance albedo tint.
const PARAM_TINT: StringName = &"instance_tint"

## Shader parameter key for cavity wear intensity.
const PARAM_WEAR: StringName = &"wear_intensity"

## Shader parameter key for top-down moss coverage.
const PARAM_MOSS: StringName = &"moss_coverage"

## Tint color applied to the arch stone material.
@export var instance_tint: Color = Color.WHITE:
	set(value):
		instance_tint = value
		_apply_instance_params()

## Cavity wear and grime intensity between 0.0 and 1.0.
@export_range(0.0, 1.0) var wear_intensity: float = 0.25:
	set(value):
		wear_intensity = value
		_apply_instance_params()

## World-space top-down moss growth coverage between 0.0 and 1.0.
@export_range(0.0, 1.0) var moss_coverage: float = 0.0:
	set(value):
		moss_coverage = value
		_apply_instance_params()

## Target visual mesh instance receiving per-instance parameters.
@export var arch_mesh: MeshInstance3D


## Validates node references, enforces Environment layers, and disables per-frame processing.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if arch_mesh == null:
		arch_mesh = get_node_or_null("ArchMesh") as MeshInstance3D
	if not Engine.is_editor_hint():
		assert(arch_mesh != null, "GothicArchProp: arch_mesh reference missing.")
	collision_layer = CollisionLayers.MASK_ENVIRONMENT
	collision_mask = CollisionLayers.MASK_NONE
	_apply_instance_params()


## Pushes per-instance uniforms to [member arch_mesh] without duplicating [Material].
func _apply_instance_params() -> void:
	if not is_inside_tree() or not is_instance_valid(arch_mesh):
		return
	arch_mesh.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	var tint_v3: Vector3 = Vector3(instance_tint.r, instance_tint.g, instance_tint.b)
	arch_mesh.set_instance_shader_parameter(PARAM_TINT, tint_v3)
	arch_mesh.set_instance_shader_parameter(PARAM_WEAR, wear_intensity)
	arch_mesh.set_instance_shader_parameter(PARAM_MOSS, moss_coverage)
