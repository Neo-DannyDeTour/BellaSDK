## A modular component that allows a [CharacterBody3D] to push [RigidBody3D] nodes.
##
## Automatically extracts collision data from the parent body's `move_and_slide()`
## and applies horizontal central impulses to overlapping rigidbodies based on player speed.
class_name PhysicsPusher
extends Node

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Node References")

## The parent character body whose slide collisions will be analyzed.
@export var player_body: CharacterBody3D

@export_category("Physics Settings")

## The base force scalar applied when pushing rigidbodies.
@export var push_force: float = 2.0

# --------------------------------------
# CORE PROCESS LOGIC
# --------------------------------------


## Analyzes the active collisions from the last physics frame and pushes [RigidBody3D] targets.
## Ignores the actively [param held_object], scales force by [param last_velocity],
## and normalizes against [param reference_max_speed].
func process_pushes(
	held_object: Node3D, last_velocity: Vector3, reference_max_speed: float
) -> void:
	if not player_body:
		return

	# Loop through all collisions that happened during move_and_slide()
	for i: int in player_body.get_slide_collision_count():
		var collision: KinematicCollision3D = player_body.get_slide_collision(i)
		var collider: Object = collision.get_collider()

		# Guard Clause: Only care about unfrozen RigidBody3D nodes
		if not collider is RigidBody3D or collider.freeze:
			continue

		# Guard Clause: Prevent punting the object we are currently holding!
		if held_object and collider == held_object:
			continue

		var push_dir: Vector3 = -collision.get_normal()

		# Guard Clause: Prevent pushing straight down into floors or up into ceilings
		if absf(push_dir.y) > 0.8:
			continue

		# Flatten the direction so the push is strictly horizontal
		push_dir.y = 0.0
		push_dir = push_dir.normalized()

		# Calculate the player's true flat speed based on the LAST frame's velocity
		var player_speed: float = Vector2(last_velocity.x, last_velocity.z).length()

		# Only apply the force if the player was actively moving into the box
		if player_speed > 0.1:
			var impulse_strength: float = push_force * (player_speed / reference_max_speed)
			collider.apply_central_impulse(push_dir * impulse_strength)
