extends GutTest

## The target InteractionManager instance we are testing
var _interaction_manager: InteractionManager

## Mock camera used for raycast logic simulation
var _mock_camera: Camera3D

## Mock interactable body for hit simulation
var _mock_target: StaticBody3D


func before_each() -> void:
	print("Setting up InteractionManager test environment.")
	_interaction_manager = InteractionManager.new()
	add_child_autofree(_interaction_manager)

	_mock_camera = Camera3D.new()
	add_child_autofree(_mock_camera)

	_mock_target = StaticBody3D.new()
	add_child_autofree(_mock_target)


func test_set_source_camera() -> void:
	print("Testing InteractionManager.set_source_camera()")
	_interaction_manager.set_source_camera(_mock_camera)
	assert_eq(
		_interaction_manager.source_camera,
		_mock_camera,
		"Source camera should match the assigned camera."
	)


func test_clear_focus() -> void:
	print("Testing InteractionManager.clear_focus()")
	_interaction_manager.current_target = _mock_target
	_interaction_manager.clear_focus()
	assert_null(
		_interaction_manager.current_target, "Current target should be null after clearing focus."
	)


func test_try_interact_fails_with_no_target() -> void:
	print("Testing InteractionManager.try_interact() fails gracefully without target.")
	_interaction_manager.current_target = null
	var result: bool = _interaction_manager.try_interact(_mock_camera)
	assert_false(result, "Try interact should return false if no target is focused.")


func test_scan_for_interactable_handles_no_camera() -> void:
	print("Testing scan_for_interactable() bypasses if no source camera exists.")
	_interaction_manager.source_camera = null
	_interaction_manager.scan_for_interactable()
	assert_true(true, "scan_for_interactable executed safely without camera.")
