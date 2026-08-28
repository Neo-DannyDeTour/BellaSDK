extends GutTest

## Variant instance for the gesture input manager under test.
var input_manager: Variant = null


func before_each() -> void:
	print("TestGestureInputManager: before_each() setup.")
	input_manager = load("res://core/GestureInputManager.gd").new()
	add_child_autofree(input_manager)

	# Clean up input map before tests
	if InputMap.has_action("test_action"):
		InputMap.erase_action("test_action")
	InputMap.add_action("test_action")


func test_consume_buffered_action() -> void:
	print("TestGestureInputManager: test_consume_buffered_action() called.")
	# Manually push to internal buffer to test consumption
	var now: float = Time.get_ticks_msec() / 1000.0
	input_manager._input_buffer["test_action"] = now

	var consumed: bool = input_manager.consume_buffered_action("test_action")
	assert_true(consumed, "Should successfully consume a buffered action.")

	# Verify it was removed
	assert_false(
		input_manager._input_buffer.has("test_action"), "Action should be removed from buffer."
	)


func test_consume_expired_buffered_action() -> void:
	print("TestGestureInputManager: test_consume_expired_buffered_action() called.")
	# Manually push to internal buffer with an old timestamp
	var now: float = Time.get_ticks_msec() / 1000.0
	input_manager._input_buffer["test_action"] = now - (input_manager.BUFFER_DURATION + 0.1)

	var consumed: bool = input_manager.consume_buffered_action("test_action")
	assert_false(consumed, "Should not consume an expired buffered action.")

	# Verify it was still removed
	assert_false(
		input_manager._input_buffer.has("test_action"),
		"Expired action should be removed from buffer."
	)


func test_is_action_just_triggered() -> void:
	print("TestGestureInputManager: test_is_action_just_triggered() called.")

	var current_frame: int = Engine.get_physics_frames()
	input_manager._triggered_actions_frame["test_action"] = current_frame

	assert_true(
		input_manager.is_action_just_triggered("test_action"),
		"Should return true for action triggered this frame."
	)


func test_is_action_just_released() -> void:
	print("TestGestureInputManager: test_is_action_just_released() called.")

	var current_frame: int = Engine.get_physics_frames()
	input_manager._released_actions_frame["test_action"] = current_frame

	assert_true(
		input_manager.is_action_just_released("test_action"),
		"Should return true for action released this frame."
	)
