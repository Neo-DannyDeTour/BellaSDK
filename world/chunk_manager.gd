class_name ChunkManager
extends Node3D
## Streams 50x50m world chunks around the player using synchronous 3x3 near-ring
## loading, throttled threaded I/O, main-thread frame-budgeted instantiation,
## and roaming entity management without unloading.

## State tracking enum for chunk lifecycle transitions.
enum ChunkState {
	QUEUED,
	LOADING,
	READY_TO_ATTACH,
	ACTIVE,
}

## World-space width and depth of a single chunk in meters.
const CHUNK_SIZE: float = 50.0

## Minimum chunk grid coordinate along X and Z axes (-2500m).
const GRID_MIN: int = -50

## Maximum chunk grid coordinate along X and Z axes (+2500m).
const GRID_MAX: int = 50

## Integer grid radius scanned when scheduling new chunk loads (600m).
const LOAD_RADIUS: int = 12

## Squared grid distance threshold for synchronous loading (3x3 around player).
const IMMEDIATE_RADIUS_SQ: float = 2.0

## Squared grid distance threshold for background loading (12 chunks / 600m).
const LOAD_RADIUS_SQ: float = 144.0

## Maximum concurrent [ResourceLoader] threaded requests in flight.
const MAX_CONCURRENT_IO: int = 4

## Maximum chunks instantiated and attached to the scene tree per frame.
const MAX_ATTACHES_PER_FRAME: int = 2

## Polling interval in seconds for active [ResourceLoader] threaded requests.
const IO_POLL_INTERVAL: float = 0.05

## Binary file name format string for chunk scenes indexed by X and Z grid coordinates.
const CHUNK_SCN_FMT: String = "chunk_%d_%d.scn"

## Text file name format string fallback for chunk scenes indexed by X and Z coordinates.
const CHUNK_TSCN_FMT: String = "chunk_%d_%d.tscn"

## Resource type hint passed to [method ResourceLoader.load_threaded_request].
const TYPE_HINT_SCENE: String = "PackedScene"

## Sentinel payload indicating an entity was destroyed or suppressed as a duplicate.
const DELTA_FREED: StringName = &"freed"

## Scene group identifying entities that persist across chunk boundaries.
const GROUP_ROAMING: StringName = &"roaming"

## Metadata key storing a roaming entity's original spawn chunk coordinate.
const META_ORIGIN_CHUNK: StringName = &"origin_chunk"

## Metadata key preserving an entity's original scene-unique name across reparenting.
const META_ENTITY_ID: StringName = &"entity_id"

## Optional method invoked on chunk root nodes during setup to apply saved deltas.
const METHOD_APPLY_DELTAS: StringName = &"apply_chunk_deltas"

## Physics collision mask matching Layer 3 (Interactive) and Layer 5 (Enemies).
const ROAMING_LAYER_MASK: int = CollisionLayers.MASK_INTERACTIVE | CollisionLayers.MASK_ENEMIES

## Directory path containing streaming chunk scenes.
@export var chunk_dir: String = "res://world/chunks/"

## Scene container hosting extracted roaming entities.
@export var dynamic_container: Node3D

## Active and transitioning state per chunk grid coordinate.
var _chunk_states: Dictionary[Vector2i, ChunkState] = {}

## Live active scene instances keyed by chunk coordinate.
var _active_nodes: Dictionary[Vector2i, Node3D] = {}

## Registered living roamers mapped by origin chunk and entity ID.
var _active_roamers: Dictionary[Vector2i, Dictionary] = {}

## Nearest-first sorted queue of chunk coordinates waiting for threaded I/O.
var _pending_io: Array[Vector2i] = []

## In-flight [ResourceLoader] scene paths keyed by chunk coordinate.
var _in_flight_loads: Dictionary[Vector2i, String] = {}

## Loaded chunk [PackedScene]s queued for main-thread instantiation and attachment.
var _ready_to_attach: Dictionary[Vector2i, PackedScene] = {}

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


## Instantiates and attaches up to [constant MAX_ATTACHES_PER_FRAME] loaded chunks.
func _process(_delta: float) -> void:
	var attached: int = 0
	while attached < MAX_ATTACHES_PER_FRAME and not _ready_to_attach.is_empty():
		var coords: Array[Vector2i] = _ready_to_attach.keys()
		var coord: Vector2i = coords[0]
		var packed: PackedScene = _ready_to_attach[coord]
		_ready_to_attach.erase(coord)
		if _instantiate_and_attach(coord, packed):
			attached += 1
	if _ready_to_attach.is_empty():
		set_process(false)


