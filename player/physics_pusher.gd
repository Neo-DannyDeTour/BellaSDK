## Applies physical push impulses to [RigidBody3D] nodes with mass-based resistance.
class_name PhysicsPusher
extends Node

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Node References")
## Parent character body whose collisions are evaluated.
@export var player_body: CharacterBody3D

@export_category("Physics Settings")
## Base impulse magnitude applied to physics objects.
@export var push_force: float = 12.0

## Mass threshold in kilograms scaling player resistance.
@export var resistance_mass_scale: float = 25.0


# --------------------------------------
# CORE PROCESS LOGIC
# --------------------------------------
## Evaluates slide collisions and applies purely horizontal central impulses.
## [param held_object] Item carried by player to ignore.
## [param last_velocity] Player velocity before move_and_slide.
## [param reference_max_speed] Top locomotion speed for ratio clamping.
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

		if is_instance_valid(held_object) and rb == held_object:
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
		var impulse_magnitude: float = (push_force * speed_ratio) / maxf(rb.mass * 0.1, 1.0)

		# Use central impulse to prevent downward rotational levering into floor geometry
		rb.apply_central_impulse(push_dir * impulse_magnitude)

		# 2. Apply resistance back onto the player
		var resistance: float = clampf(rb.mass / resistance_mass_scale, 0.0, 0.8)
		player_body.velocity.x *= (1.0 - resistance)
		player_body.velocity.z *= (1.0 - resistance)

		print(
			"PhysicsPusher: Pushed ",
			rb.name,
			" (mass: ",
			rb.mass,
			"kg). Applied central impulse: ",
			impulse_magnitude,
			", resistance: ",
			resistance
		)
