## A modular component that allows a [CharacterBody3D] to push [RigidBody3D] nodes.
##
## Automatically extracts collision data from the parent body's `move_and_slide()`
## and applies physical impulses while simulating mass resistance against player momentum.
class_name PhysicsPusher
extends Node

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Node References")
## The parent character body whose slide collisions will be analyzed.
@export var player_body: CharacterBody3D

@export_category("Physics Settings")
## The base push force scalar applied when walking into physics bodies.
@export var push_force: float = 12.0

## The mass scale factor (in kg) at which player movement slows down noticeably.
@export var resistance_mass_scale: float = 25.0


# --------------------------------------
# CORE PROCESS LOGIC
# --------------------------------------
## Analyzes active collisions and pushes [RigidBody3D] targets with mass resistance.
## [param held_object] The item currently held by the player (ignored).
## [param last_velocity] Player velocity vector prior to sliding.
## [param reference_max_speed] Maximum expected movement speed for scalar normalization.
func process_pushes(
	held_object: Node3D, last_velocity: Vector3, reference_max_speed: float
) -> void:
	if not is_instance_valid(player_body):
		return

	var slide_count: int = player_body.get_slide_collision_count()
	for i: int in range(slide_count):
		var collision: KinematicCollision3D = player_body.get_slide_collision(i)
		var collider: Object = collision.get_collider()

		if not collider is RigidBody3D:
			continue

		var rb: RigidBody3D = collider as RigidBody3D
		if rb.freeze or rb.is_in_group(&"ignore_weight"):
			continue

		if held_object and rb == held_object:
			continue

		var push_dir: Vector3 = -collision.get_normal()
		if absf(push_dir.y) > 0.8:
			continue

		push_dir.y = 0.0
		push_dir = push_dir.normalized()

		var player_speed: float = Vector2(last_velocity.x, last_velocity.z).length()
		if player_speed <= 0.1:
			continue

		# 1. Calculate mass-scaled impulse
		var speed_ratio: float = clampf(player_speed / reference_max_speed, 0.1, 1.5)
		var impulse_magnitude: float = (push_force * speed_ratio) / maxf(rb.mass * 0.15, 1.0)
		var contact_offset: Vector3 = collision.get_position() - rb.global_position

		rb.apply_impulse(push_dir * impulse_magnitude, contact_offset)

		# 2. Apply push resistance back onto the player
		var resistance: float = clampf(rb.mass / resistance_mass_scale, 0.0, 0.8)
		player_body.velocity.x *= (1.0 - resistance)
		player_body.velocity.z *= (1.0 - resistance)

		print(
			"PhysicsPusher: Pushed ",
			rb.name,
			" (mass: ",
			rb.mass,
			"kg). Applied impulse: ",
			impulse_magnitude,
			", resistance: ",
			resistance
		)
