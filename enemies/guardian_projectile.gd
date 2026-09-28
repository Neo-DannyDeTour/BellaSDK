## High-speed projectile fired by guardian pillars triggering spherical damage explosions.
class_name EnergyBlast
extends Area3D

## Speed in meters per second at which the projectile travels.
@export var speed: float = 25.0

## Health points deducted from targets caught in explosion radius.
@export var damage: int = 100

## Radius in meters of spherical damage area created upon detonation.
@export var explosion_radius: float = 4.0

## Maximum lifespan in seconds before self-detonating.
@export var lifetime: float = 3.0

## Tracks if projectile is currently undergoing explosion sequence.
var is_exploding: bool = false

## Movement velocity vector applied per frame during flight phase.
var velocity: Vector3 = Vector3.ZERO

## Visual geometry of projectile that expands during explosion.
@onready var mesh: MeshInstance3D = $MeshInstance3D

## Collision shape used for initial impact detection.
@onready var collision: CollisionShape3D = $CollisionShape3D

## Timer dictating how long explosion visual persists before removal.
@onready var explosion_timer: Timer = $ExplosionTimer


## Initializes the projectile, configures collision masks, and starts lifetime timer.
func _ready() -> void:
	print("EnergyBlast: _ready() - Initializing energy blast projectile.")
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_PLAYER

	Utilities.safe_connect(body_entered, _on_body_entered)
	Utilities.delay_call(self, lifetime, _explode)
	Utilities.safe_connect(explosion_timer.timeout, queue_free)

	Utilities.delay_call(self, lifetime, Callable(self, "_explode"))


## Defines the travel direction and calculates the final velocity vector.
## [param fire_direction] The normalized [Vector3] direction to aim the projectile.
func set_trajectory(fire_direction: Vector3) -> void:
	print("EnergyBlast: set_trajectory() - Direction set.")
	velocity = fire_direction.normalized() * speed


## Moves the projectile each frame unless it is currently exploding.
## [param delta] The time elapsed since the previous physics tick in seconds.
func _physics_process(delta: float) -> void:
	if is_exploding:
		return

	global_position += velocity * delta


## Triggers the explosion if the projectile hits a valid target.
## [param body] The [Node3D] struck by the projectile.
func _on_body_entered(body: Node3D) -> void:
	if is_exploding:
		return

	if body is GuardianPillar:
		print("EnergyBlast: Ignored collision with GuardianPillar.")
		return

	print("EnergyBlast: _on_body_entered() - Collided with ", body.name)
	_explode()


## Halts movement, expands mesh visually, and calculates AOE damage via [CollisionLayers].
func _explode() -> void:
	if is_exploding:
		return

	is_exploding = true
	print("EnergyBlast: _explode() - Detonating at ", global_position)

	velocity = Vector3.ZERO

	var tween: Tween = create_tween()
	if is_instance_valid(tween):
		tween.tween_property(mesh, "scale", Vector3.ONE * explosion_radius, 0.15)

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = explosion_radius

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = (CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_PLAYER)
	query.collide_with_bodies = true
	query.collide_with_areas = true

	var results: Array[Dictionary] = space_state.intersect_shape(query)
	print("EnergyBlast: Explosion caught ", results.size(), " objects in radius.")

	for result: Dictionary in results:
		var collider: Object = result["collider"]
		if collider is Node3D:
			_apply_damage(collider as Node3D)

	explosion_timer.start(0.3)


## Resolves target root and damage components via [NodeQuery].
## [param target] The [Node3D] caught in the blast radius.
func _apply_damage(target: Node3D) -> void:
	print("EnergyBlast: _apply_damage() - Analyzing target: ", target.name)
	var root_node: Node3D = NodeQuery.resolve_interactable_root(target)
	var comp: HealthComponent = (
		NodeQuery.find_first_child_of_type(root_node, HealthComponent) as HealthComponent
	)

	if not is_instance_valid(comp) and target != root_node:
		comp = NodeQuery.find_first_child_of_type(target, HealthComponent) as HealthComponent

	if is_instance_valid(comp):
		print("EnergyBlast: Damaged health component on ", root_node.name)
		comp.take_damage(damage)
