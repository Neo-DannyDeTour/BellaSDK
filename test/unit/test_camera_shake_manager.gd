## Unit test suite for CameraShakeManager handling screenshake, rumble, and accessibility.
class_name TestCameraShakeManager
extends GutTest

## Internal reference to the CameraShakeManager node under test.
var _shake_manager: CameraShakeManager = null

## Internal mock Camera3D node used for registering target camera.
var _mock_camera: Camera3D = null


## Sets up nodes and adds them to scene tree before each test.
func before_each() -> void:
	print("TestCameraShakeManager: Setting up test environment.")
	_shake_manager = CameraShakeManager.new()
	add_child_autofree(_shake_manager)

	_mock_camera = Camera3D.new()
	add_child_autofree(_mock_camera)


## Cleans up test nodes after each test method.
func after_each() -> void:
	print("TestCameraShakeManager: Cleaning up test environment.")
	_shake_manager = null
	_mock_camera = null


## Tests initial state and default property assignments.
func test_initial_state() -> void:
	print("TestCameraShakeManager: Testing initial property defaults.")
	assert_eq(_shake_manager.trauma, 0.0, "Initial trauma should be 0.0.")
	assert_eq(_shake_manager.global_intensity, 1.0, "Default global intensity should be 1.0.")


## Tests adding impulse trauma and clamping behavior.
func test_add_trauma_and_clamping() -> void:
	print("TestCameraShakeManager: Testing add_trauma clamping.")
	_shake_manager.add_trauma(0.5)
	assert_eq(_shake_manager.trauma, 0.5, "Trauma should accumulate to 0.5.")

	_shake_manager.add_trauma(0.8)
	assert_eq(_shake_manager.trauma, 1.0, "Trauma should be clamped at upper bound 1.0.")


## Tests accessibility intensity multiplier setter and clamping.
func test_set_accessibility_scale() -> void:
	print("TestCameraShakeManager: Testing accessibility scaling limits.")
	_shake_manager.set_accessibility_scale(0.5)
	assert_eq(_shake_manager.global_intensity, 0.5, "Global intensity should be set to 0.5.")

	_shake_manager.set_accessibility_scale(3.0)
	assert_eq(
		_shake_manager.global_intensity, 2.0, "Global intensity should be clamped to max 2.0."
	)

	_shake_manager.set_accessibility_scale(-0.5)
	assert_eq(
		_shake_manager.global_intensity, 0.0, "Global intensity should be clamped to min 0.0."
	)


## Tests register_camera binding and original transform caching.
func test_register_camera() -> void:
	print("TestCameraShakeManager: Testing active camera registration.")
	_mock_camera.transform.origin = Vector3(1.0, 2.0, 3.0)
	_shake_manager.register_camera(_mock_camera)

	assert_eq(
		_shake_manager.get("_active_camera"), _mock_camera, "Active camera should be registered."
	)


## Tests process step trauma decay.
func test_trauma_decay_in_process() -> void:
	print("TestCameraShakeManager: Testing trauma decay rate step.")
	_shake_manager.register_camera(_mock_camera)
	_shake_manager.add_trauma(1.0)

	_shake_manager._process(0.2)
	assert_true(_shake_manager.trauma < 1.0, "Trauma should decay after process step.")


## Tests sustained rumble effect and timer decay.
func test_start_rumble_and_decay() -> void:
	print("TestCameraShakeManager: Testing sustained rumble timing.")
	_shake_manager.register_camera(_mock_camera)
	_shake_manager.start_rumble(0.8, 1.0)

	assert_eq(
		_shake_manager.get("_sustained_rumble_intensity"), 0.8, "Rumble intensity should be set."
	)

	_shake_manager._process(0.5)
	assert_eq(
		_shake_manager.get("_sustained_rumble_intensity"),
		0.8,
		"Rumble intensity should remain during active timer."
	)

	_shake_manager._process(0.6)
	assert_eq(
		_shake_manager.get("_sustained_rumble_intensity"),
		0.0,
		"Rumble intensity should reset to 0 after timer expires."
	)


## Tests stop_all clearing trauma and rumble state.
func test_stop_all() -> void:
	print("TestCameraShakeManager: Testing stop_all state reset.")
	watch_signals(_shake_manager)
	_shake_manager.add_trauma(0.8)
	_shake_manager.start_rumble(0.5, 2.0)

	_shake_manager.stop_all()

	assert_eq(_shake_manager.trauma, 0.0, "Trauma should be 0.0 after stop_all().")
	assert_eq(
		_shake_manager.get("_sustained_rumble_intensity"), 0.0, "Rumble intensity should be 0.0."
	)
	assert_signal_emitted(
		_shake_manager, "shake_finished", "shake_finished signal should be emitted."
	)
