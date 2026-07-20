class_name PlayerLocomotionComponent
extends Node

# --------------------------------------
# CONSTANTS
# --------------------------------------
## The target local Y position of the head node when the player is standing.
const STANDING_HEIGHT: float = 1.8

## The target local Y position of the head node when the player is crouched.
const CROUCHING_HEIGHT: float = 1.0

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Movement Speeds")
## The speed magnitude applied when the player is moving normally on the ground.
@export var walking_speed: float = 5.0

## The speed magnitude applied when the player is sprinting.
@export var sprinting_speed: float = 6.5

## The speed magnitude applied when the player is moving while crouched.
@export var crouching_speed: float = 3.0

## The horizontal speed magnitude applied when the player is moving through water.
@export var swimming_speed: float = 4.0

## The vertical speed magnitude applied when the player ascends through water.
@export var swim_up_speed: float = 5.0

@export_category("Jump & Gravity")
## The time window in seconds where a jump input is remembered before hitting the ground.
@export var jump_buffer_duration: float = 0.15

## The time window in seconds where the player can still jump after walking off a ledge.
@export var coyote_time_duration: float = 0.15

## The multiplier applied to default gravity when the player is falling downwards to create a
## heavier feel.
@export var fall_gravity_multiplier: float = 1.5

@export_category("Physics Lerping")
## The rate at which the player's movement direction adjusts to input on standard ground.
@export var default_lerp_speed: float = 15.0

## The rate at which the player's movement direction adjusts to input while in the air.
@export var air_lerp_speed: float = 3.0

## The rate at which the player's movement direction adjusts to input while on slippery surfaces.
@export var ice_lerp_speed: float = 1.5

@export_category("System References")
## Reference to the component managing player health, stamina, and other core attributes.
@export var stats_component: PlayerStatsComponent

@export_category("Node References")
## Reference to the controller handling stair stepping and snapping mechanics.
@export var stair_controller: Node

## Reference to the manager responsible for detecting surface materials and playing footstep sounds.
@export var footstep_manager: Node

## Reference to the node that applies impulse forces to physics objects the player walks into.
@export var physics_pusher: Node

## The collision shape representing the player's full-height physical bounds.
@export var standing_collision: CollisionShape3D

## The reduced-height collision shape used when the player is crouching or sliding.
@export var crouching_collision: CollisionShape3D

## Raycast pointing upwards to ensure there is overhead clearance before the player stands up from
## a crouch.
@export var crouch_cast_check: RayCast3D

## The node representing the player's head or camera pivot, used for height interpolation.
@export var head: Node3D

# --------------------------------------
# VARIABLES
# --------------------------------------
## The cached reference to the parent player entity controlling this component.
var player: Player

## Determines if this component is actively processing physical movement and updates.
var is_active: bool = true

## Tracks the last RigidBody3D the player stood on to apply continuous downward weight force.
var _last_weighed_body: RigidBody3D = null

## The global downward acceleration value retrieved from project settings.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## Tracks whether the player is currently intending to sprint.
var sprint_active: bool = false

## Tracks whether the player is currently in a crouched stance.
var crouching: bool = false

## Determines if the player is currently allowed to enter the sprint state.
var can_sprint: bool = true

## Tracks if the player is currently standing on a surface identified as ice.
var on_ice: bool = false

## Tracks if the player is currently standing on a surface identified as sand.
var on_sand: bool = false

## The normalized 3D vector representing the player's current intended movement heading.
var direction: Vector3 = Vector3.ZERO

## The player's actual velocity vector from the previous physics frame.
var last_velocity: Vector3 = Vector3.ZERO

## Tracks if the player has landed on a surface that negates fall damage.
var on_safe_landing: bool = false


func initialize(p_player: Player) -> void:
	print("LocomotionComponent: initialize() called. Caching player reference.")
	player = p_player


func set_physics_active(active: bool) -> void:
	if is_active != active:
		print("LocomotionComponent: set_physics_active() called. Setting active state to: ", active)
		is_active = active


func process_movement(delta: float) -> void:
	if not is_active or not is_instance_valid(player):
		return

	_apply_weight_to_floor()
	_interpolate_head_height(delta)


func set_direction(new_dir: Vector3) -> void:
	direction = new_dir


func get_direction() -> Vector3:
	return direction


func reset_momentum() -> void:
	print("LocomotionComponent: reset_momentum() called. Clearing velocity arrays.")
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
	last_velocity = Vector3.ZERO
	direction = Vector3.ZERO


func _apply_weight_to_floor() -> void:
	if not player.is_on_floor():
		if is_instance_valid(_last_weighed_body):
			print("LocomotionComponent: Stepped off rigid body. Ceasing downward weight force.")
			_last_weighed_body = null
		return

	var slide_count: int = player.get_slide_collision_count()
	for i: int in range(slide_count):
		var collision: KinematicCollision3D = player.get_slide_collision(i)
		var collider: Object = collision.get_collider()

		if collider is RigidBody3D and collision.get_normal().y > 0.5:
			var is_cable_or_socket: bool = "CableLink" in collider.name or "Socket" in collider.name

			if is_cable_or_socket or collider.is_in_group("ignore_weight"):
				if _last_weighed_body != collider:
					print("LocomotionComponent: Stepped on ", collider.name, ". Ignoring weight.")
					_last_weighed_body = collider
				return

			var mass: float = (
				stats_component.player_mass if is_instance_valid(stats_component) else 80.0
			)
			var downward_force: float = mass * gravity
			var hit_position: Vector3 = collision.get_position() - collider.global_position

			collider.apply_force(Vector3.DOWN * downward_force, hit_position)

			if _last_weighed_body != collider:
				print(
					"LocomotionComponent: Applied ",
					downward_force,
					" downward force to ",
					collider.name
				)
				_last_weighed_body = collider
			return


func _interpolate_head_height(delta: float) -> void:
	if not is_instance_valid(head):
		return

	var target_height: float = CROUCHING_HEIGHT if crouching else STANDING_HEIGHT
	head.position.y = lerpf(head.position.y, target_height, delta * 15.0)
