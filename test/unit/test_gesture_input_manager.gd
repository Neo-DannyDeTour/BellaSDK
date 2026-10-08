class_name TestGestureInputManager
extends GutTest
## GUT test suite verifying gesture input buffering and frame triggering states.

## Node instance for the gesture input manager under test.
var input_manager: Node = null


## Pre-test setup instantiating manager and configuring test input action map.
func before_each() -> void:
	print("TestGestureInputManager: before_each() setup.")
	var script: GDScript = load("res://core/GestureInputManager.gd") as GDScript
	var raw_manager: Object = script.new()
	if raw_manager is Node:
		input_manager = raw_manager
		add_child_autofree(input_manager)

	if InputMap.has_action(&"test_action"):
		InputMap.erase_action(&"test_action")
	InputMap.add_action(&"test_action")


## Verifies that a fresh buffered action is consumed and purged from the buffer.
func test_consume_buffered_action() -> void:
	print("TestGestureInputManager: test_consume_buffered_action() called.")
	assert_not_null(input_manager, "Input manager node must be valid.")

	var now: float = Time.get_ticks_msec() / 1000.0
	var buffer_var: Variant = input_manager.get("_input_buffer")
	var buffer: Dictionary = buffer_var if buffer_var is Dictionary else {}
	buffer[&"test_action"] = now

	var consumed_var: Variant = input_manager.call("consume_buffered_action", &"test_action")
	var consumed: bool = consumed_var if consumed_var is bool else false
	assert_true(consumed, "Should successfully consume a buffered action.")

	var check_var: Variant = input_manager.get("_input_buffer")
	var buffer_check: Dictionary = check_var if check_var is Dictionary else {}
	var has_key: bool = buffer_check.has(&"test_action")
	assert_false(has_key, "Action should be removed from buffer.")


## Verifies that an expired action timestamp fails consumption and gets cleared.
func test_consume_expired_buffered_action() -> void:
	print("TestGestureInputManager: test_consume_expired_buffered_action() called.")
	assert_not_null(input_manager, "Input manager node must be valid.")

	var now: float = Time.get_ticks_msec() / 1000.0
	var duration_val: Variant = input_manager.get("BUFFER_DURATION")
	var buffer_duration: float = duration_val if duration_val is float else 0.2

	var buffer_var: Variant = input_manager.get("_input_buffer")
	var buffer: Dictionary = buffer_var if buffer_var is Dictionary else {}
	buffer[&"test_action"] = now - (buffer_duration + 0.1)

	var consumed_var: Variant = input_manager.call("consume_buffered_action", &"test_action")
	var consumed: bool = consumed_var if consumed_var is bool else false
	assert_false(consumed, "Should not consume an expired buffered action.")

	var check_var: Variant = input_manager.get("_input_buffer")
	var buffer_check: Dictionary = check_var if check_var is Dictionary else {}
	var has_key: bool = buffer_check.has(&"test_action")
	assert_false(has_key, "Expired action should be removed from buffer.")


## Verifies that an action triggered in the current physics frame reports true.
func test_is_action_just_triggered() -> void:
	print("TestGestureInputManager: test_is_action_just_triggered() called.")
	assert_not_null(input_manager, "Input manager node must be valid.")

	var current_frame: int = Engine.get_physics_frames()
	var triggered_var: Variant = input_manager.get("_triggered_actions_frame")
	var triggered_dict: Dictionary = triggered_var if triggered_var is Dictionary else {}
	triggered_dict[&"test_action"] = current_frame

	var result_var: Variant = input_manager.call("is_action_just_triggered", &"test_action")
	var is_triggered: bool = result_var if result_var is bool else false
	assert_true(is_triggered, "Should return true for action triggered this frame.")


## Verifies that an action released in the current physics frame reports true.
func test_is_action_just_released() -> void:
	print("TestGestureInputManager: test_is_action_just_released() called.")
	assert_not_null(input_manager, "Input manager node must be valid.")

	var current_frame: int = Engine.get_physics_frames()
	var released_var: Variant = input_manager.get("_released_actions_frame")
	var released_dict: Dictionary = released_var if released_var is Dictionary else {}
	released_dict[&"test_action"] = current_frame

	var result_var: Variant = input_manager.call("is_action_just_released", &"test_action")
	var is_released: bool = result_var if result_var is bool else false
	assert_true(is_released, "Should return true for action released this frame.")
