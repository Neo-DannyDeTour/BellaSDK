## Coordinates drone formations, automated layout cycling, area detection, and player healing.
class_name DroneSwarmController
extends Node3D

## Emitted when the swarm transitions to healing [param target_player].
signal healing_started(target_player: Node3D)

## Emitted when player healing completes and previous behavior resumes.
signal healing_completed(target_player: Node3D)

## Geometric formation layouts available for drone distribution.
enum Formation {
	CIRCLE,
	SQUARE,
	CROSS,
}

## Active operational behavioral modes for drone swarm coordination.
enum Mode {
	IDLE,
	PATH_FOLLOW,
	FORMATION,
	HEAL_PLAYER,
}

## Packed scene resource used to instantiate individual [ElfDrone] instances.
@export var drone_scene: PackedScene

## Total count of [ElfDrone] instances to instantiate and coordinate.
@export_range(1, 64) var drone_count: int = 10

## Active geometric arrangement applied across active swarm members.
@export var formation: Formation = Formation.CIRCLE

## Active operational routine dictating swarm movement behavior.
@export var mode: Mode = Mode.PATH_FOLLOW

## Radial distance in units from center to outer edge of active formation.
@export var formation_radius: float = 3.5

## Speed of smooth interpolation when transitioning between formations.
@export var formation_transition_speed: float = 3.5

## Peak vertical offset in units for undulating flight wave motions.
@export var wave_amplitude: float = 1.2

## Oscillation speed factor controlling vertical wave frequency.
@export var wave_frequency: float = 2.4

## Phase shift between adjacent drones along undulating vertical wave.
@export var wave_phase_step: float = 0.45

## [Path3D] node providing waypoint curve data for path following mode.
@export var path_to_follow: Path3D

## Movement speed of swarm center along [member path_to_follow] in units/sec.
@export var path_speed: float = 3.0

## Fallback player [Node3D] node to heal when not detected dynamically.
@export var player_target: Node3D

## Enables automated periodic cycling through available formations.
@export var auto_cycle_formations: bool = true

## Duration in seconds spent in each formation before auto-cycling.
@export var cycle_interval: float = 6.0

## Radius in units used by detection area to sense nearby players.
@export var detection_radius: float = 12.0

## Rate of health points restored to damaged player per second.
@export var heal_rate_per_sec: float = 25.0

## Angular velocity in radians per second when orbiting healed player.
@export var orbit_speed: float = 1.6

## Internal list storing all managed [ElfDrone] active instances.
var drones: Array[ElfDrone] = []

## Interpolated local offset coordinates for smooth formation morphing.
var current_offsets: Array[Vector3] = []

## Running elapsed time in seconds used for undulating wave phase evaluation.
var elapsed_time: float = 0.0

## Distance traveled along [member path_to_follow] curve in units.
var path_progress: float = 0.0

## Elapsed duration in seconds tracking next formation cycle trigger.
var cycle_timer: float = 0.0

## Cumulative rotation angle in radians for circling around player.
var orbit_angle: float = 0.0

## Accumulated fractional health points waiting to be applied.
var heal_accumulator: float = 0.0

## Stored prior [enum Mode] restored after player healing completes.
var previous_mode: Mode = Mode.PATH_FOLLOW

## Stored prior [enum Formation] restored after healing completes.
var previous_formation: Formation = Formation.CIRCLE

## Active player reference currently detected within proximity radius.
var detected_player: Node3D = null

## Child [Area3D] sensing player entities entering detection bounds.
var detector_area: Area3D = null


## Spawns drone swarm, configures detection area, and initializes state.
func _ready() -> void:
	print("DroneSwarmController: _ready() - Initializing controller on ", name)
	_setup_detector_area()
	spawn_drones()


## Processes swarm logic, automated cycling, player detection, and waves.
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
		current_offsets[i] = current_offsets[i].lerp(
			target_offset, formation_transition_speed * delta
		)

		var target_pos: Vector3 = center_pos + current_offsets[i]
		target_pos = apply_wave_motion(i, target_pos)
		drone.set_target_position(target_pos)


## Constructs child [Area3D] configured with Layer 2 player mask.
func _setup_detector_area() -> void:
	print("DroneSwarmController: _setup_detector_area() - Building detection volume.")
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


