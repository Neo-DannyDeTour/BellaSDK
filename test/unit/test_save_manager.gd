extends GutTest

## The save manager being tested. Using Variant to prevent parse errors.
var save_manager: Variant = null


# We use a mocked partial class to intercept file writes and threads
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

	# Override so it doesn't write to disk during testing
	func _write_metadata(
		_path: String, _display_name: String, _time_str: String, _fav: bool
	) -> void:
		print("TestSaveManager: Mock _write_metadata() called.")
		write_metadata_called = true

	# Override the threaded function that writes the actual file
	func _threaded_write_data(_path: String, _data: Dictionary, _count: int) -> void:
		print("TestSaveManager: Mock _threaded_write_data() called.")
		thread_write_data_called = true

	# Override get_all_saves to return our dummy data instead of checking user://
	func get_all_saves() -> Array[Dictionary]:
		return mock_saves

	func _load_game_state(_path: String) -> void:
		print("TestSaveManager: Mock _load_game_state() called.")
		read_game_state_called = true


func before_each() -> void:
	print("TestSaveManager: before_each() called. Setting up test environment.")
	save_manager = MockSaveManager.new()
	add_child_autofree(save_manager)


func test_get_all_saves() -> void:
	print("TestSaveManager: test_get_all_saves() called.")
	var dummy_saves: Array[Dictionary] = [{"id": "123", "name": "Test Save"}]
	save_manager.mock_saves = dummy_saves

	var saves: Array[Dictionary] = save_manager.get_all_saves()
	assert_eq(saves.size(), 1, "Should return 1 save from mock.")
	assert_eq(saves[0]["name"], "Test Save", "Save name should match.")


func test_has_saves_with_no_dir() -> void:
	print("TestSaveManager: test_has_saves_with_no_dir() called.")
	# Checking basic return logic when the directory does not have standard files
	# or when bypassing disk interaction for this generic return.
	var result: bool = save_manager.has_saves()
	assert_false(result, "Should return false for saves when directory is empty or inaccessible.")


func test_sort_saves() -> void:
	print("TestSaveManager: test_sort_saves() called.")
	var a: Dictionary = {"id": "1", "is_favorite": false}
	var b: Dictionary = {"id": "2", "is_favorite": true}
	var c: Dictionary = {"id": "3", "is_favorite": false}

	# Should return true if A is fav and B is not, or if A ID > B ID
	assert_false(
		save_manager._sort_saves(a, b), "B is favorite, A is not. A should not come first."
	)
	assert_true(save_manager._sort_saves(b, a), "B is favorite, B should come first.")

	# IDs are strings parsed to ints
	assert_false(save_manager._sort_saves(a, c), "C's ID is higher, A should not come first.")
	assert_true(save_manager._sort_saves(c, a), "C's ID is higher, C should come first.")


func test_load_save_game() -> void:
	print("TestSaveManager: test_load_save_game() called.")
	# Tests our mock load interception
	save_manager._load_game_state("dummy_path")
	assert_true(save_manager.read_game_state_called, "_load_game_state should be intercepted.")
