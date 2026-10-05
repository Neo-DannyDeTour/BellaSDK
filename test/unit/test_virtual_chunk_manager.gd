## Unit tests for the [ChunkManager] system.
##
## This suite verifies the behavior of the [ChunkManager] to ensure
## forced triggers for loading and unloading chunk IDs operate correctly without duplicates.
class_name TestChunkManager
extends GutTest

## The [ChunkManager] instance under test.
var manager: Node = null


## Instantiates [ChunkManager] and registers autofree cleanup before each test.
func before_each() -> void:
	print("TestChunkManager: Executing before_each() setup.")
	manager = load("res://core/chunk_manager.gd").new() as Node
	add_child_autofree(manager)


## Verifies that forcing a chunk load adds it to the active list.
func test_trigger_load_chunk() -> void:
	print("TestChunkManager: Executing test_trigger_load_chunk().")
	manager.call("trigger_load_chunk", "sewer_01")
	var active_chunks: Array = manager.get("trigger_active_chunks") as Array
	assert_true(active_chunks.has("sewer_01"), "Chunk ID should be forced into the active list.")


## Verifies that forcing a duplicate chunk load does not create multiple entries.
func test_trigger_load_duplicate() -> void:
	print("TestChunkManager: Executing test_trigger_load_duplicate().")
	manager.call("trigger_load_chunk", "boss_room")
	manager.call("trigger_load_chunk", "boss_room")
	var active_chunks: Array = manager.get("trigger_active_chunks") as Array
	assert_eq(active_chunks.size(), 1, "Should not add duplicate chunk IDs.")


## Verifies that forcing a chunk unload removes it from the active list.
func test_trigger_unload_chunk() -> void:
	print("TestChunkManager: Executing test_trigger_unload_chunk().")
	manager.call("trigger_load_chunk", "armory")
	manager.call("trigger_unload_chunk", "armory")
	var active_chunks: Array = manager.get("trigger_active_chunks") as Array
	assert_false(active_chunks.has("armory"), "Chunk ID should be removed from active list.")