## Handles entity entrance into detection bounds and checks player status.
func _on_detector_body_entered(body: Node3D) -> void:
	print("DroneSwarmController: _on_detector_body_entered() - Body entered: ", body.name)
	if _is_player(body):
		detected_player = body
		print("DroneSwarmController: Player registered in detection zone.")


## Clears detected player reference when entity leaves detection range.
func _on_detector_body_exited(body: Node3D) -> void:
	print("DroneSwarmController: _on_detector_body_exited() - Body exited: ", body.name)
	if body == detected_player:
		if mode == Mode.HEAL_PLAYER:
			stop_healing_player()
		detected_player = null


## Evaluates whether [param node] represents the player entity.
func _is_player(node: Node3D) -> bool:
	if node == null:
		return false
	if node == player_target or node.is_in_group(&"player"):
		return true
	var health_comp: HealthComponent = _get_health_component(node)
	if health_comp != null and health_comp.is_player_health:
		return true
	return false


## Locates [HealthComponent] on [param node] or child hierarchy.
func _get_health_component(node: Node) -> HealthComponent:
	if node == null:
		return null
	var direct: Node = node.get_node_or_null("Components/HealthComponent")
	if direct is HealthComponent:
		return direct as HealthComponent
	var root_child: Node = node.get_node_or_null("HealthComponent")
	if root_child is HealthComponent:
		return root_child as HealthComponent
	return null


## Checks player health and distributes healing at 25 points per second.
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
		print("DroneSwarmController: Player reached max health.")
		stop_healing_player()


## Transitions swarm into circular orbit around [param player] and activates beams.
func start_healing_player(player: Node3D) -> void:
	print("DroneSwarmController: start_healing_player() - Swarming player to heal.")
	previous_mode = mode
	previous_formation = formation
	mode = Mode.HEAL_PLAYER
	formation = Formation.CIRCLE
	heal_accumulator = 0.0

	for drone: ElfDrone in drones:
		if is_instance_valid(drone):
			drone.set_healing_target(player)

	healing_started.emit(player)


## Restores swarm back to previous mode and formation and turns off beams.
func stop_healing_player() -> void:
	print("DroneSwarmController: stop_healing_player() - Resuming previous behavior.")
	var healed_node: Node3D = detected_player if detected_player != null else player_target
	mode = previous_mode
	formation = previous_formation
	cycle_timer = 0.0

	for drone: ElfDrone in drones:
		if is_instance_valid(drone):
			drone.set_healing_target(null)

	if healed_node != null:
		healing_completed.emit(healed_node)


## Steps formation cycle timer and triggers transition on timeout.
func _process_auto_cycling(delta: float) -> void:
	cycle_timer += delta
	if cycle_timer >= cycle_interval:
		cycle_timer = 0.0
		cycle_next_formation()


## Advances active formation to next layout in sequence.
func cycle_next_formation() -> void:
	var next_idx: int = (int(formation) + 1) % 3
	var next_formation: Formation = next_idx as Formation
	print("DroneSwarmController: cycle_next_formation() - Cycling to ", next_formation)
	set_formation(next_formation)


## Instantiates [member drone_count] instances of [ElfDrone].
func spawn_drones() -> void:
	print("DroneSwarmController: spawn_drones() - Spawning ", drone_count, " elf drones.")
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


## Switches active [member formation] layout and logs transition.
func set_formation(new_formation: Formation) -> void:
	print("DroneSwarmController: set_formation() - Setting layout to ", new_formation)
	formation = new_formation


## Changes active [member mode] state to direct swarm behavior.
func set_mode(new_mode: Mode) -> void:
	print("DroneSwarmController: set_mode() - Changing mode to ", new_mode)
	mode = new_mode


## Computes local offset coordinate for drone slot based on formation.
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


## Distributes slot positions evenly along perimeter of a square.
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


## Arranges slot positions along crossing perpendicular axes.
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


## Applies vertical sinusoidal wave displacement to [param base_pos].
func apply_wave_motion(index: int, base_pos: Vector3) -> Vector3:
	var phase: float = float(index) * wave_phase_step
	var wave_y: float = sin((elapsed_time * wave_frequency) + phase) * wave_amplitude
	base_pos.y += wave_y
	return base_pos
