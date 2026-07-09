class_name PlayerLocomotionComponent
extends Node

@export_category("Movement Speeds")
@export var walking_speed: float = 5.0
@export var sprinting_speed: float = 6.5
@export var crouching_speed: float = 3.0
@export var swimming_speed: float = 4.0
@export var swim_up_speed: float = 5.0

@export_category("Jump & Gravity")
@export var jump_buffer_duration: float = 0.15
@export var coyote_time_duration: float = 0.15
@export var fall_gravity_multiplier: float = 1.5

@export_category("Physics Lerping")
@export var default_lerp_speed: float = 15.0
@export var air_lerp_speed: float = 3.0
@export var ice_lerp_speed: float = 1.5

@export_category("System References")
@export var stats_component: PlayerStatsComponent

@export_category("Node References")
@export var stair_controller: Node
@export var footstep_manager: Node
@export var physics_pusher: Node
@export var standing_collision: CollisionShape3D
@export var crouching_collision: CollisionShape3D
@export var crouch_cast_check: RayCast3D
@export var head: Node3D

var player: Player
var is_active: bool = true
var _last_weighed_body: RigidBody3D = null

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var sprint_active: bool = false
var crouching: bool = false
var can_sprint: bool = true
var on_ice: bool = false
var on_sand: bool = false
var direction: Vector3 = Vector3.ZERO
var last_velocity: Vector3 = Vector3.ZERO
var on_safe_landing: bool = false


func initialize(p_player: Player) -> void:
	print("LocomotionComponent: initialize() called. Caching player reference.")
	player = p_player


func set_physics_active(active: bool) -> void:
	if is_active != active:
		print("LocomotionComponent: set_physics_active() called. Setting active state to: ", active)
		is_active = active


func process_movement(_delta: float) -> void:
	if not is_active or not is_instance_valid(player):
		return
		
	_apply_weight_to_floor()


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

			var mass: float = stats_component.player_mass if is_instance_valid(stats_component) else 80.0
			var downward_force: float = mass * gravity
			var hit_position: Vector3 = collision.get_position() - collider.global_position
			
			collider.apply_force(Vector3.DOWN * downward_force, hit_position)

			if _last_weighed_body != collider:
				print("LocomotionComponent: Applied ", downward_force, " downward force to ", collider.name)
				_last_weighed_body = collider
			return
