## Coordinates drone formations, layout cycling, area exploration, and player healing.
@tool
class_name DroneSwarmController
extends Node3D

## Emitted when drone swarm starts healing player.
signal healing_started(target_player: Node3D)

## Emitted when player healing finishes cleanly.
signal healing_completed(target_player: Node3D)

## Available formation layout arrangements.
enum Formation { CIRCLE, SQUARE, CROSS }

## Operational behavioral modes for swarm.
enum Mode { IDLE, PATH_FOLLOW, FORMATION, HEAL_PLAYER, EXPLORE }

## Drone packed scene instantiated in swarm.
@export var drone_scene: PackedScene:
	set(value):
		drone_scene = value
		if Engine.is_editor_hint() and is_inside_tree():
			spawn_drones()

## Total drone instances spawned in swarm.
@export_range(1, 64) var drone_count: int = 10:
	set(value):
		drone_count = value
		if Engine.is_editor_hint() and is_inside_tree():
			spawn_drones()

## Active geometric arrangement of drones.
@export var formation: Formation = Formation.CIRCLE

## Active operational movement mode of swarm.
@export var mode: Mode = Mode.PATH_FOLLOW

## Radius in meters from swarm center to slots.
@export var formation_radius: float = 3.5

## Formation transition interpolation speed.
@export var formation_transition_speed: float = 3.5

## Peak vertical height offset for flight wave.
@export var wave_amplitude: float = 1.2

## Oscillation frequency for vertical wave.
@export var wave_frequency: float = 2.4

## Phase shift offset between adjacent drones.
@export var wave_phase_step: float = 0.45

## Path curve followed in path follow mode.
@export var path_to_follow: Path3D

## Traversal speed along path curve in m/s.
@export var path_speed: float = 3.0

## Fallback player node to heal if needed.
@export var player_target: Node3D

## Enables automated periodic layout cycling.
@export var auto_cycle_formations: bool = true

## Interval in seconds between layout cycles.
@export var cycle_interval: float = 6.0

## Detection radius in meters sensing player.
@export var detection_radius: float = 30.0

## Health points restored to player per second.
@export var heal_rate_per_sec: float = 25.0

## Orbit angular velocity in radians per second.
@export var orbit_speed: float = 1.6

## Exploration radius in meters for free roaming.
@export var explore_radius: float = 30.0

## Interval in seconds between wander re-routes.
@export var explore_retarget_interval: float = 4.0

## Internal list of active managed drone nodes.
var drones: Array[ElfDrone] = []

## Interpolated local offset coordinates.
var current_offsets: Array[Vector3] = []

## Target wander destinations per drone slot.
var explore_targets: Array[Vector3] = []

## Timer tracking next wander retargeting.
var explore_timer: float = 0.0

## Running elapsed time in seconds for waves.
var elapsed_time: float = 0.0

## Distance traveled along path curve in meters.
var path_progress: float = 0.0

## Elapsed duration tracking next layout cycle.
var cycle_timer: float = 0.0

## Cumulative orbit angle in radians.
var orbit_angle: float = 0.0

## Fractional health points awaiting award.
var heal_accumulator: float = 0.0

## Saved mode restored after healing completes.
var previous_mode: Mode = Mode.PATH_FOLLOW

## Saved layout restored after healing completes.
var previous_formation: Formation = Formation.CIRCLE

## Player reference currently detected in range.
var detected_player: Node3D = null

## Detection area sensing nearby player body.
var detector_area: Area3D = null


## Cleans up spawned preview drones when leaving tree.
func _exit_tree() -> void:
	print("DroneSwarmController: _exit_tree() cleaning up drones.")
	_clear_drones()


## Initializes detection volume, events, and spawns drones.
func _ready() -> void:
	print("DroneSwarmController: _ready() initializing swarm controller.")
	if not Engine.is_editor_hint():
		_setup_detector_area()
		if has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("player_damaged"):
				events.player_damaged.connect(_on_player_damaged)
	spawn_drones()


