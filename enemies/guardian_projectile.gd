## A fast-moving projectile that damages entities upon impact.
##
## [EnergyBlast] is typically fired by a [GuardianPillar]. It travels in a straight line
## until it collides with a valid body or its lifetime expires, at which point it triggers
## an area-of-effect explosion, applying damage via [HealthComponent].
class_name EnergyBlast
extends Area3D

## The speed in meters per second at which the projectile travels.
@export var speed: float = 25.0

## The amount of health points deducted from targets caught in the explosion.
@export var damage: int = 100

## The radius in meters of the spherical damage area created upon detonation.
@export var explosion_radius: float = 4.0

## The maximum time in seconds the projectile can exist before self-detonating.
@export var lifetime: float = 3.0

## Tracks if the projectile is currently undergoing its explosion sequence.
var is_exploding: bool = false

## The constant movement vector applied per frame during the flight phase.
var velocity: Vector3 = Vector3.ZERO

## The primary visual geometry of the projectile, which expands during the explosion.
@onready var mesh: MeshInstance3D = $MeshInstance3D

## The collision shape used for initial impact detection.
@onready var collision: CollisionShape3D = $CollisionShape3D

## The timer dictating how long the explosion visual persists before destruction.
@onready var explosion_timer: Timer = $ExplosionTimer


## Initializes the projectile, configures collision masks, and starts the lifetime timer.
func _ready() -> void:
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)

	body_entered.connect(_on_body_entered)

	var timer: SceneTreeTimer = get_tree().create_timer(lifetime)
	timer.timeout.connect(_explode)


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


## Halts movement, expands the mesh visually, and calculates AOE damage via a physics shape cast.
func _explode() -> void:
	if is_exploding:
		return

	is_exploding = true
	print("EnergyBlast: _explode() - Detonating at ", global_position)

	velocity = Vector3.ZERO

	var tween: Tween = create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE * explosion_radius, 0.15)

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = explosion_radius

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = true

	var results: Array[Dictionary] = space_state.intersect_shape(query)
	print("EnergyBlast: Explosion caught ", results.size(), " objects in radius.")

	for result: Variant in results:
		var collider: Object = result["collider"]
		if collider is Node3D:
			_apply_damage(collider as Node3D)

	explosion_timer.start(0.3)
	explosion_timer.timeout.connect(queue_free)


## Searches the target's direct and nested children for a [HealthComponent] to apply damage.
## [param target] The [Node3D] caught in the explosion blast radius.
func _apply_damage(target: Node3D) -> void:
	print("EnergyBlast: _apply_damage() - Analyzing target: ", target.name)

	for child: Node in target.get_children():
		if child is HealthComponent:
			print("EnergyBlast: Damaged direct component on ", target.name)
			(child as HealthComponent).take_damage(damage)
			return

		for subchild: Node in child.get_children():
			if subchild is HealthComponent:
				print("EnergyBlast: Damaged nested component inside ", child.name)
				(subchild as HealthComponent).take_damage(damage)
				return
