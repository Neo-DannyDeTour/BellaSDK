class_name ChunkManager
extends Node3D
## Streams 250x250m world chunks around the player using threaded I/O,
## [WorkerThreadPool] instantiation, hysteresis radii, and roaming lifecycle management.

## State tracking enum for chunk lifecycle transitions.
enum ChunkState {
	LOADING,
	INSTANTIATING,
	ACTIVE,
	ABORTED,
}

## World-space width and depth of a single chunk in meters.
const CHUNK_SIZE: float = 250.0

## Minimum chunk grid coordinate along X and Z axes (-2500m).
const GRID_MIN: int = -10

## Maximum chunk grid coordinate along X and Z axes (+2500m).
const GRID_MAX: int = 9

## Integer grid radius scanned when scheduling new chunk loads.
const LOAD_RADIUS: int = 3

## Squared grid distance threshold for loading chunks (3 chunks / 750m).
const LOAD_RADIUS_SQ: float = 9.0

## Squared grid distance threshold for unloading chunks (4 chunks / 1000m).
const UNLOAD_RADIUS_SQ: float = 16.0

## Polling interval in seconds for active [ResourceLoader] threaded requests.
const IO_POLL_INTERVAL: float = 0.05

## File path format string for chunk scenes indexed by X and Z grid coordinates.
const CHUNK_PATH_FMT: String = "res://world/chunks/chunk_%d_%d.tscn"

## Resource type hint passed to [method ResourceLoader.load_threaded_request].
const TYPE_HINT_SCENE: String = "PackedScene"

## Sentinel payload indicating an entity was destroyed or suppressed as a duplicate.
const DELTA_FREED: StringName = &"freed"

## Scene group identifying entities that persist across chunk unloads.
const GROUP_ROAMING: StringName = &"roaming"

## Metadata key storing a roaming entity's original spawn chunk coordinate.
const META_ORIGIN_CHUNK: StringName = &"origin_chunk"

## Metadata key preserving an entity's original scene-unique name across reparenting.
const META_ENTITY_ID: StringName = &"entity_id"

## Optional method invoked on chunk root nodes during worker-thread setup.
const METHOD_APPLY_DELTAS: StringName = &"apply_chunk_deltas"

## Optional method invoked on roaming entities to serialize custom state before despawn.
const METHOD_CAPTURE_DELTA: StringName = &"capture_delta"

## Deferred callback method name invoked when worker instantiation completes.
const METHOD_FINALIZE: StringName = &"_on_worker_instantiated"

## Physics collision mask matching Layer 3 (Interactive) and Layer 5 (Enemies).
const ROAMING_LAYER_MASK: int = CollisionLayers.MASK_INTERACTIVE | CollisionLayers.MASK_ENEMIES

## Scene container hosting extracted roaming entities across chunk unloads.
@export var dynamic_container: Node3D

## Active and transitioning state per chunk grid coordinate.
var _chunk_states: Dictionary[Vector2i, ChunkState] = {}

## Live active scene instances keyed by chunk coordinate.
var _active_nodes: Dictionary[Vector2i, Node3D] = {}

## Registered living roamers mapped by origin chunk and entity ID.
var _active_roamers: Dictionary[Vector2i, Dictionary] = {}

## In-flight [ResourceLoader] scene paths keyed by chunk coordinate.
var _in_flight_loads: Dictionary[Vector2i, String] = {}

## Pending background worker thread task IDs keyed by chunk coordinate.
var _worker_tasks: Dictionary[Vector2i, int] = {}

## Persisted state deltas mapped by origin chunk and entity ID.
var _chunk_deltas: Dictionary[Vector2i, Dictionary] = {}

## Missing chunk files skipped from redundant load attempts.
var _missing_coords: Dictionary[Vector2i, bool] = {}

## Timer driving I/O status checks for background scene loading.
@onready var _io_timer: Timer = $IOTimer as Timer


## Validates required nodes, disables frame loops, and binds signals.
func _ready() -> void:
	assert(dynamic_container != null, "ChunkManager requires dynamic_container assigned.")
	assert(_io_timer != null, "ChunkManager requires an IOTimer child node.")
	set_process(false)
	set_physics_process(false)
	_io_timer.wait_time = IO_POLL_INTERVAL
	_io_timer.one_shot = false
	Utilities.safe_connect(_io_timer.timeout, _on_io_timer_timeout)
	Utilities.safe_connect(Events.player_chunk_changed, _on_player_chunk_changed)
	Utilities.safe_connect(Events.chunk_entity_mutated, record_delta)


