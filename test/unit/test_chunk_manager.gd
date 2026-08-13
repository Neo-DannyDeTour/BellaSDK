extends GutTest

## Variant instance for the chunk manager under test
var manager: Variant = null


func before_each() -> void:
	print("TestChunkManager: before_each() setup.")
	manager = load("res://core/chunk_manager.gd").new()
	add_child_autofree(manager)


func test_trigger_load_chunk() -> void:
	print("TestChunkManager: test_trigger_load_chunk() called.")
	manager.trigger_load_chunk("sewer_01")
	assert_true(
		manager.trigger_active_chunks.has("sewer_01"),
		"Chunk ID should be forced into the active list."
	)


func test_trigger_load_duplicate() -> void:
	print("TestChunkManager: test_trigger_load_duplicate() called.")
	manager.trigger_load_chunk("boss_room")
	manager.trigger_load_chunk("boss_room")
	assert_eq(manager.trigger_active_chunks.size(), 1, "Should not add duplicate chunk IDs.")


func test_trigger_unload_chunk() -> void:
	print("TestChunkManager: test_trigger_unload_chunk() called.")
	manager.trigger_load_chunk("armory")
	manager.trigger_unload_chunk("armory")
	assert_false(
		manager.trigger_active_chunks.has("armory"), "Chunk ID should be removed from active list."
	)
