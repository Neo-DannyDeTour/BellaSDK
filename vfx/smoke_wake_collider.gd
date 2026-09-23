## Dynamic collision sphere scaling with player horizontal movement velocity.
class_name SmokeWakeCollider
extends GPUParticlesCollisionSphere3D

## Collision mask value targeting render Layer 10 (Volumetrics).
const LAYER_VOLUMETRICS_MASK: int = 512

## Base collision sphere radius when player is idle.
@export var base_radius: float = 1.0

## Maximum collision sphere radius at full sprint speed.
@export var max_radius: float = 3.0

## Interpolation speed coefficient for radius expansion.
@export var lerp_speed: float = 5.0

## Velocity scalar converting world speed into additional radius meters.
@export var speed_scale: float = 0.4

## Node reference to parent player CharacterBody3D.
@onready var _player: CharacterBody3D = get_parent() as CharacterBody3D


## Validates parent node type and initializes layer mask.
func _ready() -> void:
	print("SmokeWakeCollider: Initialized on player. Restricting cull mask.")
	cull_mask = LAYER_VOLUMETRICS_MASK
	radius = base_radius


## Smoothly resizes collider radius based on horizontal movement speed.
func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	var horizontal_velocity: Vector2 = Vector2(_player.velocity.x, _player.velocity.z)
	var speed: float = horizontal_velocity.length()
	var target_radius: float = clampf(base_radius + (speed * speed_scale), base_radius, max_radius)

	var weight: float = 1.0 - exp(-lerp_speed * delta)
	radius = lerpf(radius, target_radius, weight)