## Disconnects signals and awaits pending worker tasks before tree exit.
func _exit_tree() -> void:
	if Events.player_chunk_changed.is_connected(_on_player_chunk_changed):
		Events.player_chunk_changed.disconnect(_on_player_chunk_changed)
	if Events.chunk_entity_mutated.is_connected(record_delta):
		Events.chunk_entity_mutated.disconnect(record_delta)
	if is_instance_valid(_io_timer) and _io_timer.timeout.is_connected(_on_io_timer_timeout):
		_io_timer.timeout.disconnect(_on_io_timer_timeout)
	for task_id: int in _worker_tasks.values():
		WorkerThreadPool.wait_for_task_completion(task_id)
	_worker_tasks.clear()


## Records a state mutation for [param entity_id] inside chunk [param coord].
func record_delta(coord: Vector2i, entity_id: StringName, data: Variant) -> void:
	if not _chunk_deltas.has(coord):
		var new_map: Dictionary[StringName, Variant] = {}
		_chunk_deltas[coord] = new_map
	var chunk_map: Dictionary = _chunk_deltas[coord]
	chunk_map[entity_id] = data

	if data is StringName and data == DELTA_FREED and _active_roamers.has(coord):
		var roamer_map: Dictionary = _active_roamers[coord]
		roamer_map.erase(entity_id)
		if roamer_map.is_empty():
			_active_roamers.erase(coord)

	print("Chunk delta recorded: ", coord, " -> ", entity_id)


## Returns true if chunk [param coord] is currently in [constant ChunkState.ACTIVE].
func is_chunk_active(coord: Vector2i) -> bool:
	return _chunk_states.has(coord) and _chunk_states[coord] == ChunkState.ACTIVE


## Returns true if chunk [param coord] has one or more recorded entity deltas.
func has_chunk_delta(coord: Vector2i) -> bool:
	return _chunk_deltas.has(coord) and not _chunk_deltas[coord].is_empty()


## Evaluates hysteresis radii around [param player_coord] to unload, cull, and load.
func _on_player_chunk_changed(player_coord: Vector2i) -> void:
	var player_vec: Vector2 = Vector2(player_coord)
	var tracked_coords: Array[Vector2i] = _chunk_states.keys()
	for coord: Vector2i in tracked_coords:
		var dist_sq: float = Vector2(coord).distance_squared_to(player_vec)
		if dist_sq > UNLOAD_RADIUS_SQ:
			_unload_chunk(coord)

	_cull_distant_roamers(player_vec)

	var min_x: int = maxi(GRID_MIN, player_coord.x - LOAD_RADIUS)
	var max_x: int = mini(GRID_MAX, player_coord.x + LOAD_RADIUS)
	var min_y: int = maxi(GRID_MIN, player_coord.y - LOAD_RADIUS)
	var max_y: int = mini(GRID_MAX, player_coord.y + LOAD_RADIUS)

	for x: int in range(min_x, max_x + 1):
		for y: int in range(min_y, max_y + 1):
			var coord: Vector2i = Vector2i(x, y)
			var dist_sq: float = Vector2(coord).distance_squared_to(player_vec)
			if dist_sq <= LOAD_RADIUS_SQ:
				_request_chunk_load(coord)


## Despawns roaming entities exceeding [constant UNLOAD_RADIUS_SQ] when origin is inactive.
func _cull_distant_roamers(player_vec: Vector2) -> void:
	var origin_coords: Array[Vector2i] = _active_roamers.keys()
	for origin_coord: Vector2i in origin_coords:
		var roamer_map: Dictionary = _active_roamers[origin_coord]
		var origin_active: bool = (
			_chunk_states.has(origin_coord) and _chunk_states[origin_coord] == ChunkState.ACTIVE
		)
		var entity_ids: Array = roamer_map.keys()
		for entity_id: StringName in entity_ids:
			var roamer: Node3D = roamer_map[entity_id] as Node3D
			if not is_instance_valid(roamer):
				roamer_map.erase(entity_id)
				continue
			var pos: Vector3 = roamer.global_position
			var roamer_coord: Vector2i = Vector2i(
				floori(pos.x / CHUNK_SIZE), floori(pos.z / CHUNK_SIZE)
			)
			var dist_sq: float = Vector2(roamer_coord).distance_squared_to(player_vec)
			if dist_sq > UNLOAD_RADIUS_SQ and not origin_active:
				_capture_and_despawn_roamer(origin_coord, entity_id, roamer)
				roamer_map.erase(entity_id)
		if roamer_map.is_empty():
			_active_roamers.erase(origin_coord)


