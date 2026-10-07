## Streams world chunk sub-scenes asynchronously based on player proximity.
class_name WorldChunkManager
extends Node3D

## Emitted when the initial spawn chunk has loaded and mounted to the tree.
signal initial_zone_ready

## Emitted when a chunk scene finishes instantiating at [param cell_coord].
signal chunk_loaded(cell_coord: Vector2i)

## Emitted when a chunk scene is unloaded at [param cell_coord].
signal chunk_unloaded(cell_coord: Vector2i)

## Grid cell dimension in meters along the horizontal X and Z plane.
const CELL_SIZE: float = 40.0

## Folder path where binary chunk sub-scenes are located.
@export_dir var chunks_folder_path: String = "res://levels/chunks"

## Distance in meters around the player to keep chunks loaded.
@export var stream_radius: float = 80.0

## Reference to the player node used to evaluate coordinates.
@export var player: Node3D

## Dictionary of currently mounted chunk instances mapped by [Vector2i].
var loaded_chunks: Dictionary = {}

## Dictionary of chunk coordinates currently loading in background threads.
var loading_chunks: Dictionary = {}

## Tracks whether the player spawn area has initialized.
var _is_spawn_ready: bool = false


## Evaluates the initial player position and forces loading the spawn chunk.
func _ready() -> void:
	print("WorldChunkManager: Initializing streaming grid.")
	if is_instance_valid(player):
		var spawn_cell: Vector2i = _world_to_cell(player.global_position)
		_request_chunk(spawn_cell, true)


## Evaluates player proximity every frame and updates active chunk requests.
func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return

	_poll_threaded_loads()
	_update_stream_bounds()


## Polls pending background resource loads and instantiates finished chunks.
func _poll_threaded_loads() -> void:
	var completed_coords: Array[Vector2i] = []

	for cell_coord: Vector2i in loading_chunks:
		var path: String = loading_chunks[cell_coord]
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)

		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var scene: PackedScene = (
				ResourceLoader.load_threaded_get(path)
				if ResourceLoader.load_threaded_get(path) is PackedScene
				else null
			)
			_mount_chunk(cell_coord, scene)
			completed_coords.append(cell_coord)
		elif (
			status == ResourceLoader.THREAD_LOAD_FAILED
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		):
			push_error("WorldChunkManager: Failed loading chunk at: " + path)
			completed_coords.append(cell_coord)

	for finished_coord: Vector2i in completed_coords:
		loading_chunks.erase(finished_coord)


## Mounts an instantiated chunk scene and notifies listeners.
func _mount_chunk(cell_coord: Vector2i, scene: PackedScene) -> void:
	print("WorldChunkManager: Mounting chunk at cell: ", cell_coord)
	var instance: Node3D = scene.instantiate() if scene.instantiate() is Node3D else null
	add_child(instance)
	loaded_chunks[cell_coord] = instance
	chunk_loaded.emit(cell_coord)

	if not _is_spawn_ready:
		_is_spawn_ready = true
		initial_zone_ready.emit()


## Requests background loading for a chunk file if it exists on disk.
func _request_chunk(cell_coord: Vector2i, is_blocking: bool = false) -> void:
	if loaded_chunks.has(cell_coord) or loading_chunks.has(cell_coord):
		return

	var file_path: String = chunks_folder_path + "/chunk_%d_%d.scn" % [cell_coord.x, cell_coord.y]
	if not ResourceLoader.exists(file_path):
		return

	print("WorldChunkManager: Requesting chunk load: ", file_path)
	if is_blocking:
		var scene: PackedScene = (
			ResourceLoader.load(file_path)
			if ResourceLoader.load(file_path) is PackedScene
			else null
		)
		if is_instance_valid(scene):
			_mount_chunk(cell_coord, scene)
	else:
		loading_chunks[cell_coord] = file_path
		ResourceLoader.load_threaded_request(file_path, "", false)


## Unloads distant chunks outside the streaming perimeter to save memory.
func _unload_chunk(cell_coord: Vector2i) -> void:
	print("WorldChunkManager: Evicting distant chunk: ", cell_coord)
	if loaded_chunks.has(cell_coord):
		var chunk_node: Node3D = (
			loaded_chunks[cell_coord] if loaded_chunks[cell_coord] is Node3D else null
		)
		if is_instance_valid(chunk_node):
			chunk_node.queue_free()
		loaded_chunks.erase(cell_coord)
		chunk_unloaded.emit(cell_coord)


## Checks player position and schedules chunk loading or eviction.
func _update_stream_bounds() -> void:
	var player_pos: Vector3 = player.global_position
	var center_cell: Vector2i = _world_to_cell(player_pos)
	var radius_cells: int = int(ceil(stream_radius / CELL_SIZE))
	var desired_cells: Dictionary = {}

	for x: int in range(center_cell.x - radius_cells, center_cell.x + radius_cells + 1):
		for z: int in range(center_cell.y - radius_cells, center_cell.y + radius_cells + 1):
			var check_coord: Vector2i = Vector2i(x, z)
			var cell_pos: Vector2 = Vector2(
				(float(x) + 0.5) * CELL_SIZE, (float(z) + 0.5) * CELL_SIZE
			)
			var p_pos_2d: Vector2 = Vector2(player_pos.x, player_pos.z)
			if p_pos_2d.distance_to(cell_pos) <= stream_radius:
				desired_cells[check_coord] = true
				_request_chunk(check_coord, false)

	var to_evict: Array[Vector2i] = []
	for loaded_coord: Vector2i in loaded_chunks:
		if not desired_cells.has(loaded_coord):
			to_evict.append(loaded_coord)

	for dead_coord: Vector2i in to_evict:
		_unload_chunk(dead_coord)


## Converts a global 3D vector to a 2D horizontal chunk coordinate.
func _world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL_SIZE)), int(floor(pos.z / CELL_SIZE)))
