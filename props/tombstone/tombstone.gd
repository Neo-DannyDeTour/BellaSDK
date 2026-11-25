@tool
# class_name TombstoneProp
extends StaticBody3D
## Static environment tombstone prop managing procedural shader instance parameters
## and strict layer assignments (Render Layer 1, Physics Layer 1).

## Render layer bitmask for static environment geometry (Layer 1).
const RENDER_LAYER_ENV: int = 1 << 0
## Physics layer bitmask for static environment geometry (Layer 1).
const PHYSICS_LAYER_ENV: int = 1 << 0

## Instance shader parameter name for vertical grime height.
const PARAM_GRIME_HEIGHT: StringName = &"grime_height"
## Instance shader parameter name for engraved emblem opacity.
const PARAM_EMBLEM_OPACITY: StringName = &"emblem_opacity"
## Instance shader parameter name for procedural moss/stone UV seed.
const PARAM_MOSS_SEED: StringName = &"moss_seed"

## Target [MeshInstance3D] receiving per-instance shader uniforms.
@export var target_mesh: MeshInstance3D = null

## Normalized height [0..1] of bottom-up grime and moisture weathering.
@export_range(0.0, 1.0, 0.01) var grime_height: float = 0.45:
	set(value):
		grime_height = value
		_apply_instance_params()

## Opacity [0..1] of the engraved gold double-crescent emblem.
@export_range(0.0, 1.0, 0.01) var emblem_opacity: float = 0.85:
	set(value):
		emblem_opacity = value
		_apply_instance_params()

## Per-instance UV and procedural streak seed offset.
@export var moss_seed: float = 0.0:
	set(value):
		moss_seed = value
		_apply_instance_params()


## Configures static process gates, physics layers, and initial instance uniforms.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	collision_layer = PHYSICS_LAYER_ENV
	collision_mask = 0

	if not is_instance_valid(target_mesh):
		target_mesh = get_node_or_null("TombstoneModel/TombstoneMesh") as MeshInstance3D
	if not is_instance_valid(target_mesh):
		target_mesh = get_node_or_null("TombstoneMesh") as MeshInstance3D

	if not Engine.is_editor_hint():
		assert(is_instance_valid(target_mesh), "TombstoneProp requires valid target_mesh.")

	_apply_instance_params()


## Applies per-instance shader uniforms without duplicating [Material] resources.
func _apply_instance_params() -> void:
	if not is_inside_tree() or not is_instance_valid(target_mesh):
		return

	target_mesh.layers = RENDER_LAYER_ENV
	target_mesh.set_instance_shader_parameter(PARAM_GRIME_HEIGHT, grime_height)
	target_mesh.set_instance_shader_parameter(PARAM_EMBLEM_OPACITY, emblem_opacity)
	target_mesh.set_instance_shader_parameter(PARAM_MOSS_SEED, moss_seed)
