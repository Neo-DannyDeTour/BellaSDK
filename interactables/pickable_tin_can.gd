## Pickable low-poly hollow tin can prop with per-instance grime tint and impact events.
## Extends [PickableObject] with mass-proportional drop/throw capping and Layer 3 setup.
class_name PickableTinCan
extends PickableObject

## Emitted when the can collides with sufficient squared velocity.
signal impact_detected(speed_sq: float)

## Pre-allocated shader instance uniform name for per-instance grime tinting.
const SHADER_PARAM_TINT: StringName = &"tint_color"
## Minimum squared impact speed in (m/s)^2 required to emit [signal impact_detected].
const MIN_IMPACT_SPEED_SQ: float = 0.25
## Default mass in kilograms balanced for Jolt Physics stability on a small cylinder.
const DEFAULT_CAN_MASS: float = 0.12
## Gentle forward toss speed in m/s applied when dropping the can.
const DROP_SPEED: float = 2.0
## Maximum throw speed in m/s applied when throwing the can.
const MAX_THROW_SPEED: float = 12.0

## Per-instance color multiplier pushed to the tin can shader's [code]tint_color[/code] uniform.
@export var instance_tint: Color = Color.WHITE:
	set(value):
		instance_tint = value
		if is_instance_valid(_can_mesh) and is_inside_tree():
			_can_mesh.set_instance_shader_parameter(SHADER_PARAM_TINT, instance_tint)

## Cached primary [MeshInstance3D] rendering the hollow tin can geometry.
var _can_mesh: MeshInstance3D = null


## Initializes [PickableObject] state, enforces render layers, and applies instance tint.
func _ready() -> void:
	set_process(false)
	mass = DEFAULT_CAN_MASS if mass <= 0.0 else mass
	lock_on_player_stand = false
	projectile_damage = 0

	super._ready()

	_can_mesh = _resolve_can_mesh()
	assert(is_instance_valid(_can_mesh), "PickableTinCan requires a MeshInstance3D child.")
	assert(is_instance_valid(collision), "PickableTinCan requires a CollisionShape3D child.")

	_can_mesh.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	_can_mesh.set_instance_shader_parameter(SHADER_PARAM_TINT, instance_tint)
	contact_monitor = not sleeping


## Caps throw impulse to mass-proportional speed before delegating to [PickableObject.throw].
func throw(impulse_vector: Vector3) -> void:
	var scaled_impulse: Vector3 = impulse_vector
	var impulse_len: float = impulse_vector.length()
	var max_impulse: float = mass * MAX_THROW_SPEED
	if impulse_len > max_impulse and impulse_len > 0.0001:
		scaled_impulse = impulse_vector * (max_impulse / impulse_len)
	super.throw(scaled_impulse)


## Returns gentle mass-proportional drop impulse so ultra-light cans do not launch on drop.
func _get_drop_impulse_magnitude() -> float:
	return mass * DROP_SPEED


## Handles collision impacts and emits [signal impact_detected] above the speed threshold.
func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)
	var speed_sq: float = maxf(linear_velocity.length_squared(), _last_velocity.length_squared())
	if speed_sq >= MIN_IMPACT_SPEED_SQ:
		print("PickableTinCan: Impact with %s (speed_sq: %.2f)" % [body.name, speed_sq])
		impact_detected.emit(speed_sq)


## Resolves the assigned visual mesh node as a [MeshInstance3D].
func _resolve_can_mesh() -> MeshInstance3D:
	if is_instance_valid(mesh) and mesh is MeshInstance3D:
		return mesh as MeshInstance3D
	var found: Node = get_node_or_null("tin_can")
	if found is MeshInstance3D:
		return found as MeshInstance3D
	return null
