## Pickable Half-Life 2 style 'Květa' tin paint can prop.
## Extends [PickableObject] with mass-proportional drop/throw capping and Layer 3 setup.
class_name PickablePaintCan
extends PickableObject

## Default rigid body mass in kilograms for the paint can.
const DEFAULT_CAN_MASS: float = 1.2
## Gentle forward toss speed in m/s applied when dropping the can.
const DROP_SPEED: float = 1.8
## Maximum throw speed in m/s applied when throwing the can.
const MAX_THROW_SPEED: float = 12.0


## Initializes [PickableObject] state, enforces Layer 3 masks, and validates required children.
func _ready() -> void:
	set_process(false)
	mass = DEFAULT_CAN_MASS if mass <= 0.0 else mass
	lock_on_player_stand = false

	super._ready()

	var mesh_inst: MeshInstance3D = _resolve_can_mesh()
	assert(is_instance_valid(mesh_inst), "PickablePaintCan requires a MeshInstance3D child.")
	assert(is_instance_valid(collision), "PickablePaintCan requires a CollisionShape3D child.")

	mesh_inst.layers = CollisionLayers.RENDER_MASK_INTERACTIVE


## Caps throw impulse to mass-proportional speed before delegating to [method PickableObject.throw].
func throw(impulse_vector: Vector3) -> void:
	var scaled_impulse: Vector3 = impulse_vector
	var impulse_len: float = impulse_vector.length()
	var max_impulse: float = mass * MAX_THROW_SPEED
	if impulse_len > max_impulse and impulse_len > 0.0001:
		scaled_impulse = impulse_vector * (max_impulse / impulse_len)
	super.throw(scaled_impulse)


## Returns gentle mass-proportional drop impulse so the can does not launch on drop.
func _get_drop_impulse_magnitude() -> float:
	return mass * DROP_SPEED


## Resolves the assigned visual mesh node as a [MeshInstance3D].
func _resolve_can_mesh() -> MeshInstance3D:
	if is_instance_valid(mesh) and mesh is MeshInstance3D:
		return mesh as MeshInstance3D
	var found: Node = get_node_or_null("MeshInstance3D")
	if found is MeshInstance3D:
		return found as MeshInstance3D
	return null
