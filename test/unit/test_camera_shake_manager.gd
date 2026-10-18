## Unit tests for [CameraShakeManager] validating trauma decay, process gating, and camera offsets.
class_name TestCameraShakeManager
extends GutTest

## The [CameraShakeManager] instance under test.
var _manager: CameraShakeManager = null

## Mock camera node instance.
var _camera: Camera3D = null

## Tracks whether shake_finished signal was received.
var _finished_emitted: bool = false


## Signal listener recording shake completion.
func _on_shake_finished() -> void:
	_finished_emitted = true


## Prepares test manager and camera before each test execution.
func before_each() -> void:
	print("TestCameraShakeManager: Setting up test environment.")
	_finished_emitted = false
	_manager = CameraShakeManager.new()
	add_child_autoqfree(_manager)

	_camera = Camera3D.new()
	_camera.name = "TestCamera"
	_camera.transform = Transform3D.IDENTITY
	add_child_autoqfree(_camera)

	_manager.register_camera(_camera)
	_manager.shake_finished.connect(_on_shake_finished)


## Clears local instance references after each test execution.
func after_each() -> void:
	print("TestCameraShakeManager: Tearing down test environment.")
	_manager = null
	_camera = null


## Verifies that process is disabled initially for 60 FPS event-driven efficiency.
func test_initial_state_and_process_disabled() -> void:
	print("TestCameraShakeManager: test_initial_state_and_process_disabled() executing.")
	assert_eq(_manager.trauma, 0.0, "Initial trauma should be 0.0.")
	assert_false(_manager.is_processing(), "Process should be disabled when idle.")


## Verifies adding trauma clamps between 0.0 and 1.0 and activates processing.
func test_add_trauma_clamps_and_wakes_process() -> void:
	print("TestCameraShakeManager: test_add_trauma_clamps_and_wakes_process() executing.")
	_manager.add_trauma(0.4)
	assert_eq(_manager.trauma, 0.4, "Trauma should accumulate.")
	assert_true(_manager.is_processing(), "Process should be enabled when trauma > 0.")

	_manager.add_trauma(0.8)
	assert_eq(_manager.trauma, 1.0, "Trauma must clamp at 1.0 maximum.")


## Verifies starting sustained rumble sets timers and activates processing.
func test_start_rumble_wakes_process() -> void:
	print("TestCameraShakeManager: test_start_rumble_wakes_process() executing.")
	_manager.start_rumble(0.6, 2.0)
	assert_eq(_manager.get("_sustained_rumble_intensity"), 0.6, "Rumble intensity must be set.")
	assert_eq(_manager.get("_sustained_rumble_timer"), 2.0, "Rumble timer must be set.")
	assert_true(_manager.is_processing(), "Process should be enabled during sustained rumble.")


## Verifies trauma decay over time and sleeping when decay completes.
func test_trauma_decay_and_sleep() -> void:
	print("TestCameraShakeManager: test_trauma_decay_and_sleep() executing.")
	_manager.add_trauma(0.5)
	_manager.trauma_decay_rate = 1.0

	# Step half duration
	_manager._process(0.25)
	assert_almost_eq(_manager.trauma, 0.25, 0.01, "Trauma should decay linearly with delta.")
	assert_true(_manager.is_processing(), "Process should remain active while decaying.")

	# Step past zero
	_manager._process(0.5)
	assert_eq(_manager.trauma, 0.0, "Trauma should clamp to 0.0.")
	assert_false(_manager.is_processing(), "Process must sleep once trauma decays.")
	assert_true(_finished_emitted, "shake_finished must emit when shake concludes.")


## Verifies accessibility scaling clamps and modifies effective intensity.
func test_accessibility_scale_clamping() -> void:
	print("TestCameraShakeManager: test_accessibility_scale_clamping() executing.")
	_manager.set_accessibility_scale(0.5)
	assert_eq(_manager.global_intensity, 0.5, "Intensity scale should update.")

	_manager.set_accessibility_scale(-1.0)
	assert_eq(_manager.global_intensity, 0.0, "Scale must clamp to minimum 0.0.")

	_manager.set_accessibility_scale(3.5)
	assert_eq(_manager.global_intensity, 2.0, "Scale must clamp to maximum 2.0.")


## Verifies stop_all halts shake, resets camera transform, and sleeps process.
func test_stop_all_resets_and_sleeps() -> void:
	print("TestCameraShakeManager: test_stop_all_resets_and_sleeps() executing.")
	_manager.add_trauma(1.0)
	_manager.start_rumble(1.0, 5.0)
	assert_true(_manager.is_processing(), "Process should be active.")

	_manager.stop_all()
	assert_eq(_manager.trauma, 0.0, "Trauma must reset to 0.0.")
	assert_eq(
		_manager.get("_sustained_rumble_intensity"), 0.0, "Rumble intensity must reset to 0.0."
	)
	assert_false(_manager.is_processing(), "Process must sleep after stop_all.")
	assert_true(_finished_emitted, "shake_finished must emit on stop_all.")
	assert_eq(_camera.transform, Transform3D.IDENTITY, "Camera transform must reset.")
