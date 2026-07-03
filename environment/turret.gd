extends Node3D
class_name Turret

enum TurretState {
	SCANNING,
	ENGAGING
}

@export var is_friendly: bool = false
@export var scan_speed: float = 1.5
@export var turn_speed: float = 8.0
@export var fire_rate: float = 0.15
@export var detection_radius: float = 15.0
@export var damage: int = 10
@export var aim_offset: Vector3 = Vector3(0.0, 1.2, 0.0)

@onready var head: Node3D = $Head
@onready var detection_area: Area3D = $DetectionArea
@onready var detection_shape: CollisionShape3D = $DetectionArea/CollisionShape3D
@onready var bullet_particles: GPUParticles3D = $Head/Muzzle/GPUParticles3D
@onready var hitscan_ray: RayCast3D = $Head/Muzzle/HitscanRay

var current_state: TurretState = TurretState.SCANNING
var target: Node3D = null
var fire_cooldown: float = 0.0
var _exclude_rids: Array[RID] = []


func _ready() -> void:
	var visualizer: EditorTriggerVisualizer = get_node_or_null("EditorTriggerVisualizer")
	if visualizer != null:
		visualizer.shape_type = EditorTriggerVisualizer.ShapeType.SPHERE
		visualizer.trigger_size = Vector3.ONE * (detection_radius * 2.0)

	print("Turret: _ready() - Initialized. Friendly mode: ", is_friendly)
	
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = detection_radius
	detection_shape.shape = sphere
	
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	detection_area.area_entered.connect(_on_area_entered)
	detection_area.area_exited.connect(_on_area_exited)
	
	hitscan_ray.collide_with_areas = true
	
	# Cache all of the turret's own collision objects to prevent self-hitting
	_build_exclude_rids(self)


func _build_exclude_rids(node: Node) -> void:
	if node is CollisionObject3D:
		_exclude_rids.append(node.get_rid())
	for child: Node in node.get_children():
		_build_exclude_rids(child)


func _process(delta: float) -> void:
	if is_friendly:
		_process_scanning(delta)
		return
		
	match current_state:
		TurretState.SCANNING:
			_process_scanning(delta)
		TurretState.ENGAGING:
			_process_engaging(delta)


func _change_state(new_state: TurretState) -> void:
	print("Turret: _change_state() - Transitioning to ", new_state)
	current_state = new_state
	
	if current_state == TurretState.SCANNING:
		bullet_particles.emitting = false


func _process_scanning(delta: float) -> void:
	head.rotate_y(scan_speed * delta)


func _process_engaging(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_change_state(TurretState.SCANNING)
		return
		
	_aim_at_target(delta)
	
	if _has_line_of_sight() and _is_aimed_at_target():
		_handle_shooting(delta)
	else:
		bullet_particles.emitting = false


func _get_actual_aim_offset() -> Vector3:
	if target is ShootingTarget:
		return Vector3.ZERO
	return aim_offset


func _aim_at_target(delta: float) -> void:
	var target_pos: Vector3 = target.global_position + _get_actual_aim_offset()
	var current_transform: Transform3D = head.global_transform
	var target_transform: Transform3D = current_transform.looking_at(target_pos, Vector3.UP, true)
	
	var current_quat: Quaternion = current_transform.basis.get_rotation_quaternion()
	var target_quat: Quaternion = target_transform.basis.get_rotation_quaternion()
	
	head.global_transform.basis = Basis(current_quat.slerp(target_quat, turn_speed * delta))


func _has_line_of_sight() -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	
	var start_pos: Vector3 = hitscan_ray.global_position
	var end_pos: Vector3 = target.global_position + _get_actual_aim_offset()
	
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.collide_with_areas = true 
	query.exclude = _exclude_rids # Pre-cached RIDs prevent hitting the detection sphere
	
	var result: Dictionary = space_state.intersect_ray(query)
	
	if result and result.collider == target:
		return true
		
	return false


func _is_aimed_at_target() -> bool:
	var target_pos: Vector3 = target.global_position + _get_actual_aim_offset()
	var dir_to_target: Vector3 = hitscan_ray.global_position.direction_to(target_pos)
	
	var ray_global_target: Vector3 = hitscan_ray.to_global(hitscan_ray.target_position)
	var forward_dir: Vector3 = hitscan_ray.global_position.direction_to(ray_global_target)
	
	return forward_dir.dot(dir_to_target) > 0.98


func _handle_shooting(delta: float) -> void:
	fire_cooldown -= delta
	
	if fire_cooldown <= 0.0:
		shoot()
		fire_cooldown = fire_rate


func shoot() -> void:
	print("Turret: shoot() - Firing at target: ", target.name)
	bullet_particles.emitting = true
	
	if is_instance_valid(target):
		_damage_player(target)


func _damage_player(player_node: Object) -> void:
	print("Turret: _damage_player() - Attempting to deal damage.")
	
	if player_node.has_method("take_damage"):
		print("Turret: _damage_player() - Hit target directly.")
		player_node.take_damage(damage)
		return
		
	var health_comp: Node = player_node.get_node_or_null("Components/HealthComponent")
	
	if health_comp == null:
		health_comp = player_node.find_child("HealthComponent", true, false)
		
	if health_comp != null and health_comp.has_method("take_damage"):
		print("Turret: _damage_player() - Hit confirmed. Dealing ", damage, " damage.")
		health_comp.take_damage(damage)


func _on_body_entered(body: Node3D) -> void:
	if is_friendly:
		return
		
	if body.is_in_group("player"):
		print("Turret: _on_body_entered() - Detected body target: ", body.name)
		target = body
		_change_state(TurretState.ENGAGING)


func _on_body_exited(body: Node3D) -> void:
	if body == target:
		print("Turret: _on_body_exited() - Current target left radius: ", body.name)
		_acquire_new_target()


func _on_area_exited(area: Area3D) -> void:
	if area == target:
		print("Turret: _on_area_exited() - Current target left radius: ", area.name)
		_acquire_new_target()


func _on_area_entered(area: Area3D) -> void:
	if is_friendly:
		return
		
	if area.is_in_group("player"):
		print("Turret: _on_area_entered() - Detected area target: ", area.name)
		target = area
		_change_state(TurretState.ENGAGING)


func _acquire_new_target() -> void:
	print("Turret: _acquire_new_target() - Scanning for remaining targets in zone.")
	target = null
	
	var bodies: Array[Node3D] = detection_area.get_overlapping_bodies()
	for b: Node3D in bodies:
		if b.is_in_group("player") and is_instance_valid(b) and b != self:
			print("Turret: _acquire_new_target() - Found new body target: ", b.name)
			target = b
			_change_state(TurretState.ENGAGING)
			return
			
	var areas: Array[Area3D] = detection_area.get_overlapping_areas()
	for a: Area3D in areas:
		if a.is_in_group("player") and is_instance_valid(a):
			print("Turret: _acquire_new_target() - Found new area target: ", a.name)
			target = a
			_change_state(TurretState.ENGAGING)
			return
			
	print("Turret: _acquire_new_target() - No targets remaining. Resuming scan.")
	_change_state(TurretState.SCANNING)
