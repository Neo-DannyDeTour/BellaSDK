class_name WaveSpawner
extends Node3D
## Modular 3D wave spawner coordinating enemy wave lifecycles and global Events routing.

## Emitted locally when all defined waves are cleared. Passes [param total_waves].
@warning_ignore("unused_signal")
signal all_waves_completed(total_waves: int)

@export_category("Wave Configuration")
## Enemy scene instantiated during wave spawning.
@export var enemy_scene: PackedScene

## Marker nodes defining 3D spawn coordinates in the world.
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

## Number of enemies remaining to spawn in the current wave.
var _remaining_to_spawn: int = 0

## Array tracking active living enemy nodes spawned by this spawner.
var _alive_enemies: Array[Node3D] = []

## Timer node controlling spacing between individual unit spawns.
var _spawn_timer: Timer

## State flag indicating whether wave spawning is running.
var _is_running: bool = false


## Lifecycle setup initializing the spawn timer and connecting to Events.
func _ready() -> void:
	print("WaveSpawner: [", name, "] initializing wave spawner node.")
	_setup_spawn_timer()
	_connect_event_bus()


## Instantiates and configures the child spawn timer node.
func _setup_spawn_timer() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.name = "SpawnIntervalTimer"
	_spawn_timer.one_shot = true
	_spawn_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	Utilities.safe_connect(_spawn_timer.timeout, _on_spawn_timer_timeout)
	add_child(_spawn_timer)
	print("WaveSpawner: [", name, "] spawn interval timer initialized.")


## Connects to global [Events] for tracking combat lifecycle.
func _connect_event_bus() -> void:
	if is_instance_valid(Events):
		if Events.has_signal("enemy_killed"):
			Utilities.safe_connect(Events.enemy_killed, _on_enemy_killed)


## Starts wave sequence execution beginning from wave 1.
func start_spawner() -> void:
	print("WaveSpawner: [", name, "] starting wave spawner sequence.")
	_is_running = true
	current_wave = 0
	start_next_wave()


## Halts active spawner execution and stops pending spawn timers.
func stop_spawner() -> void:
	print("WaveSpawner: [", name, "] stopping wave spawner sequence.")
	_is_running = false
	if is_instance_valid(_spawn_timer) and not _spawn_timer.is_stopped():
		_spawn_timer.stop()


## Advances to the next wave and broadcasts [signal Events.wave_started].
func start_next_wave() -> void:
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
	print(
		"WaveSpawner: [", name, "] starting wave ", current_wave, " with ", wave_count, " enemies."
	)

	if is_instance_valid(Events) and Events.has_signal("wave_started"):
		Events.wave_started.emit(current_wave)

	_schedule_next_spawn()


## Picks random interval from [Global.rng] and starts spawn timer.
func _schedule_next_spawn() -> void:
	if not _is_running or _remaining_to_spawn <= 0:
		return

	var global_node: Node = get_node_or_null("/root/Global")
	var rng: RandomNumberGenerator = (
		global_node.get("rng") as RandomNumberGenerator
		if is_instance_valid(global_node) and "rng" in global_node
		else RandomNumberGenerator.new()
	)

	var interval: float = rng.randf_range(min_spawn_interval, max_spawn_interval)
	_spawn_timer.start(interval)


## Instantiates one enemy unit at an available spawn point.
func _on_spawn_timer_timeout() -> void:
	if not _is_running or _remaining_to_spawn <= 0:
		return

	if not is_instance_valid(enemy_scene):
		push_error("WaveSpawner: [", name, "] enemy_scene is not assigned.")
		return

	var spawn_pos: Vector3 = global_position
	if not spawn_points.is_empty():
		var valid_points: Array[Node3D] = []
		for pt: Node3D in spawn_points:
			if is_instance_valid(pt):
				valid_points.append(pt)
		if not valid_points.is_empty():
			var global_node: Node = get_node_or_null("/root/Global")
			var rng: RandomNumberGenerator = (
				global_node.get("rng") as RandomNumberGenerator
				if is_instance_valid(global_node) and "rng" in global_node
				else RandomNumberGenerator.new()
			)
			var selected_pt: Node3D = valid_points[rng.randi() % valid_points.size()]
			spawn_pos = selected_pt.global_position

	var enemy_instance: Node = enemy_scene.instantiate()
	var enemy_node: Node3D = enemy_instance as Node3D
	if not is_instance_valid(enemy_node):
		push_error("WaveSpawner: [", name, "] instantiated enemy is not Node3D.")
		enemy_instance.queue_free()
		return

	var current_scene: Node = get_tree().current_scene
	if is_instance_valid(current_scene):
		current_scene.add_child(enemy_node)
	else:
		get_tree().root.add_child(enemy_node)

	enemy_node.global_position = spawn_pos
	_alive_enemies.append(enemy_node)
	_remaining_to_spawn -= 1

	var faction_comp: Node = FactionComponent.get_faction_component(enemy_node)
	if is_instance_valid(faction_comp) and faction_comp.has_method("set_faction"):
		faction_comp.call("set_faction", Types.Faction.ENEMY)

	print("WaveSpawner: [", name, "] spawned enemy at ", spawn_pos, ". Left: ", _remaining_to_spawn)

	if is_instance_valid(Events) and Events.has_signal("enemy_spawned"):
		Events.enemy_spawned.emit(enemy_node)

	if _remaining_to_spawn > 0:
		_schedule_next_spawn()


## Tracks enemy deaths and completes wave when living count hits zero.
func _on_enemy_killed(enemy_node: Node3D, killer_node: Node3D) -> void:
	var killer_name: String = killer_node.name if is_instance_valid(killer_node) else "unknown"
	var enemy_name: String = enemy_node.name if is_instance_valid(enemy_node) else "unknown"
	print("WaveSpawner: [", name, "] enemy ", enemy_name, " slain by ", killer_name)

	var idx: int = _alive_enemies.find(enemy_node)
	if idx != -1:
		_alive_enemies.remove_at(idx)

	if _remaining_to_spawn <= 0 and _alive_enemies.is_empty() and _is_running:
		print("WaveSpawner: [", name, "] wave ", current_wave, " completed!")
		if is_instance_valid(Events) and Events.has_signal("wave_completed"):
			Events.wave_completed.emit(current_wave)
		Utilities.delay_call(self, 2.0, start_next_wave)