## Drives swarm behavior, formations, waves, and movement.
func _physics_process(delta: float) -> void:
	elapsed_time += delta
	var center_pos: Vector3 = global_position

	if not Engine.is_editor_hint():
		if is_instance_valid(detector_area) and detected_player == null:
			for body: Node3D in detector_area.get_overlapping_bodies():
				if _is_player(body):
					detected_player = body
					break
		_check_player_health_and_state(delta)

	if auto_cycle_formations and mode != Mode.HEAL_PLAYER and mode != Mode.EXPLORE:
		_process_auto_cycling(delta)

	if mode == Mode.EXPLORE:
		_process_explore_mode(delta)

	match mode:
		Mode.PATH_FOLLOW:
			if path_to_follow != null and path_to_follow.curve != null:
				var curve_len: float = path_to_follow.curve.get_baked_length()
				if curve_len > 0.0:
					path_progress = fmod(path_progress + (path_speed * delta), curve_len)
					var local_pos: Vector3 = path_to_follow.curve.sample_baked(path_progress)
					center_pos = path_to_follow.to_global(local_pos)

		Mode.HEAL_PLAYER:
			var target: Node3D = _find_player_target()
			if target != null:
				center_pos = target.global_position
				orbit_angle += orbit_speed * delta

		Mode.FORMATION, Mode.IDLE, Mode.EXPLORE:
			center_pos = global_position

	if is_instance_valid(detector_area):
		detector_area.global_position = center_pos

	for i: int in range(drones.size()):
		var drone: ElfDrone = drones[i]
		if not is_instance_valid(drone):
			continue

		var target_offset: Vector3 = Vector3.ZERO
		if mode == Mode.EXPLORE and i < explore_targets.size():
			target_offset = explore_targets[i]
		else:
			target_offset = calculate_slot_offset(i, drones.size())

		current_offsets[i] = current_offsets[i].lerp(
			target_offset, clampf(formation_transition_speed * delta, 0.0, 1.0)
		)

		var target_pos: Vector3 = center_pos + current_offsets[i]
		target_pos = apply_wave_motion(i, target_pos)
		drone.set_target_position(target_pos)

		if Engine.is_editor_hint():
			drone.global_position = target_pos


## Ticks wander retargeting timer in exploration mode.
func _process_explore_mode(delta: float) -> void:
	explore_timer += delta
	if explore_timer >= explore_retarget_interval:
		explore_timer = 0.0
		_retarget_explore_positions()


## Generates randomized offsets within exploration radius.
func _retarget_explore_positions() -> void:
	print("DroneSwarmController: _retarget_explore_positions() picking targets.")
	for i: int in range(explore_targets.size()):
		var random_dir: Vector3 = (
			Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3), randf_range(-1.0, 1.0))
			. normalized()
		)
		var random_dist: float = randf_range(2.0, explore_radius)
		explore_targets[i] = random_dir * random_dist


## Creates player detection trigger volume.
func _setup_detector_area() -> void:
	print("DroneSwarmController: _setup_detector_area() creating area.")
	detector_area = Area3D.new()
	detector_area.name = "PlayerDetectionArea"
	detector_area.collision_layer = 0
	detector_area.collision_mask = 2

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = detection_radius
	col_shape.shape = sphere

	detector_area.add_child(col_shape)
	add_child(detector_area)

	detector_area.body_entered.connect(_on_detector_body_entered)
	detector_area.body_exited.connect(_on_detector_body_exited)


## Handles body entered event on [Area3D].
func _on_detector_body_entered(body: Node3D) -> void:
	print("DroneSwarmController: _on_detector_body_entered() body: ", body.name)
	if _is_player(body):
		detected_player = body


## Handles body exited event on [Area3D].
func _on_detector_body_exited(body: Node3D) -> void:
	print("DroneSwarmController: _on_detector_body_exited() body: ", body.name)
	if body == detected_player:
		if mode == Mode.HEAL_PLAYER:
			stop_healing_player()
		detected_player = null


## Handles global player damage notification from [Events].
func _on_player_damaged(_amount: int) -> void:
	print("DroneSwarmController: Player damage signaled via Events bus.")
	_check_player_health_and_state(0.0)


## Checks if target node is valid player entity.
func _is_player(node: Node3D) -> bool:
	if node == null:
		return false
	if node == player_target or node.is_in_group(&"player"):
		return true
	var health_comp: HealthComponent = _get_health_component(node)
	if health_comp != null and health_comp.is_player_health:
		return true
	return false


