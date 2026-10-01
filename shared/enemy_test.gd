## Physics-driven test dummy with bobbing motion and damage knockback.
class_name EnemyTest
extends RigidBody3D

## Injected [HealthComponent] managing life points and death handling.
@export var health_component: HealthComponent

## The impulse force applied to the dummy when struck by attacks.
@export var knockback_force: float = 0.5

## The vertical impulse added during knockback to lift the dummy.
@export var vertical_kick: float = 0.7

## Accumulated elapsed time used to compute the oscillating bob motion.
var time_passed: float = 0.0


## Initializes dependencies and binds death lifecycle signal.
func _ready() -> void:
	print("EnemyTest: Initializing test dummy.")
	if health_component == null:
		var found_comp: Node = NodeQuery.find_first_child_of_type(self, HealthComponent)
		if found_comp is HealthComponent:
			health_component = found_comp as HealthComponent

	if is_instance_valid(health_component):
		health_component.died.connect(die)


## Applies oscillatory vertical bobbing force on the physics body.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	time_passed += get_process_delta_time()
	var bob: float = sin(time_passed * 2.0) * 0.5
	state.apply_force(Vector3(0.0, bob, 0.0))


## Subtracts health through component and applies directional knockback impulse.
func take_damage(amount: int, hit_position: Vector3, dir: Vector3) -> void:
	print("EnemyTest: take_damage() called. Amount: ", amount, " | Pos: ", hit_position)

	if is_instance_valid(health_component):
		health_component.take_damage(amount)

	var punch: Vector3 = dir.normalized() * knockback_force
	punch.y += vertical_kick
	apply_central_impulse(punch)


## Handles entity death by freeing the physics body from the tree.
func die() -> void:
	print("EnemyTest: die() called. Freeing physics body.")
	queue_free()
