## Unit tests for the [WorldChunkManager] system.
##
## This suite verifies the behavior of the [WorldChunkManager] to ensure
## requests for loading and unloading chunk IDs operate correctly without duplicates.
class_name TestWorldChunkManager
extends GutTest

## The [WorldChunkManager] instance under test.
var manager: Node = null


## Instantiates [WorldChunkManager] and registers autofree cleanup before each test.
func before_each() -> void:
	print("TestWorldChunkManager: Executing before_each() setup.")
	manager = load("res://core/virtual_chunk_manager.gd").new() as Node
	add_child_autofree(manager)


## Verifies that forcing a chunk load adds it to the active list.
func test_request_chunk() -> void:
	print("TestWorldChunkManager: Executing test_request_chunk().")
	manager.call("_request_chunk", Vector2i(1, 1), false)
	var loading_chunks: Dictionary = manager.get("loading_chunks") as Dictionary
	assert_true(
		loading_chunks.has(Vector2i(1, 1)), "Chunk ID should be forced into the loading list."
	)


## Verifies that forcing a duplicate chunk load does not create multiple entries.
func test_request_chunk_duplicate() -> void:
	print("TestWorldChunkManager: Executing test_request_chunk_duplicate().")
	manager.call("_request_chunk", Vector2i(2, 2), false)
	manager.call("_request_chunk", Vector2i(2, 2), false)
	var loading_chunks: Dictionary = manager.get("loading_chunks") as Dictionary
	assert_eq(loading_chunks.size(), 1, "Should not add duplicate chunk IDs.")


## Verifies that forcing a chunk unload removes it from the active list.
func test_unload_chunk() -> void:
	print("TestWorldChunkManager: Executing test_unload_chunk().")
	var dummy_node: Node3D = Node3D.new()
	var loaded_chunks: Dictionary = manager.get("loaded_chunks") as Dictionary
	loaded_chunks[Vector2i(3, 3)] = dummy_node
	manager.call("_unload_chunk", Vector2i(3, 3))
	assert_false(loaded_chunks.has(Vector2i(3, 3)), "Chunk ID should be removed from loaded list.")
