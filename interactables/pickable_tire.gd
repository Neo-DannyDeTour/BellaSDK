## Physics-enabled hollow rubber tire prop supporting pickup, throws, and buoyancy.
##
## Inherits full functionality from [PickableObject] and configures rubber physics
## material damping, mass, and [CollisionLayers] bitmasks.
class_name PickableTire
extends PickableObject

## Rubber friction coefficient applied to the tire physics material.
const TIRE_FRICTION: float = 0.9

## Rubber restitution bounce coefficient applied to the tire physics material.
const TIRE_BOUNCE: float = 0.35

## Default physical mass in kilograms matching hollow carcass weight.
const DEFAULT_TIRE_MASS: float = 9.5


## Configures rubber physics material, mass, and collision bitmasks on initialization.
func _ready() -> void:
	super._ready()
	print("PickableTire: Initializing rubber physics and collision layers.")

	mass = DEFAULT_TIRE_MASS
	hold_at_chest = true
	custom_hold_distance = 0.5
	hold_vertical_offset = -0.15

	collision_layer = CollisionLayers.MASK_INTERACTIVE | CollisionLayers.MASK_DEBRIS
	collision_mask = (
		CollisionLayers.MASK_SOLID_WORLD
		| CollisionLayers.MASK_COMBAT_ENTITIES
		| CollisionLayers.MASK_DEBRIS
	)

	if is_instance_valid(mesh) and mesh is VisualInstance3D:
		(mesh as VisualInstance3D).layers = CollisionLayers.RENDER_MASK_INTERACTIVE

	if physics_material_override == null:
		var phys_mat: PhysicsMaterial = PhysicsMaterial.new()
		phys_mat.friction = TIRE_FRICTION
		phys_mat.bounce = TIRE_BOUNCE
		physics_material_override = phys_mat
