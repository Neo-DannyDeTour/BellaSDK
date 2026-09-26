## Automated defense turret that sleeps when offscreen and beyond proximity.
class_name Turret
extends Node3D

## Operational mode enum representing scanning or engaging states.
enum TurretState { SCANNING, ENGAGING }

## Whether the turret ignores player and hostile targeting entirely.
@export var is_friendly: bool = false

## Rotational speed in radians per second while panning for targets.
@export var scan_speed: float = 1.5

## Interpolation turn speed factor when aiming head at targets.
@export var turn_speed: float = 8.0

## Cooldown duration in seconds between consecutive weapon discharges.
@export var fire_rate: float = 0.15

## Maximum spherical detection radius in meters for target acquisition.
@export var detection_radius: float = 15.0

## Distance to [Player] beyond which the turret sleeps if offscreen.
@export var sleep_distance: float = 35.0

## Interval in seconds between player proximity distance evaluations.
@export var proximity_interval: float = 0.5

## Base damage points inflicted per hit on the target's [HealthComponent].
@export var damage: int = 10

## Vertical and horizontal spatial offset vector applied to the target center.
@export var aim_offset: Vector3 = Vector3(0.0, 1.2, 0.0)

## String names of groups flagged as hostile targets.
@export var hostile_groups: Array[StringName] = [&"player", &"target"]

## Bounding volume notifier checking if the turret is within view frustum.
@onready var screen_notifier: VisibleOnScreenNotifier3D = $VisibleOnScreenNotifier3D

## The rotating head pivot [Node3D] containing weapon barrel and muzzle.
@onready var head: Node3D = $Head

## The [Area3D] volume used to detect overlapping hostile bodies and areas.
@onready var detection_area: Area3D = $DetectionArea

## The spherical collision shape dictating early detection boundaries.
@onready var detection_shape: CollisionShape3D = $DetectionArea/CollisionShape3D

## Visual tracer particle system spawned during active shooting.
@onready var bullet_particles: GPUParticles3D = $Head/Muzzle/GPUParticles3D

## Directional [RayCast3D] reference used for muzzle forward vector math.
@onready var hitscan_ray: RayCast3D = $Head/Muzzle/HitscanRay

## Current active state determining if turret pans or tracks targets.
var current_state: TurretState = TurretState.SCANNING

## The hostile [Node3D] entity currently acquired and tracked.
var target: Node3D = null

## Cached [HealthComponent] on current target to avoid repeat lookups.
var target_health_comp: HealthComponent = null

## Remaining cooldown time in seconds before the next shot can occur.
var fire_cooldown: float = 0.0

## Cached collision [RID] array of this turret to prevent self-hits.
var _exclude_rids: Array[RID] = []

## Cached reference to the active [Player] node in the scene tree.
var _cached_player: Node3D = null

## Timer counting elapsed seconds toward the next proximity check.
var _proximity_timer: float = 0.0

## Flag indicating whether this turret is currently dormant to save CPU.
var _is_sleeping: bool = false

## Flag indicating whether the turret's bounding box is inside camera view.
var _is_on_screen: bool = false


## Initializes collision shapes, caches references, and binds screen visibility.
func _ready() -> void:
	print("Turret: Initializing turret instance: ", name)
	var visualizer: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if visualizer != null:
		visualizer.set("shape_type", EditorTriggerVisualizer.ShapeType.SPHERE)
		visualizer.set("trigger_size", Vector3.ONE * (detection_radius * 2.0))

	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = detection_radius
	detection_shape.shape = sphere

	detection_area.collision_layer = CollisionLayers.MASK_NONE
	detection_area.collision_mask = (CollisionLayers.MASK_PLAYER | CollisionLayers.MASK_ENEMIES)

	Utilities.safe_connect(detection_area.body_entered, _on_body_entered)
	Utilities.safe_connect(detection_area.body_exited, _on_body_exited)
	Utilities.safe_connect(detection_area.area_entered, _on_area_entered)
	Utilities.safe_connect(detection_area.area_exited, _on_area_exited)

	Utilities.safe_connect(screen_notifier.screen_entered, _on_screen_entered)
	Utilities.safe_connect(screen_notifier.screen_exited, _on_screen_exited)
	_is_on_screen = screen_notifier.is_on_screen()

	hitscan_ray.enabled = false
	hitscan_ray.collide_with_areas = true
	_build_exclude_rids(self)
	_evaluate_sleep_state()


## Signal callback when the turret enters the camera view frustum.
func _on_screen_entered() -> void:
	print("Turret: Entered camera frustum: ", name)
	_is_on_screen = true
	_evaluate_sleep_state()


