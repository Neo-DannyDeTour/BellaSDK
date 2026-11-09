## Interactive cinder block physics prop supporting picking, throwing, and collision events.
class_name CinderBlock
extends PickableObject

## Standard hollow CMU dry weight in kilograms.
const BLOCK_MASS_KG: float = 17.0
## Minimum squared velocity in (m/s)^2 to emit impact audio and physics events.
const IMPACT_VEL_SQ_THRESHOLD: float = 4.0
## Pre-allocated shader instance uniform name for procedural concrete variation.
const PARAM_GRIME_SEED: StringName = &"grime_seed"
## Procedural concrete shader material reference.
const CINDER_MATERIAL: Material = preload(
	"res://interactables/cinder_block/cinder_block_material.tres"
)

## Primary visual mesh representing the cinder block model.
@export var mesh_instance: MeshInstance3D
## Physical collision shape matching the outer bounds of the cinder block.
@export var collision_shape: CollisionShape3D


## Validates exported nodes, configures layers and instance uniforms, and connects impact hooks.
func _ready() -> void:
	if not is_instance_valid(collision_shape):
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D

	if not is_instance_valid(mesh_instance):
		var found_mesh: Node = NodeQuery.find_first_child_of_type(self, MeshInstance3D)
		if found_mesh is MeshInstance3D and found_mesh.name != "MeshInstance3D":
			mesh_instance = found_mesh as MeshInstance3D
		elif found_mesh is MeshInstance3D:
			mesh_instance = found_mesh as MeshInstance3D

	assert(mesh_instance != null, "CinderBlock: mesh_instance must be assigned.")
	assert(collision_shape != null, "CinderBlock: collision_shape must be assigned.")

	mesh = mesh_instance
	collision = collision_shape

	super._ready()

	mass = BLOCK_MASS_KG
	heavy_mass_threshold = BLOCK_MASS_KG - 1.0
	collision_layer = CollisionLayers.MASK_INTERACTIVE
	collision_mask = (
		CollisionLayers.MASK_SOLID_WORLD
		| CollisionLayers.MASK_PLAYER
		| CollisionLayers.MASK_DEBRIS
		| CollisionLayers.MASK_ENEMIES
	)
	contact_monitor = true
	max_contacts_reported = 2

	mesh_instance.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	if mesh_instance.material_override == null:
		mesh_instance.material_override = CINDER_MATERIAL

	var seed_val: float = fmod(absf(global_position.length_squared() * 13.37), 100.0)
	mesh_instance.set_instance_shader_parameter(PARAM_GRIME_SEED, seed_val)


## Applies a physics impulse to launch the cinder block forward.
func apply_throw_impulse(impulse: Vector3) -> void:
	apply_central_impulse(impulse)
	print("CinderBlock: thrown with impulse ", impulse)


## Evaluates impact speed against threshold and emits [signal Events.prop_impacted].
func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)
	var speed_sq: float = linear_velocity.length_squared()
	if speed_sq < IMPACT_VEL_SQ_THRESHOLD:
		speed_sq = _last_velocity.length_squared()
	if speed_sq >= IMPACT_VEL_SQ_THRESHOLD:
		Events.prop_impacted.emit(self, body, speed_sq)
		print("CinderBlock: impacted ", body.name, " speed_sq=", speed_sq)
