## Coordinates drone formations, automated cycling, and player healing.
class_name DroneSwarmController
extends Node3D

## Emitted when drone swarm starts healing player.
signal healing_started(target_player: Node3D)

## Emitted when player healing finishes cleanly.
signal healing_completed(target_player: Node3D)

## Available formation layout arrangements.
enum Formation { CIRCLE, SQUARE, CROSS }

## Operational behavioral modes for swarm.
enum Mode { IDLE, PATH_FOLLOW, FORMATION, HEAL_PLAYER }

## Drone packed scene instantiated in swarm.
@export var drone_scene: PackedScene

## Total drone instances spawned in swarm.
@export_range(1, 64) var drone_count: int = 10

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
@export var detection_radius: float = 12.0

## Health points restored to player per second.
@export var heal_rate_per_sec: float = 25.0

## Orbit angular velocity in radians per second.
@export var orbit_speed: float = 1.6

## Internal list of active managed drone nodes.
var drones: Array[ElfDrone] = []

## Interpolated local offset coordinates.
var current_offsets: Array[Vector3] = []

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


## Initializes detection volume and spawns drones.
func _ready() -> void:
	print("DroneSwarmController: _ready() initializing swarm controller.")
	_setup_detector_area()
	spawn_drones()


## Processes swarm logic, waves, and movement.
func _physics_process(delta: float) -> void:
	elapsed_time += delta
	var center_pos: Vector3 = global_position

	_check_player_health_and_state(delta)

	if auto_cycle_formations and mode != Mode.HEAL_PLAYER:
		_process_auto_cycling(delta)

	match mode:
		Mode.PATH_FOLLOW:
			if path_to_follow != null and path_to_follow.curve != null:
				var curve_len: float = path_to_follow.curve.get_baked_length()
				if curve_len > 0.0:
					path_progress = fmod(path_progress + (path_speed * delta), curve_len)
					var local_pos: Vector3 = path_to_follow.curve.sample_baked(path_progress)
					center_pos = path_to_follow.to_global(local_pos)

		Mode.HEAL_PLAYER:
			var target: Node3D = detected_player if detected_player != null else player_target
			if target != null:
				center_pos = target.global_position
				orbit_angle += orbit_speed * delta

		Mode.FORMATION, Mode.IDLE:
			center_pos = global_position

	if is_instance_valid(detector_area):
		detector_area.global_position = center_pos

	for i: int in range(drones.size()):
		var drone: ElfDrone = drones[i]
		if not is_instance_valid(drone):
			continue

		var target_offset: Vector3 = calculate_slot_offset(i, drones.size())
		current_offsets[i] = MathUtils.damp(
			current_offsets[i], target_offset, formation_transition_speed, delta
		)

		var target_pos: Vector3 = center_pos + current_offsets[i]
		target_pos = apply_wave_motion(i, target_pos)
		drone.set_target_position(target_pos)


## Creates player detection trigger volume.
func _setup_detector_area() -> void:
	print("DroneSwarmController: _setup_detector_area() creating area.")
	detector_area = Area3D.new()
	detector_area.name = "PlayerDetectionArea"
	detector_area.collision_layer = CollisionLayers.MASK_NONE
	detector_area.collision_mask = CollisionLayers.MASK_PLAYER

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = detection_radius
	col_shape.shape = sphere

	detector_area.add_child(col_shape)
	add_child(detector_area)

	detector_area.body_entered.connect(_on_detector_body_entered)
	detector_area.body_exited.connect(_on_detector_body_exited)


## Registers player entering detection volume.
func _on_detector_body_entered(body: Node3D) -> void:
	print("DroneSwarmController: _on_detector_body_entered() body: ", body.name)
	if _is_player(body):
		detected_player = body


## Clears player exiting detection volume.
func _on_detector_body_exited(body: Node3D) -> void:
	print("DroneSwarmController: _on_detector_body_exited() body: ", body.name)
	if body == detected_player:
		if mode == Mode.HEAL_PLAYER:
			stop_healing_player()
		detected_player = null


## Evaluates if given node is player entity.
func _is_player(node: Node3D) -> bool:
	if node == null:
		return false
	if node == player_target or node.is_in_group(&"player"):
		return true
	var health_comp: HealthComponent = _get_health_component(node)
	if health_comp != null and health_comp.is_player_health:
		return true
	return false


## Resolves [HealthComponent] on target entity.
func _get_health_component(node: Node) -> HealthComponent:
	if not is_instance_valid(node):
		return null
	return NodeQuery.find_first_child_of_type(node, HealthComponent) as HealthComponent


## Checks player health and dispenses healing.
func _check_player_health_and_state(delta: float) -> void:
	var target: Node3D = detected_player if detected_player != null else player_target
	if target == null:
		return

	var health_comp: HealthComponent = _get_health_component(target)
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
	var healed_node: Node3D = detected_player if detected_player != null else player_target
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


## Instantiates configured drone instances.
func spawn_drones() -> void:
	print("DroneSwarmController: spawn_drones() spawning drone flock.")
	if drone_scene == null:
		push_error("DroneSwarmController: No drone_scene assigned!")
		return

	for i: int in range(drone_count):
		var instance: Node = drone_scene.instantiate()
		if instance is ElfDrone:
			var drone: ElfDrone = instance as ElfDrone
			add_child(drone)
			var offset: Vector3 = calculate_slot_offset(i, drone_count)
			drone.global_position = global_position + offset
			drones.append(drone)
			current_offsets.append(offset)


## Sets active formation layout for swarm.
func set_formation(new_formation: Formation) -> void:
	print("DroneSwarmController: set_formation() setting layout to: ", new_formation)
	formation = new_formation


## Sets active operational mode for swarm.
func set_mode(new_mode: Mode) -> void:
	print("DroneSwarmController: set_mode() setting mode to: ", new_mode)
	mode = new_mode


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


## Adopts solo drone into active swarm flock.
func adopt_drone(solo_drone: ElfDrone) -> void:
	print("DroneSwarmController: adopt_drone() adopting solo drone.")
	if not is_instance_valid(solo_drone) or drones.has(solo_drone):
		return

	drones.append(solo_drone)
	current_offsets.append(solo_drone.global_position - global_position)
	drone_count = drones.size()

	mode = Mode.FORMATION
	formation = Formation.CIRCLE
	auto_cycle_formations = true
	cycle_timer = 0.0
