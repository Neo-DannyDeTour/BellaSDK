## Unit tests for [EventSequenceTrigger] validating sequential, parallel, and WAIT_LOOK steps.
class_name TestEventSequenceTrigger
extends GutTest


## Mock target class recording method invocations.
class MockSequenceTarget:
	extends Node3D

	## Number of times test_action was called.
	var action_calls: int = 0

	## Receives dispatched step action.
	func test_action() -> void:
		action_calls += 1


## The [EventSequenceTrigger] instance under test.
var _trigger: EventSequenceTrigger = null

## The mock player activator node.
var _player: CharacterBody3D = null

## The camera simulating viewport gaze.
var _camera: Camera3D = null

## The look target node.
var _look_marker: Marker3D = null

## The action target node.
var _action_target: MockSequenceTarget = null


## Prepares test nodes and wiring before each test execution.
func before_each() -> void:
	print("TestEventSequenceTrigger: Setting up test environment.")
	_trigger = EventSequenceTrigger.new()

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(10.0, 10.0, 10.0)
	col.shape = box
	_trigger.add_child(col)

	_look_marker = Marker3D.new()
	_look_marker.name = "LookMarker"
	_look_marker.position = Vector3(0.0, 0.0, -10.0)
	_trigger.add_child(_look_marker)

	_action_target = MockSequenceTarget.new()
	_action_target.name = "ActionTarget"
	_trigger.add_child(_action_target)

	add_child_autoqfree(_trigger)

	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.collision_layer = 2
	_player.position = Vector3(0.0, 0.0, 0.0)
	add_child_autoqfree(_player)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.position = Vector3(0.0, 0.0, 0.0)
	_camera.current = true
	add_child_autoqfree(_camera)


## Clears local instance references after each test execution.
func after_each() -> void:
	print("TestEventSequenceTrigger: Tearing down test environment.")
	_trigger = null
	_player = null
	_camera = null
	_look_marker = null
	_action_target = null


## Verifies WAIT_LOOK step holds sequence progression until gaze threshold is met.
func test_wait_look_step_execution() -> void:
	print("TestEventSequenceTrigger: test_wait_look_step_execution() executing.")
	var look_step: EventStep = EventStep.new()
	look_step.step_type = EventStep.StepType.CALL_METHOD
	look_step.exec_mode = EventStep.ExecMode.WAIT_LOOK
	look_step.target_path = NodePath("LookMarker")
	look_step.look_time = 0.1
	look_step.look_tolerance = 0.9

	var action_step: EventStep = EventStep.new()
	action_step.step_type = EventStep.StepType.CALL_METHOD
	action_step.exec_mode = EventStep.ExecMode.SEQUENTIAL
	action_step.target_path = NodePath("ActionTarget")
	action_step.method_name = &"test_action"

	_trigger.steps = [look_step, action_step]

	# Point camera away initially
	_camera.look_at(Vector3(10.0, 0.0, 0.0), Vector3.UP)

	# Start sequence in background
	_trigger.trigger_sequence(_player)
	await wait_process_frames(2)

	assert_eq(_action_target.action_calls, 0, "Action step must not run while looking away.")

	# Turn camera to face look marker
	_camera.look_at(Vector3(0.0, 0.0, -10.0), Vector3.UP)

	# Await duration to satisfy look duration (0.1s)
	await wait_seconds(0.25)

	assert_eq(
		_action_target.action_calls,
		1,
		"Action step must execute once gaze duration threshold is met."
	)


