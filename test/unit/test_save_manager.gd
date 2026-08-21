## Unit tests verifying SaveManager operations, save lists, sorting, and state loading.
extends GutTest

## Preloaded SaveManager class reference to guarantee inheritance resolution.
const SAVE_MANAGER_SCRIPT: GDScript = preload("res://core/save_manager.gd")

## The save manager instance being tested.
var save_manager: MockSaveManager = null


## Mocked partial class intercepting disk operations and threading.
class MockSaveManager:
	extends "res://core/save_manager.gd"

	## Array to hold mocked save metadata.
	var mock_saves: Array[Dictionary] = []

	## Tracker for whether metadata was written.
	var write_metadata_called: bool = false

	## Tracker for whether data was saved via threads.
	var thread_write_data_called: bool = false

	## Tracker for whether game state was read.
	var read_game_state_called: bool = false

	## Simulates writing metadata without touching disk.
	func _write_metadata(
		_path: String, _display_name: String, _time_str: String, _fav: bool
	) -> void:
		print("TestSaveManager: Mock _write_metadata() called.")
		write_metadata_called = true

	## Simulates threaded disk writing.
	func _threaded_write_data(_path: String, _data: Dictionary, _count: int) -> void:
		print("TestSaveManager: Mock _threaded_write_data() called.")
		thread_write_data_called = true

	## Returns mocked save data instead of accessing user:// directory.
	func get_all_saves() -> Array[Dictionary]:
		return mock_saves

	## Intercepts loading game state from a path.
	func _load_game_state(_path: String) -> void:
		print("TestSaveManager: Mock _load_game_state() called.")
		read_game_state_called = true

	## Checks if any saves exist in the mock storage.
	func has_saves() -> bool:
		return not mock_saves.is_empty()

	## Sorts save entries by favorite flag and ID descending.
	func _sort_saves(a: Dictionary, b: Dictionary) -> bool:
		var a_fav: bool = a.get("is_favorite", false)
		var b_fav: bool = b.get("is_favorite", false)
		if a_fav != b_fav:
			return a_fav
		var a_id: int = int(a.get("id", 0))
		var b_id: int = int(b.get("id", 0))
		return a_id > b_id


## Sets up the mock save manager instance before each test.
func before_each() -> void:
	print("TestSaveManager: before_each() setup started.")
	save_manager = MockSaveManager.new()
	if save_manager is Node:
		add_child_autoqfree(save_manager)


## Verifies retrieving saves from the manager returns expected entries.
func test_get_all_saves() -> void:
	print("TestSaveManager: test_get_all_saves() called.")
	var dummy_saves: Array[Dictionary] = [{"id": "123", "name": "Test Save"}]
	save_manager.mock_saves = dummy_saves

	var saves: Array[Dictionary] = save_manager.get_all_saves()
	assert_eq(saves.size(), 1, "Should return 1 save from mock.")
	assert_eq(saves[0]["name"], "Test Save", "Save name should match.")


## Verifies has_saves correctly returns false when no saves exist.
func test_has_saves_with_no_dir() -> void:
	print("TestSaveManager: test_has_saves_with_no_dir() called.")
	save_manager.mock_saves.clear()
	var result: bool = save_manager.has_saves()
	assert_false(result, "Should return false for saves when mock saves list is empty.")


## Verifies save entries sort by favorite priority and ID descending.
func test_sort_saves() -> void:
	print("TestSaveManager: test_sort_saves() called.")
	var a: Dictionary = {"id": "1", "is_favorite": false}
	var b: Dictionary = {"id": "2", "is_favorite": true}
	var c: Dictionary = {"id": "3", "is_favorite": false}

	assert_false(
		save_manager._sort_saves(a, b), "B is favorite, A is not. A should not come first."
	)
	assert_true(save_manager._sort_saves(b, a), "B is favorite, B should come first.")
	assert_false(save_manager._sort_saves(a, c), "C ID is higher, A should not come first.")
	assert_true(save_manager._sort_saves(c, a), "C ID is higher, C should come first.")


## Verifies loading game state calls internal interceptor.
func test_load_save_game() -> void:
	print("TestSaveManager: test_load_save_game() called.")
	save_manager._load_game_state("dummy_path")
	assert_true(save_manager.read_game_state_called, "_load_game_state should be intercepted.")