## Signal callback when the turret leaves the camera view frustum.
func _on_screen_exited() -> void:
	print("Turret: Left camera frustum: ", name)
	_is_on_screen = false
	_evaluate_sleep_state()


## Evaluates sleep state based on screen visibility OR proximity.
func _evaluate_sleep_state() -> void:
	if not is_instance_valid(_cached_player):
		_find_player()

	var is_nearby: bool = false
	if is_instance_valid(_cached_player):
		var dist_sq: float = global_position.distance_squared_to(_cached_player.global_position)
		is_nearby = dist_sq <= (sleep_distance * sleep_distance)

	var should_sleep: bool = not (_is_on_screen or is_nearby)

	if should_sleep != _is_sleeping:
		_is_sleeping = should_sleep
		if _is_sleeping:
			_enter_sleep()
		else:
			_wake_up()


## Puts the turret to sleep, disabling area monitoring and particle systems.
func _enter_sleep() -> void:
	print("Turret: Entering sleep mode: ", name)
	detection_area.monitoring = false
	bullet_particles.emitting = false
	if target != null:
		_set_target(null)
		_change_state(TurretState.SCANNING)


## Wakes the turret from sleep, reenabling area monitoring and scanning.
func _wake_up() -> void:
	print("Turret: Waking up from sleep mode: ", name)
	detection_area.monitoring = true
	_acquire_new_target()


## Finds and caches the player instance from the player node group.
func _find_player() -> void:
	if not is_inside_tree():
		return
	_cached_player = NodeQuery.get_single_node_in_group(get_tree(), &"player") as Node3D


## Recursively aggregates collision [RID] instances across child nodes.
## [param node] The root [Node] to recursively harvest collision RIDs from.
func _build_exclude_rids(node: Node) -> void:
	if node is CollisionObject3D:
		_exclude_rids.append((node as CollisionObject3D).get_rid())
	for child: Node in node.get_children():
		_build_exclude_rids(child)


## Steps sleep checks, panning rotations, and active target engagements.
## [param delta] The physics step duration in seconds.
func _process(delta: float) -> void:
	_proximity_timer += delta
	if _proximity_timer >= proximity_interval:
		_proximity_timer = 0.0
		_evaluate_sleep_state()

	if _is_sleeping or is_friendly:
		if not _is_sleeping and is_friendly:
			_process_scanning(delta)
		return

	match current_state:
		TurretState.SCANNING:
			_process_scanning(delta)
		TurretState.ENGAGING:
			_process_engaging(delta)


## Changes state and handles particle deactivation on scan transition.
## [param new_state] The target [enum TurretState] to transition to.
func _change_state(new_state: TurretState) -> void:
	print("Turret: Transitioning operational state to: ", new_state)
	current_state = new_state

	if current_state == TurretState.SCANNING:
		bullet_particles.emitting = false


## Pans the turret head continuously around its Y axis while searching.
## [param delta] The physics step duration in seconds.
func _process_scanning(delta: float) -> void:
	head.rotate_y(scan_speed * delta)


## Tracks the active target, validates line of sight, and triggers shots.
## [param delta] The physics step duration in seconds.
func _process_engaging(delta: float) -> void:
	if not _is_active_target(target):
		_set_target(null)
		_change_state(TurretState.SCANNING)
		return

	_aim_at_target(delta)

	if _has_line_of_sight() and _is_aimed_at_target():
		_handle_shooting(delta)
	else:
		bullet_particles.emitting = false


## Assigns a target and retrieves its [HealthComponent] instance.
## [param new_target] The target [Node3D] to lock onto.
func _set_target(new_target: Node3D) -> void:
	print("Turret: Assigning target entity: ", new_target)
	target = new_target
	target_health_comp = null

	if target == null:
		return

	target_health_comp = (
		NodeQuery.find_first_child_of_type(target, HealthComponent) as HealthComponent
	)