## Verifies trigger volume properties sync to collision shape and visualizer.
func test_inspector_bounds_and_visualizer_synchronization() -> void:
	print("TestEventSequenceTrigger: test_inspector_bounds_and_visualizer_synchronization().")
	assert_true(
		_trigger is BaseTriggerArea3D, "EventSequenceTrigger must inherit BaseTriggerArea3D."
	)
	_trigger.trigger_size = Vector3(4.0, 5.0, 6.0)
	_trigger.trigger_offset = Vector3(1.0, 2.0, 3.0)

	var col: CollisionShape3D = _trigger.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_not_null(col, "CollisionShape3D must be present.")
	assert_true(col.shape is BoxShape3D, "Shape must be BoxShape3D.")
	var box: BoxShape3D = col.shape as BoxShape3D
	assert_eq(box.size, Vector3(4.0, 5.0, 6.0), "BoxShape3D size must match trigger_size.")
	assert_eq(col.position, Vector3(1.0, 2.0, 3.0), "CollisionShape3D position must match offset.")

	var visual: EditorTriggerVisualizer = (
		_trigger.get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	assert_not_null(visual, "EditorTriggerVisualizer must be present.")
	assert_eq(visual.trigger_size, Vector3(4.0, 5.0, 6.0), "Visualizer size must match.")
	assert_eq(visual.position, Vector3(1.0, 2.0, 3.0), "Visualizer position must match.")


## Verifies cutscene step types (LOOK_AT, MOVE_TOWARDS, MOVE_OFFSET, CAMERA_TILT, CAMERA_FOV).
func test_cutscene_steps_execution() -> void:
	print("TestEventSequenceTrigger: test_cutscene_steps_execution() executing.")
	_player.position = Vector3(10.0, 0.0, 0.0)
	_camera.position = Vector3(10.0, 1.5, 0.0)
	_look_marker.position = Vector3(0.0, 1.5, 0.0)
	_action_target.position = Vector3(0.0, -3.7, 0.0)

	var step_look: EventStep = EventStep.new()
	step_look.step_type = EventStep.StepType.LOOK_AT
	step_look.exec_mode = EventStep.ExecMode.PARALLEL
	step_look.target_path = NodePath("LookMarker")
	step_look.duration = 0.0

	var step_move: EventStep = EventStep.new()
	step_move.step_type = EventStep.StepType.MOVE_TOWARDS
	step_move.exec_mode = EventStep.ExecMode.SEQUENTIAL
	step_move.target_path = NodePath("LookMarker")
	step_move.distance = 3.0
	step_move.duration = 0.05

	var step_raise: EventStep = EventStep.new()
	step_raise.step_type = EventStep.StepType.MOVE_OFFSET
	step_raise.exec_mode = EventStep.ExecMode.SEQUENTIAL
	step_raise.target_path = NodePath("ActionTarget")
	step_raise.offset_vector = Vector3(0.0, 3.7, 0.0)
	step_raise.duration = 0.05

	var step_tilt: EventStep = EventStep.new()
	step_tilt.step_type = EventStep.StepType.CAMERA_TILT
	step_tilt.exec_mode = EventStep.ExecMode.PARALLEL
	step_tilt.angle_deg = 20.0
	step_tilt.duration = 0.0

	var step_fov: EventStep = EventStep.new()
	step_fov.step_type = EventStep.StepType.CAMERA_FOV
	step_fov.exec_mode = EventStep.ExecMode.PARALLEL
	step_fov.angle_deg = 110.0
	step_fov.duration = 0.0

	var step_tp: EventStep = EventStep.new()
	step_tp.step_type = EventStep.StepType.TELEPORT_PLAYER
	step_tp.exec_mode = EventStep.ExecMode.SEQUENTIAL
	step_tp.target_path = NodePath("")
	step_tp.delay = 0.05

	_trigger.steps = [step_look, step_move, step_raise, step_tilt, step_fov, step_tp]
	_trigger.trigger_sequence(_player)

	await wait_seconds(0.08)
	assert_almost_eq(
		_player.global_position.x, 7.0, 0.2, "Player must move 3m towards LookMarker along -X."
	)

	await wait_seconds(0.15)
	assert_almost_eq(
		_action_target.global_position.y, 0.0, 0.1, "ActionTarget must raise by +3.7m on Y axis."
	)
	assert_almost_eq(
		rad_to_deg(_camera.rotation.z), 20.0, 0.5, "Camera must tilt to 20 degrees Dutch angle."
	)
	assert_almost_eq(_camera.fov, 110.0, 0.5, "Camera FOV must expand to 110 degrees.")
	assert_almost_eq(
		_player.global_position.x,
		10.0,
		0.1,
		"Player must teleport back to entry position (10, 0, 0)."
	)
