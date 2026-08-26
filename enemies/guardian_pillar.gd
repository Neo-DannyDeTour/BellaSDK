## A stationary defense turret that scans an area and fires projectiles at hostile targets.
##
## [GuardianPillar] constantly sweeps its head in a scanning motion. When a valid target
## enters its view cone and line of sight, it tracks them with a visible laser, freezes
## position to aim, and fires an [EnergyBlast].
class_name GuardianPillar
extends StaticBody3D

## Defines the sequential operational states of the pillar.
enum State { SCANNING, TARGETING, FROZEN, COOLDOWN }

## Determines if the pillar is friendly. If true, it ignores the player and only scans idly.
@export var is_friendly: bool = false

## The rotation speed in radians per second at which the guardian's head turns while scanning.
@export var scan_speed: float = 1.5

## The duration in seconds the pillar tracks the target before locking into the frozen state.
@export var targeting_time: float = 2.0

## The duration in seconds the pillar remains locked in position before firing its projectile.
@export var freeze_time: float = 1.0

## The packed scene representing the projectile to be instantiated and fired.
@export var projectile_scene: PackedScene

## The maximum distance in meters the pillar can detect targets within its line of sight.
@export var vision_radius: float = 25.0

## The vision cone angle in degrees for detecting targets.
@export var field_of_view_degrees: float = 60.0

## Tracks the current operational phase of the pillar.
var current_state: State = State.SCANNING

## A reference to the currently tracked player node. Null if no player is actively targeted.
var target_player: Node3D = null

## The spatial node representing the rotating head of the pillar.
@onready var head: Node3D = $Head

## The visual representation of the targeting laser beam.
@onready var laser_mesh: MeshInstance3D = $Head/LaserBeam

## The exact 3D position marker where projectiles are instantiated.
@onready var spawn_point: Marker3D = $Head/ProjectileSpawnPoint

## The timer governing state transitions.
@onready var state_timer: Timer = $StateTimer


## Initializes the pillar by hiding the laser, orienting it, and connecting the state timer.
func _ready() -> void:
	laser_mesh.hide()
	laser_mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	state_timer.timeout.connect(_on_state_timer_timeout)


## Main physics loop driving the active state logic.
## [param delta] The time elapsed since the previous physics tick in seconds.
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


## Rotates the head and checks for player presence within the vision cone.
## [param delta] The physics step duration in seconds.
func _process_scanning(delta: float) -> void:
	head.rotate_y(scan_speed * delta)
	_detect_player_in_cone()


## Executes a spatial shape intersection to find players within the FOV and line of sight.
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

	for result: Variant in results:
		var collider: Object = result["collider"]
		if collider is Node3D and collider.is_in_group("player"):
			var dir_to_player: Vector3 = head.global_position.direction_to(collider.global_position)
			var forward_dir: Vector3 = -head.global_basis.z
			var angle_to_player: float = rad_to_deg(forward_dir.angle_to(dir_to_player))

			if angle_to_player <= field_of_view_degrees / 2.0:
				if _has_line_of_sight(collider as Node3D):
					print("GuardianPillar: Player detected in FOV! Switching to TARGETING.")
					target_player = collider as Node3D
					_change_state(State.TARGETING)
					return


## Casts a ray from the head to the target to ensure no geometry is blocking the shot.
## [param target] The [Node3D] to check visibility against.
## Returns [code]true[/code] if the target is directly visible, [code]false[/code] otherwise.
func _has_line_of_sight(target: Node3D) -> bool:
	print("GuardianPillar: _has_line_of_sight() - Checking visibility.")
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		head.global_position, target.global_position, 3
	)
	query.exclude = [self.get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)
	if result and result["collider"] == target:
		return true

	return false


## Actively rotates the head to track the targeted player and stretches the laser mesh.
func _process_targeting() -> void:
	if is_friendly or not is_instance_valid(target_player):
		print("GuardianPillar: Target lost or friendly mode engaged. Resuming scan.")
		_change_state(State.SCANNING)
		return

	var target_pos: Vector3 = target_player.global_position

	head.look_at(target_pos, Vector3.UP)

	var dist_sq: float = head.global_position.distance_squared_to(target_pos)
	var dist: float = sqrt(dist_sq)

	laser_mesh.scale.y = dist / 2.0
	laser_mesh.position = Vector3(0.0, 0.0, -dist / 2.0)


## Handles transitions between operational states, updating visuals and timers.
## [param new_state] The target [enum State] to enter.
func _change_state(new_state: State) -> void:
	current_state = new_state
	print("GuardianPillar: State changed to ", State.keys()[current_state])

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


## Progresses the state machine to the next phase when the active timer completes.
func _on_state_timer_timeout() -> void:
	print("GuardianPillar: Timer finished for state: ", State.keys()[current_state])
	match current_state:
		State.TARGETING:
			_change_state(State.FROZEN)
		State.FROZEN:
			_shoot_projectile()
			_change_state(State.COOLDOWN)
		State.COOLDOWN:
			_change_state(State.SCANNING)


## Instantiates and fires an [EnergyBlast] projectile in the locked aiming direction.
func _shoot_projectile() -> void:
	print("GuardianPillar: _shoot_projectile() called. Action: Firing energy blast.")
	if projectile_scene == null:
		printerr("GuardianPillar: No projectile scene assigned!")
		return

	var proj: EnergyBlast = projectile_scene.instantiate() as EnergyBlast
	get_tree().current_scene.add_child(proj)

	proj.global_transform = spawn_point.global_transform
	var aim_direction: Vector3 = -spawn_point.global_transform.basis.z

	proj.set_trajectory(aim_direction)