## Captures state or local [Transform3D] for [param roamer] and queues its removal.
func _capture_and_despawn_roamer(
	origin_coord: Vector2i, entity_id: StringName, roamer: Node3D
) -> void:
	if roamer.has_method(METHOD_CAPTURE_DELTA):
		var custom_delta: Variant = roamer.call(METHOD_CAPTURE_DELTA)
		record_delta(origin_coord, entity_id, custom_delta)
	else:
		var local_xform: Transform3D = roamer.global_transform
		local_xform.origin -= Vector3(
			float(origin_coord.x) * CHUNK_SIZE, 0.0, float(origin_coord.y) * CHUNK_SIZE
		)
		record_delta(origin_coord, entity_id, local_xform)
	roamer.queue_free()
	print("Roaming entity despawned: ", entity_id, " from ", origin_coord)


## Initiates threaded loading for [param coord] or revives an aborted in-flight load.
func _request_chunk_load(coord: Vector2i) -> void:
	if _missing_coords.has(coord):
		return
	if _chunk_states.has(coord):
		if _chunk_states[coord] == ChunkState.ABORTED:
			# Restore previous pipeline stage when player re-enters before abort resolves.
			if _in_flight_loads.has(coord):
				_chunk_states[coord] = ChunkState.LOADING
			else:
				_chunk_states[coord] = ChunkState.INSTANTIATING
			print("Chunk abort canceled: ", coord)
		return

	var path: String = CHUNK_PATH_FMT % [coord.x, coord.y]
	if not ResourceLoader.exists(path):
		_missing_coords[coord] = true
		return

	var err: Error = ResourceLoader.load_threaded_request(path, TYPE_HINT_SCENE)
	if err != OK:
		return

	_chunk_states[coord] = ChunkState.LOADING
	_in_flight_loads[coord] = path
	print("Chunk load requested: ", coord)
	if _io_timer.is_stopped():
		_io_timer.start()


## Queues active chunk removal or marks in-flight loads as [constant ChunkState.ABORTED].
func _unload_chunk(coord: Vector2i) -> void:
	if not _chunk_states.has(coord):
		return
	var state: ChunkState = _chunk_states[coord]
	if state == ChunkState.ACTIVE:
		if _active_nodes.has(coord):
			var node: Node3D = _active_nodes[coord]
			if is_instance_valid(node):
				node.queue_free()
			_active_nodes.erase(coord)
		_chunk_states.erase(coord)
		print("Chunk unloaded: ", coord)
	elif state == ChunkState.LOADING or state == ChunkState.INSTANTIATING:
		_chunk_states[coord] = ChunkState.ABORTED
		print("Chunk load aborted in-flight: ", coord)


## Polls [ResourceLoader] status for in-flight chunks and stops when queue empties.
func _on_io_timer_timeout() -> void:
	if _in_flight_loads.is_empty():
		_io_timer.stop()
		return

	var pending_coords: Array[Vector2i] = _in_flight_loads.keys()
	for coord: Vector2i in pending_coords:
		var path: String = _in_flight_loads[coord]
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_in_flight_loads.erase(coord)
			var res: Resource = ResourceLoader.load_threaded_get(path)
			var packed: PackedScene = res as PackedScene
			if not _chunk_states.has(coord) or _chunk_states[coord] == ChunkState.ABORTED:
				_chunk_states.erase(coord)
				continue
			if packed == null:
				_chunk_states.erase(coord)
				continue
			_start_worker_instantiation(coord, packed)
		elif (
			status == ResourceLoader.THREAD_LOAD_FAILED
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		):
			_in_flight_loads.erase(coord)
			_chunk_states.erase(coord)
			print("Chunk I/O load failed: ", coord)

	if _in_flight_loads.is_empty():
		_io_timer.stop()


