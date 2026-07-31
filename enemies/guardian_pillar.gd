extends StaticBody3D
class_name GuardianPillar

enum State { SCANNING, TARGETING, FROZEN, COOLDOWN }

@export var scan_speed: float = 1.5
@export var targeting_time: float = 2.0
@export var freeze_time: float = 1.0
@export var projectile_scene: PackedScene
@export var vision_radius: float = 25.0
@export var field_of_view_degrees: float = 60.0

var current_state: State = State.SCANNING
var target_player: Node3D = null

@onready var head: Node3D = $Head
@onready var laser_mesh: MeshInstance3D = $Head/LaserBeam
@onready var spawn_point: Marker3D = $Head/ProjectileSpawnPoint
@onready var state_timer: Timer = $StateTimer


func _ready() -> void:
	laser_mesh.hide()

	laser_mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	state_timer.timeout.connect(_on_state_timer_timeout)


func _physics_process(delta: float) -> void:
	match current_state:
		State.SCANNING:
			_process_scanning(delta)
		State.TARGETING:
			_process_targeting()
		State.FROZEN:
			pass  # Pillar is frozen, waiting to fire
		State.COOLDOWN:
			pass  # Waiting to resume scanning


func _process_scanning(delta: float) -> void:
	head.rotate_y(scan_speed * delta)
	_detect_player_in_cone()


func _detect_player_in_cone() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = vision_radius

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 2  # Assuming layer 2 is Player

	var results: Array[Dictionary] = space_state.intersect_shape(query)

	for result in results:
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


func _has_line_of_sight(target: Node3D) -> bool:
	print("GuardianPillar: _has_line_of_sight() - Checking visibility.")
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		head.global_position, target.global_position, 3  # Mask 1 (World) + 2 (Player)
	)
	query.exclude = [self.get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)
	if result and result["collider"] == target:
		return true

	return false


func _process_targeting() -> void:
	if not is_instance_valid(target_player):
		print("GuardianPillar: Target lost. Resuming scan.")
		_change_state(State.SCANNING)
		return

	var target_pos: Vector3 = target_player.global_position

	head.look_at(target_pos, Vector3.UP)

	var dist_sq: float = head.global_position.distance_squared_to(target_pos)
	var dist: float = sqrt(dist_sq)

	laser_mesh.scale.y = dist / 2.0
	laser_mesh.position = Vector3(0.0, 0.0, -dist / 2.0)


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


func _shoot_projectile() -> void:
	print("GuardianPillar: _shoot_projectile() called. Action: Firing energy blast.")
	print("GuardianPillar: _shoot_projectile() - Firing energy blast.")
	if projectile_scene == null:
		printerr("GuardianPillar: No projectile scene assigned!")
		return

	var proj: EnergyBlast = projectile_scene.instantiate() as EnergyBlast
	get_tree().current_scene.add_child(proj)

	proj.global_transform = spawn_point.global_transform

	var aim_direction: Vector3 = -spawn_point.global_transform.basis.z

	if is_instance_valid(target_player):
		# Calculate exactly point A to point B
		aim_direction = spawn_point.global_position.direction_to(target_player.global_position)
		# Visually aim the projectile's local -Z at the player
		proj.look_at(target_player.global_position, Vector3.UP)

	proj.set_trajectory(aim_direction)
