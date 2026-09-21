## Manages movement speeds, floor weight application, stance heights, and physics states.
class_name PlayerLocomotionComponent
extends Node

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Target local Y position of [member head] when standing.
const STANDING_HEIGHT: float = 1.8

## Target local Y position of [member head] when crouched.
const CROUCHING_HEIGHT: float = 1.0

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Movement Speeds")
## Ground walking speed magnitude in meters per second.
@export var walking_speed: float = 5.0

## Sprint speed magnitude in meters per second.
@export var sprinting_speed: float = 6.5

## Crouch walking speed magnitude in meters per second.
@export var crouching_speed: float = 3.0

## Horizontal swimming speed in meters per second.
@export var swimming_speed: float = 4.0

## Vertical swimming ascension speed in meters per second.
@export var swim_up_speed: float = 5.0

@export_category("Heavy Carry Modifiers")
## Multiplier applied to walking speed when carrying heavy objects.
@export_range(0.1, 1.0) var heavy_carry_speed_mult: float = 0.6

## Whether the player is permitted to jump while carrying heavy items.
@export var allow_heavy_carry_jump: bool = false

## Jump velocity multiplier applied when carrying heavy objects.
@export_range(0.0, 1.0) var heavy_carry_jump_mult: float = 0.4

@export_category("Jump & Gravity")
## Jump input buffer window in seconds before floor contact.
@export var jump_buffer_duration: float = 0.15

## Grace period in seconds to jump after leaving a ledge.
@export var coyote_time_duration: float = 0.15

## Multiplier applied to downward gravity during falls.
@export var fall_gravity_multiplier: float = 1.5

@export_category("Physics Lerping")
## Direction interpolation speed on standard ground.
@export var default_lerp_speed: float = 15.0

## Direction interpolation speed while airborne.
@export var air_lerp_speed: float = 3.0

## Direction interpolation speed on icy surfaces.
@export var ice_lerp_speed: float = 1.5

@export_category("System References")
## Reference to [PlayerStatsComponent] managing stamina and mass.
@export var stats_component: PlayerStatsComponent

@export_category("Node References")
## Controller managing stair stepping and snapping logic.
@export var stair_controller: Node

## Manager handling surface-specific footstep audio.
@export var footstep_manager: Node

## Node applying physical impulses to pushable objects.
@export var physics_pusher: Node

## Full-height [CollisionShape3D] used while standing.
@export var standing_collision: CollisionShape3D

## Reduced-height [CollisionShape3D] used when crouching.
@export var crouching_collision: CollisionShape3D

## Upward [RayCast3D] checking clearance before standing up.
@export var crouch_cast_check: RayCast3D

## Camera or head pivot [Node3D] for vertical stance lerping.
@export var head: Node3D

# --------------------------------------
# VARIABLES
# --------------------------------------
## Reference to parent [CharacterBody3D] entity.
var player: CharacterBody3D

## Flag determining if movement calculations should process.
var is_active: bool = true

## Previous [RigidBody3D] the player stood on.
var _last_weighed_body: RigidBody3D = null

## Default world gravity scalar from [ProjectSettings].
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## Indicates whether sprinting is currently active.
var sprint_active: bool = false

## Indicates whether the player is in crouched stance.
var crouching: bool = false

## Determines if sprinting is currently permitted.
var can_sprint: bool = true

## Tracks if the player is currently on an ice surface.
var on_ice: bool = false

## Tracks if the player is currently on a sand surface.
var on_sand: bool = false

## Normalized 3D vector representing intended movement heading.
var direction: Vector3 = Vector3.ZERO

## Player velocity vector from the previous physics frame.
var last_velocity: Vector3 = Vector3.ZERO

## Indicates if surface negates fall damage.
var on_safe_landing: bool = false

## System time in milliseconds of the last sprint action.
var _last_sprint_time: int = 0

## Tracks whether the player is currently carrying a heavy item.
var is_heavy_carrying: bool = false