## Dispatches off-thread scene instantiation with active roamer deduplication.
func _start_worker_instantiation(coord: Vector2i, packed: PackedScene) -> void:
	_chunk_states[coord] = ChunkState.INSTANTIATING
	var deltas_snapshot: Dictionary = {}
	if _chunk_deltas.has(coord):
		# Duplicate dictionary on main thread to avoid concurrent read/write in worker.
		deltas_snapshot = _chunk_deltas[coord].duplicate()
	if _active_roamers.has(coord):
		var roamer_map: Dictionary = _active_roamers[coord]
		for entity_id: StringName in roamer_map.keys():
			var roamer: Node3D = roamer_map[entity_id] as Node3D
			if is_instance_valid(roamer):
				# Suppress duplicate spawn while living instance exists in dynamic_container.
				deltas_snapshot[entity_id] = DELTA_FREED
	var task_callable: Callable = _instantiate_chunk_worker.bind(coord, packed, deltas_snapshot)
	var task_id: int = WorkerThreadPool.add_task(task_callable)
	_worker_tasks[coord] = task_id


## Instantiates chunk [PackedScene] and applies deltas on a worker thread.
func _instantiate_chunk_worker(coord: Vector2i, packed: PackedScene, deltas: Dictionary) -> void:
	var instance: Node3D = packed.instantiate() as Node3D
	instance.position = Vector3(float(coord.x) * CHUNK_SIZE, 0.0, float(coord.y) * CHUNK_SIZE)
	if not deltas.is_empty() and instance.has_method(METHOD_APPLY_DELTAS):
		instance.call(METHOD_APPLY_DELTAS, deltas)
	call_deferred(METHOD_FINALIZE, coord, instance)


## Finalizes worker task on main thread, freeing aborted chunks or attaching active ones.
func _on_worker_instantiated(coord: Vector2i, instance: Node3D) -> void:
	if _worker_tasks.has(coord):
		var task_id: int = _worker_tasks[coord]
		WorkerThreadPool.wait_for_task_completion(task_id)
		_worker_tasks.erase(coord)

	if not _chunk_states.has(coord) or _chunk_states[coord] == ChunkState.ABORTED:
		if is_instance_valid(instance):
			instance.free()
		_chunk_states.erase(coord)
		print("Aborted chunk freed after worker completion: ", coord)
		return

	# Attach chunk root first so reparented children preserve world transforms.
	add_child(instance)
	_extract_roaming_entities(coord, instance)
	_active_nodes[coord] = instance
	_chunk_states[coord] = ChunkState.ACTIVE
	print("Chunk active: ", coord)


## Registers and reparents top-level roaming [CollisionObject3D] nodes.
func _extract_roaming_entities(coord: Vector2i, chunk_root: Node3D) -> void:
	# shortcut: scans direct children of chunk root only, upgrade to recursive if nested.
	var children: Array[Node] = chunk_root.get_children()
	for child: Node in children:
		if not child.is_in_group(GROUP_ROAMING):
			continue
		var col_obj: CollisionObject3D = child as CollisionObject3D
		if col_obj == null or (col_obj.collision_layer & ROAMING_LAYER_MASK) == 0:
			continue
		var entity_id: StringName = col_obj.name
		if col_obj.has_meta(META_ENTITY_ID):
			var raw_id: Variant = col_obj.get_meta(META_ENTITY_ID)
			if raw_id is StringName:
				entity_id = raw_id
			elif raw_id is String:
				entity_id = StringName(raw_id)
		else:
			col_obj.set_meta(META_ENTITY_ID, entity_id)
		if not col_obj.has_meta(META_ORIGIN_CHUNK):
			col_obj.set_meta(META_ORIGIN_CHUNK, coord)
		if not _active_roamers.has(coord):
			var new_roamer_map: Dictionary[StringName, Node3D] = {}
			_active_roamers[coord] = new_roamer_map
		var roamer_map: Dictionary = _active_roamers[coord]
		roamer_map[entity_id] = col_obj
		Utilities.reparent_keep_transform(col_obj, dynamic_container, true)
