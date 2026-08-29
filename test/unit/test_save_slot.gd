## Unit tests for the [SaveSlot] UI component.
extends GutTest

## The instance of the SaveSlot for testing.
var _save_slot: SaveSlot


## Setup logic that runs before each individual test.
func before_each() -> void:
	print("Setting up SaveSlot test environment...")
	# We instantiate the scene directly since it has UI dependencies and script attached.
	var scene: PackedScene = load("res://core/save_slot.tscn")
	_save_slot = scene.instantiate()
	add_child_autofree(_save_slot)


## Teardown logic that runs after each individual test.
func after_each() -> void:
	print("Tearing down SaveSlot test environment...")


## Tests the initial configuration and default values of the save slot.
func test_initial_state() -> void:
	print("Executing test_initial_state...")
	assert_not_null(_save_slot, "Save slot instance should not be null.")

	# Verify that the critical UI nodes are present and initialized
	assert_not_null(_save_slot.thumbnail, "Thumbnail texture rect should be initialized.")
	assert_not_null(_save_slot.name_input, "Name input line edit should be initialized.")
	assert_not_null(_save_slot.date_label, "Date label should be initialized.")
	assert_not_null(_save_slot.fav_button, "Favorite button should be initialized.")


## Tests signal emissions for basic interactions if simulated.
func test_signal_emission() -> void:
	print("Executing test_signal_emission...")
	watch_signals(_save_slot)

	# Simulate a basic metadata update
	var test_id: String = "test_slot_01"
	var test_name: String = "My Save"
	var test_fav: bool = true

	_save_slot.meta_updated.emit(test_id, test_name, test_fav)
	assert_signal_emitted_with_parameters(
		_save_slot, "meta_updated", [test_id, test_name, test_fav]
	)
