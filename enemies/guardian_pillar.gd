## Stationary turret sweeping an area and firing projectiles at hostiles.
class_name GuardianPillar
extends StaticBody3D

## Defines operational states for the pillar state machine.
enum State { SCANNING, TARGETING, FROZEN, COOLDOWN }

## When true, ignores hostiles and stays in an idle scanning state.
@export var is_friendly: bool = false

## Sweep rotation speed of the head in radians per second.
@export var scan_speed: float = 1.5

## Seconds the pillar tracks a target before locking position.
@export var targeting_time: float = 2.0

## Seconds the pillar remains locked on target before firing.
@export var freeze_time: float = 1.0

## Scene instantiated when firing projectile attacks.
@export var projectile_scene: PackedScene

## Maximum target detection range in meters.
@export var vision_radius: float = 25.0

## Total field of view detection angle in degrees.
@export var field_of_view_degrees: float = 60.0

## Active operational state of the turret.
var current_state: State = State.SCANNING

## Currently tracked hostile target, or null if unassigned.
var target_player: Node3D = null

## Spatial node containing rotating turret head components.
@onready var head: Node3D = $Head

## Visible laser mesh component used during targeting.
@onready var laser_mesh: MeshInstance3D = $Head/LaserBeam

## Marker transform defining projectile spawn coordinates.
@onready var spawn_point: Marker3D = $Head/ProjectileSpawnPoint

## State timer driving phase transition durations.
@onready var state_timer: Timer = $StateTimer


## Orients targeting laser and binds state timer completion.
func _ready() -> void:
	print("GuardianPillar: Initializing defense turret.")
	laser_mesh.hide()
	laser_mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	state_timer.timeout.connect(_on_state_timer_timeout)


## Updates state logic per physics frame tick.
func _physics_process(delta: float) -> void:
	match current_state:
		State.SCANNING:
			_process_scanning(delta)
		State.TARGETING:
			_process_targeting()
		State.FROZEN:
			pass
		State.COOLDOWN:
			pass


## Rotates turret head and inspects vision cone for hostiles.
func _process_scanning(delta: float) -> void:
	head.rotate_y(scan_speed * delta)
	_detect_player_in_cone()


## Queries world space within vision cone for valid player targets.
func _detect_player_in_cone() -> void:
	if is_friendly:
		return

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = vision_radius

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 2

	var results: Array[Dictionary] = space_state.intersect_shape(query)

	for result: Dictionary in results:
		var collider: Object = result["collider"]
		if collider is Node3D and (collider as Node).is_in_group("player"):
			var player_node: Node3D = collider as Node3D
			var dir_to_player: Vector3 = head.global_position.direction_to(
				player_node.global_position
			)
			var forward_dir: Vector3 = -head.global_basis.z
			var angle_to_player: float = rad_to_deg(forward_dir.angle_to(dir_to_player))

			if angle_to_player <= field_of_view_degrees / 2.0:
				if _has_line_of_sight(player_node):
					print("GuardianPillar: Target spotted. Locking on.")
					target_player = player_node
					_change_state(State.TARGETING)
					return


## Raycasts toward target to confirm unobstructed line of sight.
func _has_line_of_sight(target: Node3D) -> bool:
	print("GuardianPillar: Checking line of sight to target.")
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		head.global_position, target.global_position, 3
	)
	query.exclude = [self.get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)
	if result and result["collider"] == target:
		return true

	return false


## Adjusts head to track active target and scales laser beam.
func _process_targeting() -> void:
	if is_friendly or not is_instance_valid(target_player):
		print("GuardianPillar: Target missing or disabled. Resuming scan.")
		_change_state(State.SCANNING)
		return

	var target_pos: Vector3 = target_player.global_position
	head.look_at(target_pos, Vector3.UP)

	var dist_sq: float = head.global_position.distance_squared_to(target_pos)
	var dist: float = sqrt(dist_sq)

	laser_mesh.scale.y = dist / 2.0
	laser_mesh.position = Vector3(0.0, 0.0, -dist / 2.0)


## Transitions operational state machine and adjusts timers.
func _change_state(new_state: State) -> void:
	current_state = new_state
	print("GuardianPillar: State transitioned to ", State.keys()[current_state])

	match current_state:
		State.SCANNING:
			laser_mesh.hide()
			target_player = null
		State.TARGETING:
			laser_mesh.show()
			state_timer.start(targeting_time)
		State.FROZEN:
			state_timer.start(freeze_time)
		State.COOLDOWN:
			laser_mesh.hide()
			state_timer.start(2.0)


## Advances state machine when active timer period elapses.
func _on_state_timer_timeout() -> void:
	print("GuardianPillar: State timer elapsed for ", State.keys()[current_state])
	match current_state:
		State.TARGETING:
			_change_state(State.FROZEN)
		State.FROZEN:
			_shoot_projectile()
			_change_state(State.COOLDOWN)
		State.COOLDOWN:
			_change_state(State.SCANNING)


## Safely instantiates and launches an [EnergyBlast] projectile.
func _shoot_projectile() -> void:
	print("GuardianPillar: Firing projectile.")
	if projectile_scene == null:
		printerr("GuardianPillar: Missing projectile scene reference!")
		return

	var raw_proj: Node = projectile_scene.instantiate()
	if not (raw_proj is EnergyBlast):
		printerr("GuardianPillar: Spawned scene is not EnergyBlast. Freeing.")
		raw_proj.queue_free()
		return

	var proj: EnergyBlast = raw_proj as EnergyBlast
	get_tree().current_scene.add_child(proj)

	proj.global_transform = spawn_point.global_transform
	var aim_direction: Vector3 = -spawn_point.global_transform.basis.z

	proj.set_trajectory(aim_direction)