## Disconnects signals and clears pending queues on exit.
func _exit_tree() -> void:
	if Events.player_chunk_changed.is_connected(_on_player_chunk_changed):
		Events.player_chunk_changed.disconnect(_on_player_chunk_changed)
	if Events.chunk_entity_mutated.is_connected(record_delta):
		Events.chunk_entity_mutated.disconnect(record_delta)
	if is_instance_valid(_io_timer) and _io_timer.timeout.is_connected(_on_io_timer_timeout):
		_io_timer.timeout.disconnect(_on_io_timer_timeout)
	_pending_io.clear()
	_in_flight_loads.clear()
	_ready_to_attach.clear()


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


## Loads near-ring chunks immediately and queues remaining chunks nearest-first.
func _on_player_chunk_changed(player_coord: Vector2i) -> void:
	var player_vec: Vector2 = Vector2(player_coord)
	var min_x: int = maxi(GRID_MIN, player_coord.x - LOAD_RADIUS)
	var max_x: int = mini(GRID_MAX, player_coord.x + LOAD_RADIUS)
	var min_y: int = maxi(GRID_MIN, player_coord.y - LOAD_RADIUS)
	var max_y: int = mini(GRID_MAX, player_coord.y + LOAD_RADIUS)

	var load_candidates: Array[Vector2i] = []
	for x: int in range(min_x, max_x + 1):
		for y: int in range(min_y, max_y + 1):
			var coord: Vector2i = Vector2i(x, y)
			var dist_sq: float = Vector2(coord).distance_squared_to(player_vec)
			if dist_sq <= LOAD_RADIUS_SQ:
				load_candidates.append(coord)

	load_candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var da: float = Vector2(a).distance_squared_to(player_vec)
			var db: float = Vector2(b).distance_squared_to(player_vec)
			return da < db
	)

	for coord: Vector2i in load_candidates:
		var dist_sq: float = Vector2(coord).distance_squared_to(player_vec)
		if dist_sq <= IMMEDIATE_RADIUS_SQ:
			_load_chunk_immediate(coord)
		else:
			_enqueue_chunk_load(coord)

	_pump_io_queue()


## Resolves the chunk scene path for [param coord], preferring binary `.scn` over `.tscn`.
func _get_chunk_path(coord: Vector2i) -> String:
	var dir: String = chunk_dir if chunk_dir.ends_with("/") else chunk_dir + "/"
	var scn_path: String = dir + (CHUNK_SCN_FMT % [coord.x, coord.y])
	if ResourceLoader.exists(scn_path):
		return scn_path
	var tscn_path: String = dir + (CHUNK_TSCN_FMT % [coord.x, coord.y])
	if ResourceLoader.exists(tscn_path):
		return tscn_path
	return ""


## Synchronously loads, instantiates, and attaches a near-ring chunk at [param coord].
func _load_chunk_immediate(coord: Vector2i) -> void:
	if _missing_coords.has(coord):
		return
	if _chunk_states.has(coord):
		var state: ChunkState = _chunk_states[coord]
		if state == ChunkState.ACTIVE:
			return
		if state == ChunkState.READY_TO_ATTACH and _ready_to_attach.has(coord):
			var queued_packed: PackedScene = _ready_to_attach[coord]
			_ready_to_attach.erase(coord)
			_instantiate_and_attach(coord, queued_packed)
		return

	var path: String = _get_chunk_path(coord)
	if path.is_empty():
		_missing_coords[coord] = true
		return

	var res: Resource = ResourceLoader.load(path, TYPE_HINT_SCENE)
	var packed: PackedScene = res as PackedScene
	if packed == null:
		return

	_instantiate_and_attach(coord, packed)


## Appends [param coord] to the throttled background I/O queue if not already tracked.
func _enqueue_chunk_load(coord: Vector2i) -> void:
	if _missing_coords.has(coord) or _chunk_states.has(coord):
		return
	var path: String = _get_chunk_path(coord)
	if path.is_empty():
		_missing_coords[coord] = true
		return
	_chunk_states[coord] = ChunkState.QUEUED
	_pending_io.append(coord)