## Finds player node reference via target, detected, or group.
func _find_player_target() -> Node3D:
	if is_instance_valid(player_target):
		return player_target
	if is_instance_valid(detected_player):
		return detected_player
	var player_nodes: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if not player_nodes.is_empty() and player_nodes[0] is Node3D:
		return player_nodes[0] as Node3D
	return null


## Finds [HealthComponent] on target entity using query fallbacks.
func _get_health_component(node: Node) -> HealthComponent:
	if not is_instance_valid(node):
		return null
	if "health_component" in node:
		var comp: Variant = node.get("health_component")
		if comp is HealthComponent:
			return comp as HealthComponent
	var direct: Node = node.get_node_or_null("HealthComponent")
	if direct is HealthComponent:
		return direct as HealthComponent
	var comp_dir: Node = node.get_node_or_null("Components/HealthComponent")
	if comp_dir is HealthComponent:
		return comp_dir as HealthComponent
	var found: HealthComponent = (
		NodeQuery.find_first_child_of_type(node, HealthComponent) as HealthComponent
	)
	if is_instance_valid(found):
		return found
	for child: Node in node.get_children():
		if child is HealthComponent:
			return child as HealthComponent
	return null


## Checks player health and dispenses healing.
func _check_player_health_and_state(delta: float) -> void:
	var target: Node3D = _find_player_target()
	if target == null:
		return

	var dist_to_player: float = global_position.distance_to(target.global_position)
	if dist_to_player > detection_radius and mode != Mode.HEAL_PLAYER:
		return

	var health_comp: HealthComponent = _get_health_component(target)
	if health_comp == null:
		var dmg_nodes: Array[Node] = get_tree().get_nodes_in_group(&"damageable")
		for d: Node in dmg_nodes:
			if d is HealthComponent and (d as HealthComponent).is_player_health:
				health_comp = d as HealthComponent
				break

	if health_comp == null:
		return

	if health_comp.current_health < health_comp.max_health:
		if mode != Mode.HEAL_PLAYER:
			start_healing_player(target)
		else:
			heal_accumulator += heal_rate_per_sec * delta
			if heal_accumulator >= 1.0:
				var points: int = int(heal_accumulator)
				heal_accumulator -= float(points)
				health_comp.heal(points)
				print("DroneSwarmController: Dispensed ", points, " HP to player.")
	elif mode == Mode.HEAL_PLAYER:
		print("DroneSwarmController: Target reached max health.")
		stop_healing_player()


## Switches swarm into healing orbit routine.
func start_healing_player(target: Node3D) -> void:
	print("DroneSwarmController: start_healing_player() initiating healing orbit.")
	previous_mode = mode
	previous_formation = formation
	mode = Mode.HEAL_PLAYER
	formation = Formation.CIRCLE
	heal_accumulator = 0.0

	for drone: ElfDrone in drones:
		if is_instance_valid(drone):
			drone.set_healing_target(target)

	healing_started.emit(target)


## Restores swarm back to prior operation mode.
func stop_healing_player() -> void:
	print("DroneSwarmController: stop_healing_player() returning to prior mode.")
	var healed_node: Node3D = _find_player_target()
	mode = previous_mode
	formation = previous_formation
	cycle_timer = 0.0

	for drone: ElfDrone in drones:
		if is_instance_valid(drone):
			drone.set_healing_target(null)

	if healed_node != null:
		healing_completed.emit(healed_node)


## Ticks automated layout cycling timer.
func _process_auto_cycling(delta: float) -> void:
	cycle_timer += delta
	if cycle_timer >= cycle_interval:
		cycle_timer = 0.0
		cycle_next_formation()


## Cycles layout to next formation in sequence.
func cycle_next_formation() -> void:
	var next_idx: int = (int(formation) + 1) % 3
	var next_formation: Formation = next_idx as Formation
	print("DroneSwarmController: cycle_next_formation() cycling to: ", next_formation)
	set_formation(next_formation)


## Clears and frees all managed drone instances.
func _clear_drones() -> void:
	print("DroneSwarmController: _clear_drones() clearing instances.")
	for drone: ElfDrone in drones:
		if is_instance_valid(drone):
			drone.queue_free()
	drones.clear()
	current_offsets.clear()
	explore_targets.clear()


