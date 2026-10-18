## Unit tests for Checkpoint trigger and visualizer system.
class_name TestCheckpoint
extends GutTest

## Target Checkpoint instance being tested.
var _checkpoint: Checkpoint = null


## Sets up clean Checkpoint instance and test environment.
func before_each() -> void:
	print("TestCheckpoint: before_each() setup started.")
	_checkpoint = Checkpoint.new()
	add_child_autofree(_checkpoint)


## Tears down Checkpoint instance references.
func after_each() -> void:
	print("TestCheckpoint: after_each() cleanup.")
	_checkpoint = null


## Verifies checkpoint group registration and initial inactive state.
func test_initial_state() -> void:
	print("TestCheckpoint: test_initial_state() called.")
	assert_false(_checkpoint.is_activated, "Checkpoint should initially be inactive.")
	assert_true(
		_checkpoint.is_in_group(&"checkpoints"),
		"Checkpoint should be added to 'checkpoints' group."
	)


## Verifies checkpoint activation state transitions and save manager position updates.
func test_activate_checkpoint() -> void:
	print("TestCheckpoint: test_activate_checkpoint() called.")
	_checkpoint.global_position = Vector3(10.0, 5.0, -20.0)
	_checkpoint.activate_checkpoint()

	assert_true(_checkpoint.is_activated, "Checkpoint should be marked as activated.")
	assert_eq(
		SaveManager.last_checkpoint_pos,
		Vector3(10.0, 5.0, -20.0),
		"SaveManager.last_checkpoint_pos should update to checkpoint global position."
	)
	assert_eq(
		_checkpoint.label_text, "Checkpoint Activated", "Label text should update upon activation."
	)


## Verifies checkpoint deactivation restores initial label and speed properties.
func test_deactivate_checkpoint() -> void:
	print("TestCheckpoint: test_deactivate_checkpoint() called.")
	_checkpoint.label_text = "Stage 1"
	_checkpoint._ready()
	_checkpoint.activate_checkpoint()

	_checkpoint.deactivate_checkpoint()

	assert_false(_checkpoint.is_activated, "Checkpoint should be marked as deactivated.")
	assert_eq(
		_checkpoint.label_text,
		"Stage 1",
		"Label text should revert to original value upon deactivation."
	)


## Verifies collision shape generation based on configured shape type.
func test_trigger_shape_box() -> void:
	print("TestCheckpoint: test_trigger_shape_box() called.")
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	_checkpoint.add_child(col_shape)

	_checkpoint.shape_type = EditorTriggerVisualizer.ShapeType.BOX
	_checkpoint.trigger_size = Vector3(4.0, 4.0, 4.0)
	_checkpoint._update_trigger_shape()

	assert_true(col_shape.shape is BoxShape3D, "Shape should be BoxShape3D.")
	var box: BoxShape3D = col_shape.shape as BoxShape3D
	assert_eq(box.size, Vector3(4.0, 4.0, 4.0), "BoxShape3D size should match trigger_size.")