## Validates that the target is still alive, visible, and processing.
## [param node] The target [Node3D] to check for active state.
## Returns `true` if active, `false` otherwise.
func _is_active_target(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not node.visible or node.process_mode == Node.PROCESS_MODE_DISABLED:
		return false
	return true


## Checks if a node belongs to any defined hostile group.
## [param node] The [Node] to check against hostile group names.
## Returns `true` if hostile, `false` otherwise.
func _is_hostile(node: Node) -> bool:
	for group: StringName in hostile_groups:
		if node.is_in_group(group):
			return true
	return false


## Computes the target offset, clearing offset for [ShootingTarget].
## Returns the calculated aim offset [Vector3].
func _get_actual_aim_offset() -> Vector3:
	if target is ShootingTarget:
		return Vector3.ZERO
	return aim_offset


## Interpolates head rotation toward the target using quaternion slerp.
## [param delta] The physics step duration in seconds.
func _aim_at_target(delta: float) -> void:
	var target_pos: Vector3 = target.global_position + _get_actual_aim_offset()
	var cur_tr: Transform3D = head.global_transform
	var target_tr: Transform3D = cur_tr.looking_at(target_pos, Vector3.UP, true)

	var cur_q: Quaternion = cur_tr.basis.get_rotation_quaternion()
	var tgt_q: Quaternion = target_tr.basis.get_rotation_quaternion()

	head.global_transform.basis = Basis(cur_q.slerp(tgt_q, turn_speed * delta))


## Performs a space state raycast to confirm clear line of sight.
## Returns `true` if unobstructed line of sight exists, `false` otherwise.
func _has_line_of_sight() -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start_pos: Vector3 = hitscan_ray.global_position
	var end_pos: Vector3 = target.global_position + _get_actual_aim_offset()

	var mask: int = (
		CollisionLayers.MASK_ENVIRONMENT
		| CollisionLayers.MASK_PLAYER
		| CollisionLayers.MASK_ENEMIES
	)
	var hit: Dictionary = Utilities.raycast_3d(space, start_pos, end_pos, mask, _exclude_rids)

	return bool(hit and hit.get("collider") == target)


## Evaluates dot product between muzzle forward vector and target vector.
## Returns `true` if aiming directly at target within tolerance.
func _is_aimed_at_target() -> bool:
	var target_pos: Vector3 = target.global_position + _get_actual_aim_offset()
	var dir_to_target: Vector3 = hitscan_ray.global_position.direction_to(target_pos)
	var ray_target: Vector3 = hitscan_ray.to_global(hitscan_ray.target_position)
	var forward_dir: Vector3 = hitscan_ray.global_position.direction_to(ray_target)

	return forward_dir.dot(dir_to_target) > 0.98


## Decrements weapon cooldown and fires when ready.
## [param delta] The physics step duration in seconds.
func _handle_shooting(delta: float) -> void:
	fire_cooldown -= delta
	if fire_cooldown <= 0.0:
		shoot()
		fire_cooldown = fire_rate


## Emits muzzle particles and inflicts damage on the active target.
func shoot() -> void:
	print("Turret: Discharging hitscan weapon at target: ", target.name)
	bullet_particles.emitting = true
	if is_instance_valid(target):
		_damage_target()


## Applies damage to the cached [HealthComponent] on the target.
func _damage_target() -> void:
	if is_instance_valid(target_health_comp):
		print("Turret: Dealing hitscan damage: ", damage)
		target_health_comp.take_damage(damage)


## Handles new bodies entering the spherical detection boundary.
## [param body] The [Node3D] that entered the detection area.
func _on_body_entered(body: Node3D) -> void:
	if _is_sleeping or is_friendly:
		return
	if _is_hostile(body) and _is_active_target(body):
		print("Turret: Hostile body entered perimeter: ", body.name)
		_set_target(body)
		_change_state(TurretState.ENGAGING)


## Handles bodies exiting the detection boundary and re-acquires.
## [param body] The [Node3D] that exited the detection area.
func _on_body_exited(body: Node3D) -> void:
	if body == target:
		print("Turret: Target body left perimeter: ", body.name)
		_acquire_new_target()


## Handles new areas entering the spherical detection boundary.
## [param area] The [Area3D] that entered the detection area.
func _on_area_entered(area: Area3D) -> void:
	if _is_sleeping or is_friendly:
		return
	if _is_hostile(area) and _is_active_target(area):
		print("Turret: Hostile area entered perimeter: ", area.name)
		_set_target(area)
		_change_state(TurretState.ENGAGING)


## Handles areas exiting the detection boundary and re-acquires.
## [param area] The [Area3D] that exited the detection area.
func _on_area_exited(area: Area3D) -> void:
	if area == target:
		print("Turret: Target area left perimeter: ", area.name)
		_acquire_new_target()


## Scans overlapping colliders in the detection area for a target.
func _acquire_new_target() -> void:
	if _is_sleeping:
		return

	print("Turret: Scanning overlapping geometry for hostile targets.")
	_set_target(null)

	for b: Node3D in detection_area.get_overlapping_bodies():
		if _is_hostile(b) and _is_active_target(b) and b != self:
			_set_target(b)
			_change_state(TurretState.ENGAGING)
			return

	for a: Area3D in detection_area.get_overlapping_areas():
		if _is_hostile(a) and _is_active_target(a):
			_set_target(a)
			_change_state(TurretState.ENGAGING)
			return

	_change_state(TurretState.SCANNING)