## Instantiates configured drone instances.
func spawn_drones() -> void:
	print("DroneSwarmController: spawn_drones() spawning drone flock.")
	_clear_drones()
	if drone_scene == null:
		return

	for i: int in range(drone_count):
		var instance: Node = drone_scene.instantiate()
		if instance is ElfDrone:
			var drone: ElfDrone = instance as ElfDrone
			add_child(drone)
			var offset: Vector3 = calculate_slot_offset(i, drone_count)
			drone.global_position = global_position + offset
			drone.task_state = ElfDrone.TaskState.FOLLOW_SWARM
			drones.append(drone)
			current_offsets.append(offset)
			explore_targets.append(offset)


## Sets active formation layout for swarm.
func set_formation(new_formation: Formation) -> void:
	print("DroneSwarmController: set_formation() setting layout to: ", new_formation)
	formation = new_formation


## Sets active operational mode for swarm.
func set_mode(new_mode: Mode) -> void:
	print("DroneSwarmController: set_mode() setting mode to: ", new_mode)
	mode = new_mode


## Switches swarm layout to cross formation.
func switch_to_cross_formation(_param: Variant = null) -> void:
	print("DroneSwarmController: switch_to_cross_formation() executed.")
	set_mode(Mode.FORMATION)
	set_formation(Formation.CROSS)


## Computes local slot offset coordinate.
func calculate_slot_offset(index: int, total: int) -> Vector3:
	if total <= 0:
		return Vector3.ZERO

	match formation:
		Formation.CIRCLE:
			var angle: float = (TAU / float(total)) * float(index) + orbit_angle
			return Vector3(cos(angle) * formation_radius, 0.0, sin(angle) * formation_radius)
		Formation.SQUARE:
			return _calculate_square_offset(index, total)
		Formation.CROSS:
			return _calculate_cross_offset(index, total)

	return Vector3.ZERO


## Calculates slot position along square edge.
func _calculate_square_offset(index: int, total: int) -> Vector3:
	var perimeter_progress: float = (float(index) / float(total)) * 4.0
	var r: float = formation_radius
	var side_t: float = fmod(perimeter_progress, 1.0)
	var edge: int = int(perimeter_progress) % 4

	match edge:
		0:
			return Vector3(-r + (2.0 * r * side_t), 0.0, -r)
		1:
			return Vector3(r, 0.0, -r + (2.0 * r * side_t))
		2:
			return Vector3(r - (2.0 * r * side_t), 0.0, r)
		3:
			return Vector3(-r, 0.0, r - (2.0 * r * side_t))

	return Vector3.ZERO


## Calculates slot position along cross axes.
func _calculate_cross_offset(index: int, total: int) -> Vector3:
	var half: int = maxi(1, int(float(total) / 2.0))
	if index < half:
		var denom: float = float(maxi(1, half - 1))
		var t: float = ((float(index) / denom) - 0.5) * 2.0
		return Vector3(t * formation_radius, 0.0, 0.0)

	var count_z: int = total - half
	var denom_z: float = float(maxi(1, count_z - 1))
	var idx_z: int = index - half
	var tz: float = ((float(idx_z) / denom_z) - 0.5) * 2.0
	return Vector3(0.0, 0.0, tz * formation_radius)


## Applies vertical flight wave displacement.
func apply_wave_motion(index: int, base_pos: Vector3) -> Vector3:
	var phase: float = float(index) * wave_phase_step
	var wave_y: float = sin((elapsed_time * wave_frequency) + phase) * wave_amplitude
	base_pos.y += wave_y
	return base_pos


## Adopts solo drone into active swarm flock smoothly.
func adopt_drone(solo_drone: ElfDrone) -> void:
	print("DroneSwarmController: adopt_drone() adopting solo drone.")
	if not is_instance_valid(solo_drone) or drones.has(solo_drone):
		return

	drones.append(solo_drone)
	var local_offset: Vector3 = solo_drone.global_position - global_position
	current_offsets.append(local_offset)
	explore_targets.append(local_offset)
	drone_count = drones.size()
	solo_drone.task_state = ElfDrone.TaskState.FOLLOW_SWARM
