## Unit tests for [CameraController] validating wolf mode idle jitter, blends, and accessibility.
class_name TestCameraController
extends GutTest

## The [CameraController] instance under test.
var _controller: CameraController = null

## Mock eyes node tracking transforms.
var _eyes: Node3D = null

## Mock camera node.
var _camera: Camera3D = null

## Mock player body.
var _body: CharacterBody3D = null

## Mock head node.
var _head: Node3D = null


## Prepares test hierarchy before each test execution.
func before_each() -> void:
	print("TestCameraController: Setting up test environment.")
	_body = CharacterBody3D.new()
	_head = Node3D.new()
	_eyes = Node3D.new()
	_camera = Camera3D.new()
	_controller = CameraController.new()

	_body.add_child(_head)
	_head.add_child(_eyes)
	_eyes.add_child(_camera)
	_head.add_child(_controller)

	_controller.player_body = _body
	_controller.head = _head
	_controller.eyes = _eyes
	_controller.camera = _camera

	add_child_autoqfree(_body)


## Clears local instance references after each test execution.
func after_each() -> void:
	print("TestCameraController: Tearing down test environment.")
	_controller = null
	_eyes = null
	_camera = null
	_body = null
	_head = null


## Verifies that wolf mode toggle updates internal state via event bus.
func test_wolf_mode_event_toggle() -> void:
	print("TestCameraController: test_wolf_mode_event_toggle() executing.")
	assert_false(_controller.get("_is_wolf_mode"), "Wolf mode should be false by default.")

	Events.wolf_mode_toggled.emit(true)
	assert_true(_controller.get("_is_wolf_mode"), "Wolf mode should be true after signal.")

	Events.wolf_mode_toggled.emit(false)
	assert_false(_controller.get("_is_wolf_mode"), "Wolf mode should return to false.")


## Verifies idle in wolf mode blends in jitter on position and rotation.
func test_wolf_mode_idle_jitter_active() -> void:
	print("TestCameraController: test_wolf_mode_idle_jitter_active() executing.")
	Events.wolf_mode_toggled.emit(true)

	for index: int in 30:
		_controller.update_camera(0.016, Vector2.ZERO, false, false, true, 0.0)

	var blend: float = float(_controller.get("_wolf_idle_blend"))
	assert_gt(blend, 0.5, "Wolf idle blend weight should ramp up when stationary.")

	var has_rotation_jitter: bool = (
		absf(_eyes.rotation.x) > 0.00001
		or absf(_eyes.rotation.y) > 0.00001
		or absf(_eyes.rotation.z) > 0.00001
	)
	assert_true(has_rotation_jitter, "Eyes rotation should have active jitter when idle.")


## Verifies movement suppresses wolf idle jitter and resets rotation.
func test_movement_suppresses_wolf_idle_jitter() -> void:
	print("TestCameraController: test_movement_suppresses_wolf_idle_jitter() executing.")
	Events.wolf_mode_toggled.emit(true)

	for index: int in 30:
		_controller.update_camera(0.016, Vector2.ZERO, false, false, true, 0.0)

	for index: int in 40:
		_controller.update_camera(0.016, Vector2.UP, false, false, true, 5.0)

	var blend: float = float(_controller.get("_wolf_idle_blend"))
	assert_eq(blend, 0.0, "Wolf idle blend weight should decay to 0 when moving.")
	assert_eq(_eyes.rotation.x, 0.0, "Eyes pitch rotation should be zeroed when moving.")
	assert_eq(_eyes.rotation.y, 0.0, "Eyes yaw rotation should be zeroed when moving.")


## Verifies reduce_motion setting disables wolf idle jitter completely.
func test_reduce_motion_disables_wolf_idle_jitter() -> void:
	print("TestCameraController: test_reduce_motion_disables_wolf_idle_jitter() executing.")
	Events.wolf_mode_toggled.emit(true)
	_controller.reduce_motion = true

	for index: int in 30:
		_controller.update_camera(0.016, Vector2.ZERO, false, false, true, 0.0)

	var blend: float = float(_controller.get("_wolf_idle_blend"))
	assert_eq(blend, 0.0, "Wolf idle blend weight should remain 0 when reduce_motion is true.")
	assert_eq(_eyes.rotation.x, 0.0, "Eyes pitch rotation should remain 0.")
	assert_eq(_eyes.rotation.y, 0.0, "Eyes yaw rotation should remain 0.")
