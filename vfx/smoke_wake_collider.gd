## A dynamic particle collision sphere that scales based on player movement.
##
## Attached to the player, this [GPUParticlesCollisionSphere3D] pushes GPU smoke
## and fog out of the way, expanding its radius smoothly as the player's speed increases.
class_name SmokeWakeCollider
extends GPUParticlesCollisionSphere3D

## The base radius of the collider when the player is standing still.
@export var base_radius: float = 1.0

## The maximum radius when the player is moving at full speed.
@export var max_radius: float = 3.0

## How fast the collider expands and shrinks.
@export var lerp_speed: float = 5.0

## Reference to the parent [CharacterBody3D] to track velocity.
@onready var _player: CharacterBody3D = $".."


## Called every frame to adjust the collision radius based on parent velocity.
## [param delta] The time elapsed since the previous frame.
func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# Calculate the player's current speed
	var speed: float = _player.velocity.length()

	# Map the speed to a target radius.
	# Adjust the 0.4 multiplier based on your game's movement speed.
	var target_radius: float = clampf(base_radius + (speed * 0.4), base_radius, max_radius)

	# Smoothly interpolate the collision radius
	radius = lerpf(radius, target_radius, delta * lerp_speed)
