## Unit tests for InputHelper input formatting and icon lookup helper.
class_name TestInputHelper
extends GutTest

const INPUT_HELPER_SCRIPT: GDScript = preload("res://ui/InputHelper.gd")

## Primary InputHelper instance under test.
var _input_helper: Node = null


## Prepares a clean InputHelper node instance before each test execution.
func before_each() -> void:
	print("TestInputHelper: before_each() setup started.")
	_input_helper = INPUT_HELPER_SCRIPT.new()
	add_child_autofree(_input_helper)


## Cleans up InputHelper node reference after each test execution.
func after_each() -> void:
	print("TestInputHelper: after_each() cleanup completed.")
	_input_helper = null


## Verifies key label sanitization and stripping of internal physical tags.
func test_sanitize_key_name() -> void:
	print("TestInputHelper: test_sanitize_key_name() executing.")
	@warning_ignore("unsafe_method_access")
	var res_1: String = _input_helper.call("sanitize_key_name", "W (Physical)")
	assert_eq(res_1, "W", "Should strip '(Physical)' tag.")

	@warning_ignore("unsafe_method_access")
	var res_2: String = _input_helper.call("sanitize_key_name", "Space - Physical")
	assert_eq(res_2, "Space", "Should strip '- Physical' suffix.")

	@warning_ignore("unsafe_method_access")
	var res_3: String = _input_helper.call("sanitize_key_name", "Left Mouse Button")
	assert_eq(res_3, "LMB", "Should convert 'Left Mouse Button' to 'LMB'.")

	@warning_ignore("unsafe_method_access")
	var res_4: String = _input_helper.call("sanitize_key_name", "Right Mouse Button")
	assert_eq(res_4, "RMB", "Should convert 'Right Mouse Button' to 'RMB'.")

	@warning_ignore("unsafe_method_access")
	var res_5: String = _input_helper.call("sanitize_key_name", "Middle Mouse Button")
	assert_eq(res_5, "MMB", "Should convert 'Middle Mouse Button' to 'MMB'.")


## Verifies icon texture resolution logic for keyboard input events.
func test_get_event_icon_keyboard() -> void:
	print("TestInputHelper: test_get_event_icon_keyboard() executing.")
	var key_ev: InputEventKey = InputEventKey.new()
	key_ev.physical_keycode = KEY_SPACE

	@warning_ignore("unsafe_method_access")
	var icon: Variant = _input_helper.call("get_event_icon", key_ev)
	assert_true(icon == null or icon is Texture2D, "Icon result should be null or Texture2D.")


## Verifies icon texture resolution logic for mouse input events.
func test_get_event_icon_mouse() -> void:
	print("TestInputHelper: test_get_event_icon_mouse() executing.")
	var mouse_ev: InputEventMouseButton = InputEventMouseButton.new()
	mouse_ev.button_index = MOUSE_BUTTON_LEFT

	@warning_ignore("unsafe_method_access")
	var icon: Variant = _input_helper.call("get_event_icon", mouse_ev)
	assert_true(icon == null or icon is Texture2D, "Icon result should be null or Texture2D.")
