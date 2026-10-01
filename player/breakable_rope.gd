## Destructible physics rope that snaps after sustaining critical damage.
class_name BreakableRope
extends StaticBody3D

## Emitted when the rope snaps after its health drops to zero.
signal rope_broken

## Injected [HealthComponent] tracking structural damage and death.
@export var health_component: HealthComponent

## Prevents duplicate destruction logic if damage occurs after breaking.
var is_broken: bool = false


## Caches [HealthComponent] dependency and binds to death signal.
func _ready() -> void:
	print("BreakableRope: Initializing rope entity.")
	if health_component == null:
		var found_comp: Node = NodeQuery.find_first_child_of_type(self, HealthComponent)
		if found_comp is HealthComponent:
			health_component = found_comp as HealthComponent

	if is_instance_valid(health_component):
		health_component.died.connect(snap_rope)


## Applies damage through [HealthComponent] if rope is intact.
func take_damage(amount: int, hit_position: Vector3, direction: Vector3) -> void:
	print(
		"BreakableRope: take_damage() called. Amount: ",
		amount,
		" | Pos: ",
		hit_position,
		" | Dir: ",
		direction
	)

	if is_broken:
		return

	if is_instance_valid(health_component):
		health_component.take_damage(amount)


## Emits [signal rope_broken] and frees the root hierarchy.
func snap_rope() -> void:
	print("BreakableRope: snap_rope() called. Rope snapped!")
	is_broken = true
	rope_broken.emit()

	if owner:
		print("BreakableRope: Freeing owner node.")
		owner.queue_free()
	else:
		print("BreakableRope: Freeing self.")
		queue_free()
