extends GutTest

## The SaveSlot node to test
var save_slot: SaveSlot = null


func before_each() -> void:
	print("TestSaveSlot: before_each() setup.")
	var scene: PackedScene = load("res://core/save_slot.tscn")
	save_slot = scene.instantiate() as SaveSlot
	# Need to trigger ready before test since we instantiate but are headless.
	add_child_autofree(save_slot)

	# Mock UI elements needed for setup() and signal emissions in headless test.
	if not is_instance_valid(save_slot.name_input):
		save_slot.name_input = LineEdit.new()
		save_slot.add_child(save_slot.name_input)
	if not is_instance_valid(save_slot.date_label):
		save_slot.date_label = Label.new()
		save_slot.add_child(save_slot.date_label)
	if not is_instance_valid(save_slot.fav_button):
		save_slot.fav_button = Button.new()
		save_slot.add_child(save_slot.fav_button)
	if not is_instance_valid(save_slot.action_button):
		save_slot.action_button = Button.new()
		save_slot.add_child(save_slot.action_button)
	if not is_instance_valid(save_slot.thumbnail):
		save_slot.thumbnail = TextureRect.new()
		save_slot.add_child(save_slot.thumbnail)
	if not is_instance_valid(save_slot.highlight_border):
		save_slot.highlight_border = Control.new()
		save_slot.add_child(save_slot.highlight_border)

	if save_slot.has_method("_ready"):
		save_slot._ready()


func test_setup_load() -> void:
	print("TestSaveSlot: test_setup_load() called.")

	## Mock metadata dictionary representing a loaded save file to test setup logic
	var data: Dictionary = {
		"base_path": "user://saves/save_123",
		"id": "123",
		"name": "My Cool Save",
		"timestamp": "2023-10-27",
		"is_favorite": true
	}

	save_slot.setup(data, false)

	assert_eq(
		save_slot._base_path, "user://saves/save_123", "Base path should be correctly assigned."
	)
	assert_eq(save_slot._save_id, "123", "Save ID should be correctly assigned.")
	assert_eq(save_slot.name_input.text, "My Cool Save", "Name input should match data.")
	assert_eq(save_slot.date_label.text, "2023-10-27", "Date label should match data.")
	assert_true(save_slot.fav_button.button_pressed, "Fav button should be pressed based on data.")
	assert_eq(
		save_slot.action_button.text,
		"Load",
		"Action button text should be 'Load' when is_saving is false."
	)


func test_setup_overwrite() -> void:
	print("TestSaveSlot: test_setup_overwrite() called.")

	## Mock metadata dictionary representing a save slot when the game is being saved
	var data: Dictionary = {
		"base_path": "user://saves/save_456",
		"id": "456",
		"name": "Another Save",
		"timestamp": "2023-10-28",
		"is_favorite": false
	}

	save_slot.setup(data, true)

	assert_eq(
		save_slot.action_button.text,
		"Overwrite",
		"Action button text should be 'Overwrite' when is_saving is true."
	)
	assert_false(
		save_slot.fav_button.button_pressed, "Fav button should not be pressed based on data."
	)


func test_action_button_pressed() -> void:
	print("TestSaveSlot: test_action_button_pressed() called.")
	watch_signals(save_slot)

	save_slot._base_path = "user://saves/save_test"
	save_slot._on_action_button_pressed()

	assert_signal_emitted_with_parameters(save_slot, "action_pressed", ["user://saves/save_test"])


func test_emit_meta_update() -> void:
	print("TestSaveSlot: test_emit_meta_update() called.")
	watch_signals(save_slot)

	save_slot._save_id = "test_id"
	save_slot.name_input.text = "  Test Name  "
	save_slot.fav_button.button_pressed = true

	save_slot._emit_meta_update()

	# Note: name should be stripped of edges
	assert_signal_emitted_with_parameters(save_slot, "meta_updated", ["test_id", "Test Name", true])
