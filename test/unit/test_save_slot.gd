## Unit test suite validating SaveSlot UI state initialization and signal handling.
extends GutTest

const SAVE_SLOT_SCENE: PackedScene = preload("res://core/save_slot.tscn")

## Instance of the SaveSlot UI component under test.
var _save_slot: SaveSlot


## Instantiates and adds a fresh SaveSlot node before each test case runs.
func before_each() -> void:
	print("Setting up SaveSlot instance for test execution.")
	_save_slot = SAVE_SLOT_SCENE.instantiate() as SaveSlot
	add_child_autofree(_save_slot)


## Cleans up the SaveSlot instance after test completion.
func after_each() -> void:
	print("Tearing down SaveSlot test instance.")
	_save_slot = null


## Verifies correct slot text and favorite state configuration on setup.
func test_setup_load_mode() -> void:
	print("Testing SaveSlot setup in Load mode.")
	var test_data: Dictionary = {
		"base_path": "user://saves/save_001",
		"id": "save_001",
		"name": "Hero Save",
		"timestamp": "2026-01-01 10:00",
		"is_favorite": false
	}
	_save_slot.setup(test_data, false)

	assert_eq(
		_save_slot.name_input.text, "Hero Save", "Name input should reflect save metadata name."
	)
	assert_eq(_save_slot.date_label.text, "2026-01-01 10:00", "Date label should match timestamp.")
	assert_eq(
		_save_slot.action_button.text,
		"Load",
		"Action button text should be 'Load' when is_saving is false."
	)
	assert_false(_save_slot.fav_button.button_pressed, "Favorite button should not be pressed.")


## Verifies action button text in overwrite/saving mode.
func test_setup_save_mode() -> void:
	print("Testing SaveSlot setup in Save mode.")
	var test_data: Dictionary = {
		"base_path": "user://saves/save_002",
		"id": "save_002",
		"name": "Checkpoint Save",
		"timestamp": "2026-01-02 14:30",
		"is_favorite": true
	}
	_save_slot.setup(test_data, true)

	assert_eq(
		_save_slot.action_button.text,
		"Overwrite",
		"Action button text should be 'Overwrite' when is_saving is true."
	)
	assert_true(
		_save_slot.fav_button.button_pressed,
		"Favorite button should be pressed when is_favorite is true."
	)


## Verifies signal emission when action button is pressed.
func test_action_button_pressed_signal() -> void:
	print("Testing SaveSlot action_pressed signal emission.")
	var test_data: Dictionary = {
		"base_path": "user://saves/slot_01",
		"id": "slot_01",
		"name": "Slot 1",
		"timestamp": "Now",
		"is_favorite": false
	}
	_save_slot.setup(test_data, false)
	watch_signals(_save_slot)

	_save_slot.action_button.pressed.emit()

	assert_signal_emitted_with_parameters(_save_slot, "action_pressed", ["user://saves/slot_01"])


## Verifies signal emission when favorite status is toggled.
func test_favorite_toggled_signal() -> void:
	print("Testing SaveSlot favorite button toggle signal emission.")
	var test_data: Dictionary = {
		"base_path": "user://saves/slot_02",
		"id": "slot_02",
		"name": "Slot 2",
		"timestamp": "Now",
		"is_favorite": false
	}
	_save_slot.setup(test_data, false)
	watch_signals(_save_slot)

	_save_slot.fav_button.toggled.emit(true)

	assert_signal_emitted_with_parameters(_save_slot, "meta_updated", ["slot_02", "Slot 2", true])


## Verifies signal emission when delete button is pressed.
func test_delete_button_pressed_signal() -> void:
	print("Testing SaveSlot delete_pressed signal emission.")
	var test_data: Dictionary = {
		"base_path": "user://saves/slot_03",
		"id": "slot_03",
		"name": "Slot 3",
		"timestamp": "Now",
		"is_favorite": false
	}
	_save_slot.setup(test_data, false)
	watch_signals(_save_slot)

	_save_slot.delete_button.pressed.emit()

	assert_signal_emitted_with_parameters(
		_save_slot, "delete_pressed", ["slot_03", "user://saves/slot_03"]
	)