## Fills open [constant MAX_CONCURRENT_IO] slots from [member _pending_io].
func _pump_io_queue() -> void:
	while _in_flight_loads.size() < MAX_CONCURRENT_IO and not _pending_io.is_empty():
		var coord: Vector2i = _pending_io.pop_front() as Vector2i
		if not _chunk_states.has(coord) or _chunk_states[coord] != ChunkState.QUEUED:
			continue
		var path: String = _get_chunk_path(coord)
		if path.is_empty():
			_missing_coords[coord] = true
			_chunk_states.erase(coord)
			continue
		var err: Error = ResourceLoader.load_threaded_request(path, TYPE_HINT_SCENE)
		if err != OK:
			_chunk_states.erase(coord)
			continue
		_chunk_states[coord] = ChunkState.LOADING
		_in_flight_loads[coord] = path
		print("Chunk load requested: ", coord)

	if not _in_flight_loads.is_empty() and _io_timer.is_stopped():
		_io_timer.start()


## Polls [ResourceLoader] status for in-flight chunks and pumps the next queued loads.
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
			if packed == null:
				_chunk_states.erase(coord)
				continue
			_chunk_states[coord] = ChunkState.READY_TO_ATTACH
			_ready_to_attach[coord] = packed
			set_process(true)
		elif (
			status == ResourceLoader.THREAD_LOAD_FAILED
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		):
			_in_flight_loads.erase(coord)
			_chunk_states.erase(coord)
			print("Chunk I/O load failed: ", coord)

	_pump_io_queue()
	if _in_flight_loads.is_empty() and _pending_io.is_empty():
		_io_timer.stop()


## Instantiates [param packed] on the main thread, applies deltas, and attaches it.
func _instantiate_and_attach(coord: Vector2i, packed: PackedScene) -> bool:
	if not is_instance_valid(packed):
		_chunk_states.erase(coord)
		return false
	var deltas_snapshot: Dictionary = _build_deltas_snapshot(coord)
	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		_chunk_states.erase(coord)
		return false
	instance.position = Vector3(float(coord.x) * CHUNK_SIZE, 0.0, float(coord.y) * CHUNK_SIZE)
	if not deltas_snapshot.is_empty() and instance.has_method(METHOD_APPLY_DELTAS):
		instance.call(METHOD_APPLY_DELTAS, deltas_snapshot)
	_attach_chunk(coord, instance)
	return true


## Builds a delta snapshot with active roamer deduplication for [param coord].
func _build_deltas_snapshot(coord: Vector2i) -> Dictionary:
	var deltas_snapshot: Dictionary = {}
	if _chunk_deltas.has(coord):
		deltas_snapshot = _chunk_deltas[coord].duplicate()
	if _active_roamers.has(coord):
		var roamer_map: Dictionary = _active_roamers[coord]
		for entity_id: StringName in roamer_map.keys():
			var roamer: Node3D = roamer_map[entity_id] as Node3D
			if is_instance_valid(roamer):
				deltas_snapshot[entity_id] = DELTA_FREED
	return deltas_snapshot


## Attaches [param instance] to the scene tree, extracts roamers, and marks it active.
func _attach_chunk(coord: Vector2i, instance: Node3D) -> void:
	add_child(instance)
	_extract_roaming_entities(coord, instance)
	_active_nodes[coord] = instance
	_chunk_states[coord] = ChunkState.ACTIVE
	print("Chunk active: ", coord)


## Recursively registers and reparents roaming [CollisionObject3D] nodes under [param parent].
func _extract_roaming_entities(coord: Vector2i, parent: Node) -> void:
	var children: Array[Node] = parent.get_children()
	for child: Node in children:
		var col_obj: CollisionObject3D = child as CollisionObject3D
		if (
			child.is_in_group(GROUP_ROAMING)
			and col_obj != null
			and (col_obj.collision_layer & ROAMING_LAYER_MASK) != 0
		):
			_register_and_reparent_roamer(coord, col_obj)
		else:
			_extract_roaming_entities(coord, child)


## Stamps roaming metadata, registers [param col_obj], and reparents to dynamic container.
func _register_and_reparent_roamer(coord: Vector2i, col_obj: CollisionObject3D) -> void:
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
