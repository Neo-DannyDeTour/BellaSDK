## Coordinates enemy wave lifecycles, timers, and Events bus notifications.
class_name WaveSpawner
extends Node3D

## Emitted when all defined waves are completed.
@warning_ignore("unused_signal")
signal all_waves_completed(total_waves: int)

## Enemy scene instantiated during wave spawning.
@export var enemy_scene: PackedScene

## Marker nodes defining 3D spawn coordinates in world.
@export var spawn_points: Array[Node3D] = []

## Total number of waves to run (-1 for endless scaling).
@export var total_waves: int = 5

## Base enemy count for wave 1 before scaling.
@export var base_enemy_count: int = 4

## Multiplier applied to enemy count on subsequent waves.
@export var wave_growth_rate: float = 1.3

## Minimum interval duration between enemy spawns in seconds.
@export var min_spawn_interval: float = 0.5

## Maximum interval duration between enemy spawns in seconds.
@export var max_spawn_interval: float = 1.5

## Current active wave index (1-based, 0 when inactive).
var current_wave: int = 0

## Number of enemies remaining to spawn in current wave.
var _remaining_to_spawn: int = 0

## Array tracking active living enemy nodes spawned.
var _alive_enemies: Array[Node3D] = []

## Pre-cached array of valid spawn points preventing per-tick allocation.
var _valid_spawn_points: Array[Node3D] = []

## Dedicated deterministic random number generator.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## State flag indicating whether wave spawning is running.
var _is_running: bool = false


## Lifecycle setup caching spawn points and binding events.
func _ready() -> void:
	print("WaveSpawner: [", name, "] initializing wave spawner node.")
	_cache_spawn_points()
	_connect_event_bus()


## Caches non-null spawn point nodes to avoid heap allocations during waves.
func _cache_spawn_points() -> void:
	print("WaveSpawner: [", name, "] caching spawn points.")
	_valid_spawn_points.clear()
	for pt: Node3D in spawn_points:
		if is_instance_valid(pt):
			_valid_spawn_points.append(pt)


## Connects to global [Events] for tracking combat lifecycle.
func _connect_event_bus() -> void:
	print("WaveSpawner: [", name, "] connecting to global event bus.")
	if is_instance_valid(Events):
		if Events.has_signal(&"enemy_killed"):
			Utilities.safe_connect(Events.enemy_killed, _on_enemy_killed)


## Starts wave sequence execution beginning from wave 1.
func start_spawner() -> void:
	print("WaveSpawner: [", name, "] starting wave spawner sequence.")
	_is_running = true
	current_wave = 0
	start_next_wave()


## Halts active spawner execution.
func stop_spawner() -> void:
	print("WaveSpawner: [", name, "] stopping wave spawner sequence.")
	_is_running = false


## Advances to next wave and broadcasts [signal Events.wave_started].
func start_next_wave() -> void:
	print("WaveSpawner: [", name, "] start_next_wave() advancing wave.")
	if not _is_running:
		return

	current_wave += 1
	if total_waves > 0 and current_wave > total_waves:
		print("WaveSpawner: [", name, "] all ", total_waves, " waves cleared!")
		_is_running = false
		all_waves_completed.emit(total_waves)
		return

	var wave_count: int = int(
		round(float(base_enemy_count) * pow(wave_growth_rate, current_wave - 1))
	)
	_remaining_to_spawn = wave_count
	print("WaveSpawner: Wave ", current_wave, " started with ", wave_count, " units.")

	if is_instance_valid(Events) and Events.has_signal(&"wave_started"):
		Events.wave_started.emit(current_wave)

	_schedule_next_spawn()


## Schedules next spawn tick using [method Utilities.delay_call].
func _schedule_next_spawn() -> void:
	print("WaveSpawner: [", name, "] scheduling next spawn.")
	if not _is_running or _remaining_to_spawn <= 0:
		return

	var interval: float = _rng.randf_range(min_spawn_interval, max_spawn_interval)
	Utilities.delay_call(self, interval, _spawn_one_enemy)


## Instantiates one enemy unit at an available spawn point.
func _spawn_one_enemy() -> void:
	print("WaveSpawner: [", name, "] spawning single enemy unit.")
	if not _is_running or _remaining_to_spawn <= 0:
		return

	if not is_instance_valid(enemy_scene):
		push_error("WaveSpawner: [", name, "] enemy_scene is not assigned.")
		return

	var spawn_pos: Vector3 = global_position
	if not _valid_spawn_points.is_empty():
		var idx: int = _rng.randi() % _valid_spawn_points.size()
		spawn_pos = _valid_spawn_points[idx].global_position

	var enemy_instance: Node = enemy_scene.instantiate()
	var enemy_node: Node3D = enemy_instance as Node3D
	if not is_instance_valid(enemy_node):
		push_error("WaveSpawner: [", name, "] instantiated enemy is not Node3D.")
		return

	var target_parent: Node = get_tree().current_scene
	if target_parent == null:
		target_parent = get_parent() if get_parent() != null else self
	target_parent.add_child(enemy_node)
	enemy_node.global_position = spawn_pos
	_alive_enemies.append(enemy_node)
	_remaining_to_spawn -= 1

	var faction_comp: Node = FactionComponent.get_faction_component(enemy_node)
	if is_instance_valid(faction_comp) and faction_comp.has_method(&"set_faction"):
		faction_comp.call(&"set_faction", Types.Faction.ENEMY)

	if is_instance_valid(Events) and Events.has_signal(&"enemy_spawned"):
		Events.enemy_spawned.emit(enemy_node)

	if _remaining_to_spawn > 0:
		_schedule_next_spawn()


## Tracks enemy deaths and completes wave when living count hits zero.
## [param enemy_node]: Slain enemy instance.
## [param killer_node]: Entity dealing final blow.
func _on_enemy_killed(enemy_node: Node3D, killer_node: Node3D = null) -> void:
	var killer_name: String = killer_node.name if is_instance_valid(killer_node) else "unknown"
	var enemy_name: String = enemy_node.name if is_instance_valid(enemy_node) else "unknown"
	print("WaveSpawner: Enemy ", enemy_name, " slain by ", killer_name)

	var valid_enemies: Array[Node3D] = []
	for node: Node3D in _alive_enemies:
		if is_instance_valid(node) and node != enemy_node:
			valid_enemies.append(node)
	_alive_enemies = valid_enemies

	if _remaining_to_spawn <= 0 and _alive_enemies.is_empty() and _is_running:
		print("WaveSpawner: Wave ", current_wave, " completed.")
		if is_instance_valid(Events) and Events.has_signal(&"wave_completed"):
			Events.wave_completed.emit(current_wave)
		Utilities.delay_call(self, 2.0, start_next_wave)
