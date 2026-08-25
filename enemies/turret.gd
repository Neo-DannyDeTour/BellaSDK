## An automated defense mechanism that targets specific groups.
class_name Turret
extends Node3D

enum TurretState { SCANNING, ENGAGING }

## Defines whether the turret is friendly to the player, disabling its hostile tracking.
@export var is_friendly: bool = false
## The rotational speed at which the turret scans when no target is present.
@export var scan_speed: float = 1.5
## The speed at which the turret head interpolates to aim at a tracked target.
@export var turn_speed: float = 8.0
## The time interval in seconds between consecutive shots.
@export var fire_rate: float = 0.15
## The maximum distance in meters at which the turret can detect targets.
@export var detection_radius: float = 15.0
## The amount of health subtracted from a target upon a successful hit.
@export var damage: int = 10
## The 3D positional offset applied to the target's center to adjust the aiming reticle.
@export var aim_offset: Vector3 = Vector3(0.0, 1.2, 0.0)
## The groups that this turret considers hostile and will actively attempt to shoot.
@export var hostile_groups: Array[StringName] = [&"player", &"target"]

## The rotating pivot mechanism of the turret.
@onready var head: Node3D = $Head
## The physics area used for early overlap detection.
@onready var detection_area: Area3D = $DetectionArea
## The collision shape matching the detection radius.
@onready var detection_shape: CollisionShape3D = $DetectionArea/CollisionShape3D
## Visual tracer effect fired from the barrel.
@onready var bullet_particles: GPUParticles3D = $Head/Muzzle/GPUParticles3D
## Internal raycast to confirm precise line of sight before shooting.
@onready var hitscan_ray: RayCast3D = $Head/Muzzle/HitscanRay

## The current operational mode of the turret, determining if it is scanning or engaging.
var current_state: TurretState = TurretState.SCANNING
## The current entity that the turret is actively tracking and attempting to shoot.
var target: Node3D = null
## The remaining time in seconds before the turret is allowed to fire again.
var fire_cooldown: float = 0.0
## A cached list of Physics RIDs representing the turret's
## own collision shapes to avoid self-intersection.
var _exclude_rids: Array[RID] = []


## Pre-calculates physics data and hooks into detection signals.
func _ready() -> void:
	print("Turret: _ready() - Initializing turret systems.")
	var visualizer: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if visualizer != null:
		visualizer.shape_type = EditorTriggerVisualizer.ShapeType.SPHERE
		visualizer.trigger_size = Vector3.ONE * (detection_radius * 2.0)

	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = detection_radius
	detection_shape.shape = sphere

	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	detection_area.area_entered.connect(_on_area_entered)
	detection_area.area_exited.connect(_on_area_exited)

	hitscan_ray.collide_with_areas = true
	_build_exclude_rids(self)


## Recursively builds an array of local physics RIDs to ignore.
## [param node] The [Node] to search recursively.
func _build_exclude_rids(node: Node) -> void:
	if node is CollisionObject3D:
		_exclude_rids.append(node.get_rid())
	for i: int in node.get_child_count():
		_build_exclude_rids(node.get_child(i))


## Steps the active logic state of the turret per frame.
## [param delta] Engine frame delta in seconds.
func _process(delta: float) -> void:
	if is_friendly:
		_process_scanning(delta)
		return

	match current_state:
		TurretState.SCANNING:
			_process_scanning(delta)
		TurretState.ENGAGING:
			_process_engaging(delta)


## Safely forces a transition to a new turret state.
## [param new_state] The target enum TurretState.
func _change_state(new_state: TurretState) -> void:
	print("Turret: _change_state() - Transitioning to ", new_state)
	current_state = new_state

	if current_state == TurretState.SCANNING:
		bullet_particles.emitting = false


## Panning logic while waiting for a target.
## [param delta] Engine frame delta in seconds.
func _process_scanning(delta: float) -> void:
	head.rotate_y(scan_speed * delta)


## Aiming and shooting logic while actively tracking a target.
## [param delta] Engine frame delta in seconds.
func _process_engaging(delta: float) -> void:
	# Safely verifies if the target is physically in play, stopping the pooling bug.
	if not _is_active_target(target):
		_change_state(TurretState.SCANNING)
		return

	_aim_at_target(delta)

	if _has_line_of_sight() and _is_aimed_at_target():
		_handle_shooting(delta)
	else:
		bullet_particles.emitting = false


