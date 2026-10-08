## Unit tests verifying [WorldChunkManager] chunk load and unload operations.
class_name TestWorldChunkManager
extends GutTest

## The [WorldChunkManager] instance under test.
var manager: Node = null


## Instantiates [WorldChunkManager] and registers autofree cleanup before tests.
func before_each() -> void:
	print("TestWorldChunkManager: Executing before_each() setup.")
	var script: GDScript = load("res://core/virtual_chunk_manager.gd") as GDScript
	if script != null:
		var instance: Variant = script.new()
		if instance is Node:
			manager = instance
			manager.set("bypass_disk_check", true)
			add_child_autofree(manager)


## Verifies that forcing a chunk load adds it to the active list.
func test_request_chunk() -> void:
	print("TestWorldChunkManager: Executing test_request_chunk().")
	manager.call("_request_chunk", Vector2i(1, 1), false)
	var loading_chunks_var: Variant = manager.get("loading_chunks")
	var loading_chunks: Dictionary = {}
	if loading_chunks_var is Dictionary:
		loading_chunks = loading_chunks_var
	assert_true(
		loading_chunks.has(Vector2i(1, 1)), "Chunk ID should be forced into the loading list."
	)


## Verifies that forcing a duplicate chunk load does not create duplicate entries.
func test_request_chunk_duplicate() -> void:
	print("TestWorldChunkManager: Executing test_request_chunk_duplicate().")
	manager.call("_request_chunk", Vector2i(2, 2), false)
	manager.call("_request_chunk", Vector2i(2, 2), false)
	var loading_chunks_var: Variant = manager.get("loading_chunks")
	var loading_chunks: Dictionary = {}
	if loading_chunks_var is Dictionary:
		loading_chunks = loading_chunks_var
	assert_eq(loading_chunks.size(), 1, "Should not add duplicate chunk IDs.")


## Verifies that forcing a chunk unload removes it from the active list.
func test_unload_chunk() -> void:
	print("TestWorldChunkManager: Executing test_unload_chunk().")
	var dummy_node: Node3D = Node3D.new()
	var loaded_chunks_var: Variant = manager.get("loaded_chunks")
	var loaded_chunks: Dictionary = {}
	if loaded_chunks_var is Dictionary:
		loaded_chunks = loaded_chunks_var
	loaded_chunks[Vector2i(3, 3)] = dummy_node
	manager.call("_unload_chunk", Vector2i(3, 3))
	assert_false(loaded_chunks.has(Vector2i(3, 3)), "Chunk ID should be removed from loaded list.")
