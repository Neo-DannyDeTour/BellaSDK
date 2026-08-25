## A manager that handles background streaming and unloading of world chunks.
##
## [ChunkManager] uses distance-based proximity and explicit area triggers to dynamically
## load and unload [PackedScene] chunks asynchronously. This keeps memory usage low and
## performance high by only processing visible or active segments of the world.
class_name ChunkManager
extends Node3D

## Reference to the player node used to calculate spatial distances for proximity-based chunk
## loading.
@export var player: Node3D

## The maximum distance in meters before a chunk is considered out of range and gets queued for
## unloading.
@export var load_distance: float = 150.0

## A dictionary mapping a unique chunk ID [String] to its corresponding scene file path [String]
## on disk.
@export var chunk_registry: Dictionary = {}

## A dictionary mapping a unique chunk ID [String] to its central [Vector3] world position for
## distance checks.
@export var chunk_positions: Dictionary = {}

## A dictionary storing the active chunk IDs as keys and their instantiated [Node3D] references as
## values.
var loaded_chunks: Dictionary = {}

## A dictionary tracking chunks that are currently in the background loading queue to prevent
## duplicate requests.
var loading_chunks: Dictionary = {}

## An array of chunk IDs that have been explicitly requested by trigger areas, bypassing distance
## checks.
var trigger_active_chunks: Array[String] = []


## Called when the node enters the scene tree for the first time.
## Sets up a repeating timer to periodically check chunk distances and loading states.
func _ready() -> void:
	var check_timer: Timer = Timer.new()
	check_timer.wait_time = 0.5
	check_timer.timeout.connect(_on_check_chunks)
	add_child(check_timer)
	check_timer.start()


## Called when a player enters an [Area3D] trigger to forcefully load a specific chunk.
## [param chunk_id] The string identifier of the chunk to load.
func trigger_load_chunk(chunk_id: String) -> void:
	print("ChunkManager: trigger_load_chunk() called for chunk ID: ", chunk_id)
	if not trigger_active_chunks.has(chunk_id):
		trigger_active_chunks.append(chunk_id)


## Called when a player exits an [Area3D] trigger to release the forced load state of a chunk.
## [param chunk_id] The string identifier of the chunk to unload.
func trigger_unload_chunk(chunk_id: String) -> void:
	print("ChunkManager: trigger_unload_chunk() called for chunk ID: ", chunk_id)
	if trigger_active_chunks.has(chunk_id):
		trigger_active_chunks.erase(chunk_id)


## Called periodically by the internal timer.
## Calculates which chunks should be active based on explicit triggers and player proximity.
func _on_check_chunks() -> void:
	print("ChunkManager: _on_check_chunks() executed. Evaluating chunk distances and triggers.")
	if not is_instance_valid(player):
		return

	var desired_chunks: Array[String] = []

	# 1. Add chunks requested by triggers
	for chunk_id: String in trigger_active_chunks:
		desired_chunks.append(chunk_id)

	# 2. Add chunks based on distance
	var player_pos: Vector3 = player.global_position
	for chunk_id: String in chunk_positions:
		var chunk_pos: Vector3 = chunk_positions[chunk_id]
		if player_pos.distance_squared_to(chunk_pos) <= load_distance * load_distance:
			if not desired_chunks.has(chunk_id):
				desired_chunks.append(chunk_id)

	_process_chunk_queues(desired_chunks)


## Unloads stale chunks, requests new loads, and processes background loading threads.
## [param desired_chunks] An array of chunk IDs that are requested to be active this cycle.
func _process_chunk_queues(desired_chunks: Array[String]) -> void:
	print("ChunkManager: _process_chunk_queues() executed. Managing memory and threads.")

	# Unload chunks that are no longer desired
	var chunks_to_remove: Array[String] = []
	for loaded_id: String in loaded_chunks:
		if not desired_chunks.has(loaded_id):
			_unload_chunk(loaded_id)
			chunks_to_remove.append(loaded_id)

	for id: String in chunks_to_remove:
		loaded_chunks.erase(id)

	# Request loads for desired chunks that aren't loaded or loading
	for desired_id: String in desired_chunks:
		if not loaded_chunks.has(desired_id) and not loading_chunks.has(desired_id):
			_request_async_load(desired_id)

	# Check progress of currently loading chunks
	var finished_loads: Array[String] = []
	for loading_id: String in loading_chunks:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			chunk_registry[loading_id]
		)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_instantiate_chunk(loading_id)
			finished_loads.append(loading_id)
		elif (
			status == ResourceLoader.THREAD_LOAD_FAILED
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		):
			print("ChunkManager: Error loading chunk ID: ", loading_id)
			finished_loads.append(loading_id)

	for id: String in finished_loads:
		loading_chunks.erase(id)


## Requests the [ResourceLoader] to load a chunk scene asynchronously in the background.
## [param chunk_id] The string identifier of the chunk to begin loading.
func _request_async_load(chunk_id: String) -> void:
	print("ChunkManager: _request_async_load() called. Pushing to background thread: ", chunk_id)
	if chunk_registry.has(chunk_id):
		loading_chunks[chunk_id] = true
		ResourceLoader.load_threaded_request(chunk_registry[chunk_id])


## Safely grabs a fully loaded [PackedScene] from the background thread and spawns it.
## [param chunk_id] The string identifier of the successfully loaded chunk.
func _instantiate_chunk(chunk_id: String) -> void:
	print("ChunkManager: _instantiate_chunk() called. Spawning into world: ", chunk_id)
	var chunk_resource: PackedScene = ResourceLoader.load_threaded_get(chunk_registry[chunk_id])
	if chunk_resource:
		var instance: Node3D = chunk_resource.instantiate()
		loaded_chunks[chunk_id] = instance
		call_deferred("add_child", instance)


## Removes and frees an active chunk instance from the scene tree.
## [param chunk_id] The string identifier of the chunk to destroy.
func _unload_chunk(chunk_id: String) -> void:
	print("ChunkManager: _unload_chunk() called. Freeing memory for: ", chunk_id)
	var chunk_instance: Node3D = loaded_chunks[chunk_id]
	if is_instance_valid(chunk_instance):
		chunk_instance.queue_free()