## Verifies a target is physically present and capable of receiving damage.
## [param node] The [Node3D] to evaluate.
## [return] True if valid and active.
func _is_active_target(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	# Pooled targets hide themselves and disable processing when dead.
	if not node.visible or node.process_mode == Node.PROCESS_MODE_DISABLED:
		return false
	return true


## Checks if an incoming node exists in the hostility list.
## [param node] The generic [Node] to check.
## [return] True if hostile.
func _is_hostile(node: Node) -> bool:
	for group: StringName in hostile_groups:
		if node.is_in_group(group):
			return true
	return false


## Retrieves the precise aiming offset, zeroing out for specific target types.
## [return] The calculated [Vector3] offset.
func _get_actual_aim_offset() -> Vector3:
	if target is ShootingTarget:
		return Vector3.ZERO
	return aim_offset


## Uses quaternion slerp to smoothly track the active target.
## [param delta] Engine frame delta in seconds.
func _aim_at_target(delta: float) -> void:
	var target_pos: Vector3 = target.global_position + _get_actual_aim_offset()
	var current_transform: Transform3D = head.global_transform
	var target_transform: Transform3D = current_transform.looking_at(target_pos, Vector3.UP, true)

	var current_quat: Quaternion = current_transform.basis.get_rotation_quaternion()
	var target_quat: Quaternion = target_transform.basis.get_rotation_quaternion()

	head.global_transform.basis = Basis(current_quat.slerp(target_quat, turn_speed * delta))


## Performs a direct space state raycast to confirm the target isn't behind a wall.
## [return] True if nothing blocks the target.
func _has_line_of_sight() -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	var start_pos: Vector3 = hitscan_ray.global_position
	var end_pos: Vector3 = target.global_position + _get_actual_aim_offset()

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.collide_with_areas = true
	query.exclude = _exclude_rids

	var result: Dictionary = space_state.intersect_ray(query)

	if result and result.collider == target:
		return true

	return false


## Uses dot product math to determine if the muzzle is pointed directly at the target.
## [return] True if perfectly aimed.
func _is_aimed_at_target() -> bool:
	var target_pos: Vector3 = target.global_position + _get_actual_aim_offset()
	var dir_to_target: Vector3 = hitscan_ray.global_position.direction_to(target_pos)

	var ray_global_target: Vector3 = hitscan_ray.to_global(hitscan_ray.target_position)
	var forward_dir: Vector3 = hitscan_ray.global_position.direction_to(ray_global_target)

	return forward_dir.dot(dir_to_target) > 0.98


## Steps the cooldown timer and fires the weapon if ready.
## [param delta] Engine frame delta in seconds.
func _handle_shooting(delta: float) -> void:
	fire_cooldown -= delta

	if fire_cooldown <= 0.0:
		shoot()
		fire_cooldown = fire_rate


## Triggers the visual tracer and attempts to deal direct damage to the target.
func shoot() -> void:
	print("Turret: shoot() - Firing at target: ", target.name)
	bullet_particles.emitting = true

	if is_instance_valid(target):
		_damage_player(target)


## Deeply searches the target hierarchy for a health component to deduct health.
## [param player_node] The root object hit by the turret.
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


## Detects new physics bodies entering the detection range.
## [param body] The [Node3D] that entered.
func _on_body_entered(body: Node3D) -> void:
	if is_friendly:
		return

	if _is_hostile(body) and _is_active_target(body):
		print("Turret: _on_body_entered() - Detected hostile body: ", body.name)
		target = body
		_change_state(TurretState.ENGAGING)


## Forgets targets that escape the detection range.
## [param body] The [Node3D] that left.
func _on_body_exited(body: Node3D) -> void:
	if body == target:
		print("Turret: _on_body_exited() - Current target left radius: ", body.name)
		_acquire_new_target()


## Forgets area targets that escape the detection range.
## [param area] The [Area3D] that left.
func _on_area_exited(area: Area3D) -> void:
	if area == target:
		print("Turret: _on_area_exited() - Current target left radius: ", area.name)
		_acquire_new_target()


## Detects new area bodies entering the detection range.
## [param area] The [Area3D] that entered.
func _on_area_entered(area: Area3D) -> void:
	if is_friendly:
		return

	if _is_hostile(area) and _is_active_target(area):
		print("Turret: _on_area_entered() - Detected hostile area: ", area.name)
		target = area
		_change_state(TurretState.ENGAGING)


## Scans overlapping geometry to find a replacement target if the current one is lost.
func _acquire_new_target() -> void:
	print("Turret: _acquire_new_target() - Scanning for remaining targets in zone.")
	target = null

	var bodies: Array[Node3D] = detection_area.get_overlapping_bodies()
	for b: Node3D in bodies:
		if _is_hostile(b) and _is_active_target(b) and b != self:
			print("Turret: _acquire_new_target() - Found new body target: ", b.name)
			target = b
			_change_state(TurretState.ENGAGING)
			return

	var areas: Array[Area3D] = detection_area.get_overlapping_areas()
	for a: Area3D in areas:
		if _is_hostile(a) and _is_active_target(a):
			print("Turret: _acquire_new_target() - Found new area target: ", a.name)
			target = a
			_change_state(TurretState.ENGAGING)
			return

	print("Turret: _acquire_new_target() - No active targets remaining. Resuming scan.")
	_change_state(TurretState.SCANNING)
