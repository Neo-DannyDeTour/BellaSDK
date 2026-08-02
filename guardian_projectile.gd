extends Area3D
class_name EnergyBlast

@export var speed: float = 25.0
@export var damage: int = 100
@export var explosion_radius: float = 4.0
@export var lifetime: float = 3.0

var is_exploding: bool = false
var velocity: Vector3 = Vector3.ZERO

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var explosion_timer: Timer = $ExplosionTimer


func _ready() -> void:
	# Force Area3D to collide with World (1) and Player (2)
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)

	body_entered.connect(_on_body_entered)

	var timer: SceneTreeTimer = get_tree().create_timer(lifetime)
	timer.timeout.connect(_explode)


func set_trajectory(fire_direction: Vector3) -> void:
	print("EnergyBlast: set_trajectory() - Direction set.")
	velocity = fire_direction.normalized() * speed


func _physics_process(delta: float) -> void:
	if is_exploding:
		return

	global_position += velocity * delta


func _on_body_entered(body: Node3D) -> void:
	if is_exploding:
		return

	if body is GuardianPillar:
		print("EnergyBlast: Ignored collision with GuardianPillar.")
		return

	print("EnergyBlast: _on_body_entered() - Collided with ", body.name)
	_explode()


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
	# Ensure the sphere cast detects both standard physics bodies and Area3D hurtboxes
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


func _apply_damage(target: Node3D) -> void:
	print("EnergyBlast: _apply_damage() - Analyzing target: ", target.name)

	for child: Node in target.get_children():
		# 1. Check direct children first (in case it hits a standard enemy)
		if child is HealthComponent:
			print("EnergyBlast: Damaged direct component on ", target.name)
			(child as HealthComponent).take_damage(damage)
			return

		# 2. Unconditionally check one level deeper to reliably hit your Components folder
		for subchild: Node in child.get_children():
			if subchild is HealthComponent:
				print("EnergyBlast: Damaged nested component inside ", child.name)
				(subchild as HealthComponent).take_damage(damage)
				return
