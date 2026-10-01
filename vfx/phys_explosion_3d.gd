## Physics-driven explosive entity applying radial impulse without allocations.
class_name PhysExplosion3D
extends RigidBody3D

## Magnitude of radial impulse force applied to adjacent bodies.
@export var explosion_force: float = 50.0

## Spherical radius in meters affected by the explosive blast.
@export var explosion_radius: float = 5.0

## Multiplier for random kickback applied to the explosive itself.
@export var self_kick_multiplier: float = 0.5

## Minimum fuse duration in seconds before detonating.
@export var min_fuse_time: float = 1.0

## Maximum fuse duration in seconds before detonating.
@export var max_fuse_time: float = 4.0

## Remaining fuse duration timer in seconds before detonation.
var _fuse_timer: float = 0.0

## Pre-cached [Area3D] measuring radial physical overlap.
@onready var blast_area: Area3D = $BlastArea

## Pre-cached [CollisionShape3D] driving spherical overlap check.
@onready var blast_shape: CollisionShape3D = $BlastArea/CollisionShape3D

## Pre-cached particle emitter rendering spark bursts.
@onready var burst_sparks: GPUParticles3D = $BurstSparks

## Pre-cached editor icon purged at runtime to reduce overhead.
@onready var _editor_icon: Node3D = get_node_or_null("%EditorIcon") as Node3D


## Configures collision masks, sizes sphere shape once, and arms fuse.
func _ready() -> void:
	print("PhysExplosion3D: Arming explosive entity: ", name)
	if not Engine.is_editor_hint() and is_instance_valid(_editor_icon):
		_editor_icon.queue_free()

	blast_area.collision_layer = CollisionLayers.MASK_NONE
	blast_area.collision_mask = (
		CollisionLayers.MASK_DEBRIS
		| CollisionLayers.MASK_ENEMIES
		| CollisionLayers.MASK_PLAYER
		| CollisionLayers.MASK_INTERACTIVE
	)

	if blast_shape.shape is SphereShape3D:
		(blast_shape.shape as SphereShape3D).radius = explosion_radius

	_reset_fuse()


## Ticks fuse countdown timer and initiates detonation on expiry.
func _physics_process(delta: float) -> void:
	_fuse_timer -= delta
	if _fuse_timer <= 0.0:
		_detonate()
		_reset_fuse()


## Resets fuse timer to a randomized interval within duration bounds.
func _reset_fuse() -> void:
	_fuse_timer = randf_range(min_fuse_time, max_fuse_time)


## Executes radial physics blast, triggers sparks, and kicks self body.
func _detonate() -> void:
	print("PhysExplosion3D: Detonating radial explosion on: ", name)
	burst_sparks.restart()

	var bodies: Array[Node3D] = blast_area.get_overlapping_bodies()
	var center: Vector3 = global_position

	for body: Node3D in bodies:
		if body is RigidBody3D and body != self:
			var parent_node: Node = body.get_parent()
			if is_instance_valid(parent_node) and parent_node.get_class() == "PhysicsCable3D":
				continue

			var target_rb: RigidBody3D = body as RigidBody3D
			target_rb.sleeping = false

			var dir: Vector3 = center.direction_to(target_rb.global_position)
			var dist: float = center.distance_to(target_rb.global_position)

			if dist < 0.01:
				dir = Vector3.UP
				dist = 0.1

			var falloff: float = maxf(0.0, 1.0 - (dist / explosion_radius))
			var impulse: Vector3 = dir * explosion_force * falloff * target_rb.mass
			target_rb.apply_impulse(impulse, Vector3(0.0, 0.1, 0.0))

	var random_kick: Vector3 = (
		Vector3(randf_range(-1.0, 1.0), randf_range(0.5, 1.5), randf_range(-1.0, 1.0)).normalized()
	)
	var final_kick: Vector3 = random_kick * explosion_force * self_kick_multiplier * mass
	apply_central_impulse(final_kick)