## Extra mass in kilograms of currently held physical object.
var carried_weight: float = 0.0


## Subscribes to global event bus signals and initializes state.
func _ready() -> void:
	print("LocomotionComponent: _ready() initialized.")
	if Events.has_signal("heavy_carry_toggled"):
		if not Events.heavy_carry_toggled.is_connected(_on_heavy_carry_toggled):
			Events.heavy_carry_toggled.connect(_on_heavy_carry_toggled)


## Caches parent [CharacterBody3D] for physical updates.
func initialize(p_player: CharacterBody3D) -> void:
	print("LocomotionComponent: initialize() called. Caching player reference.")
	player = p_player


## Enables or disables movement and gravity processing.
func set_physics_active(active: bool) -> void:
	if is_active != active:
		print("LocomotionComponent: set_physics_active() -> ", active)
		is_active = active


## Executes floor weight application and head height interpolation.
func process_movement(delta: float) -> void:
	if not is_active or not is_instance_valid(player):
		return

	if sprint_active:
		_last_sprint_time = Time.get_ticks_msec()

	_apply_weight_to_floor()
	_interpolate_head_height(delta)


## Evaluates if player sprinted within the given millisecond window.
func did_run_recently(time_window_ms: int = 10000) -> bool:
	print("LocomotionComponent: did_run_recently() evaluated.")
	return (Time.get_ticks_msec() - _last_sprint_time) <= time_window_ms


## Updates player intended movement direction vector.
func set_direction(new_dir: Vector3) -> void:
	direction = new_dir


## Returns the normalized intended movement vector.
func get_direction() -> Vector3:
	return direction


## Clears movement direction and resets parent velocity.
func reset_momentum() -> void:
	print("LocomotionComponent: reset_momentum() called. Clearing velocity.")
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
	last_velocity = Vector3.ZERO
	direction = Vector3.ZERO


## Updates heavy carrying state, carried mass, and sprint allowance.
func set_heavy_carry(active: bool, weight: float = 0.0) -> void:
	print("LocomotionComponent: set_heavy_carry() -> ", active, " (mass: ", weight, "kg)")
	is_heavy_carrying = active
	carried_weight = weight if active else 0.0
	can_sprint = not active


## Handles [signal Events.heavy_carry_toggled] to restrict locomotion.
func _on_heavy_carry_toggled(is_heavy: bool) -> void:
	print("LocomotionComponent: _on_heavy_carry_toggled() received -> ", is_heavy)
	set_heavy_carry(is_heavy, 15.0 if is_heavy else 0.0)


## Calculates current walking speed scaled by heavy carry modifiers.
func get_effective_walk_speed() -> float:
	var base_speed: float = walking_speed
	if crouching:
		base_speed = crouching_speed
	elif sprint_active and can_sprint:
		base_speed = sprinting_speed

	if is_heavy_carrying:
		base_speed *= heavy_carry_speed_mult

	return base_speed


## Calculates adjusted jump velocity based on carry state.
func get_effective_jump_velocity(base_jump_velocity: float) -> float:
	if is_heavy_carrying:
		if not allow_heavy_carry_jump:
			print("LocomotionComponent: Jump blocked due to heavy carry.")
			return 0.0
		print("LocomotionComponent: Scaling jump velocity by heavy factor.")
		return base_jump_velocity * heavy_carry_jump_mult

	return base_jump_velocity


## Injects downward forces into floor bodies, including carried weight.
func _apply_weight_to_floor() -> void:
	if not player.is_on_floor():
		if is_instance_valid(_last_weighed_body):
			print("LocomotionComponent: Stepped off rigid body.")
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
			if is_heavy_carrying:
				mass += maxf(carried_weight, 10.0)

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


## Smoothly interpolates head node height based on stance.
func _interpolate_head_height(delta: float) -> void:
	if not is_instance_valid(head):
		return

	var target_height: float = CROUCHING_HEIGHT if crouching else STANDING_HEIGHT
	head.position.y = lerpf(head.position.y, target_height, delta * 15.0)
