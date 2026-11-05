## Unit tests for [TriggerLook] validating gaze duration, target activation, and lifecycle.
class_name TestTriggerLook
extends GutTest


## Mock target class recording add_power calls.
class MockPowerTarget:
	extends Node

	## Counter for dispatched power activations.
	var power_calls: int = 0

	## Receives dispatched power activation.
	func add_power() -> void:
		power_calls += 1


## The [TriggerLook] instance under test.
var _trigger: TriggerLook = null

## The mock player node instance.
var _player: Node3D = null

## The target node looked at by player camera.
var _marker: Marker3D = null

## The mock target node receiving power activation calls.
var _target: MockPowerTarget = null

## The camera node simulating player view.
var _camera: Camera3D = null


## Prepares test nodes and wiring before each test execution.
func before_each() -> void:
	print("TestTriggerLook: Setting up test environment.")
	_trigger = TriggerLook.new()

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	col.shape = BoxShape3D.new()
	_trigger.add_child(col)

	_marker = Marker3D.new()
	_marker.name = "TriggerLookMarker"
	_marker.position = Vector3(0.0, 0.0, -5.0)
	_trigger.add_child(_marker)

	_target = MockPowerTarget.new()
	_target.name = "MockPowerTarget"
	_trigger.add_child(_target)

	_trigger.look_target = _marker
	_trigger.targets = [_target]
	_trigger.required_look_time = 0.5
	_trigger.look_tolerance = 0.9
	_trigger.fire_once = true

	add_child_autoqfree(_trigger)

	_player = Node3D.new()
	_player.name = "Player"
	add_child_autoqfree(_player)

	_camera = Camera3D.new()
	_camera.name = "PlayerCamera"
	_camera.position = Vector3(0.0, 0.0, 0.0)
	_camera.current = true
	add_child_autoqfree(_camera)


## Clears local instance references after each test execution.
func after_each() -> void:
	print("TestTriggerLook: Tearing down test environment.")
	_trigger = null
	_player = null
	_marker = null
	_target = null
	_camera = null


## Verifies initial property state and disabled process state.
func test_initial_state() -> void:
	print("TestTriggerLook: test_initial_state() executing.")
	assert_false(
		_trigger.auto_consume_on_entry, "TriggerLook must set auto_consume_on_entry to false."
	)
	assert_false(
		_trigger.is_processing(), "TriggerLook must not process while player is outside volume."
	)


## Verifies that player physical entry activates gaze processing without consuming trigger.
func test_entry_activates_process_without_consuming() -> void:
	print("TestTriggerLook: test_entry_activates_process_without_consuming() executing.")
	_trigger._on_body_entered(_player)

	assert_false(
		_trigger._has_triggered, "Trigger must not be marked triggered merely on volume entry."
	)
	assert_true(_trigger.is_processing(), "TriggerLook must start processing when player enters.")


## Verifies player exit stops processing and resets gaze accumulator.
func test_exit_stops_processing_and_resets_gaze() -> void:
	print("TestTriggerLook: test_exit_stops_processing_and_resets_gaze() executing.")
	_trigger._on_body_entered(_player)
	_trigger._current_look_time = 0.3
	_trigger._on_body_exited(_player)

	assert_false(_trigger.is_processing(), "TriggerLook must stop processing on player exit.")
	assert_eq(_trigger._current_look_time, 0.0, "Active look timer must reset to 0.0 upon exit.")


## Verifies full gaze alignment threshold triggers targets and sets has_triggered.
func test_gaze_threshold_triggers_target() -> void:
	print("TestTriggerLook: test_gaze_threshold_triggers_target() executing.")
	_trigger._on_body_entered(_player)

	# Camera at origin looking at (0, 0, -5) along -Z
	_camera.look_at(Vector3(0.0, 0.0, -5.0), Vector3.UP)

	# Accumulate delta to exceed required_look_time (0.5s)
	_trigger._process(0.3)
	assert_eq(_target.power_calls, 0, "Target must not trigger before required time.")

	_trigger._process(0.3)
	assert_eq(_target.power_calls, 1, "Target must receive add_power() when gaze threshold met.")
	assert_true(_trigger._has_triggered, "Trigger must be marked triggered after gaze completion.")
	assert_false(
		_trigger.is_processing(), "TriggerLook must stop processing once fire_once trigger fires."
	)
