class_name TestRotatorComponent
extends GutTest

## The rotator component under test.
var rotator: RotatorComponent


func before_each() -> void:
	print("TestRotatorComponent: before_each() setup starting.")
	rotator = RotatorComponent.new()
	add_child_autofree(rotator)
	print("TestRotatorComponent: before_each() setup completed.")


func test_process_x_axis() -> void:
	print("TestRotatorComponent: test_process_x_axis() running.")
	rotator.axis = 0
	rotator.speed = 1.0

	var initial_rotation: Vector3 = rotator.rotation
	rotator._process(1.0)
	var final_rotation: Vector3 = rotator.rotation

	assert_ne(final_rotation.x, initial_rotation.x, "Rotation X should change.")
	assert_eq(final_rotation.y, initial_rotation.y, "Rotation Y should not change.")
	assert_eq(final_rotation.z, initial_rotation.z, "Rotation Z should not change.")


func test_process_y_axis() -> void:
	print("TestRotatorComponent: test_process_y_axis() running.")
	rotator.axis = 1
	rotator.speed = 1.0

	var initial_rotation: Vector3 = rotator.rotation
	rotator._process(1.0)
	var final_rotation: Vector3 = rotator.rotation

	assert_eq(final_rotation.x, initial_rotation.x, "Rotation X should not change.")
	assert_ne(final_rotation.y, initial_rotation.y, "Rotation Y should change.")
	assert_eq(final_rotation.z, initial_rotation.z, "Rotation Z should not change.")


func test_process_z_axis() -> void:
	print("TestRotatorComponent: test_process_z_axis() running.")
	rotator.axis = 2
	rotator.speed = 1.0

	var initial_rotation: Vector3 = rotator.rotation
	rotator._process(1.0)
	var final_rotation: Vector3 = rotator.rotation

	assert_eq(final_rotation.x, initial_rotation.x, "Rotation X should not change.")
	assert_eq(final_rotation.y, initial_rotation.y, "Rotation Y should not change.")
	assert_ne(final_rotation.z, initial_rotation.z, "Rotation Z should change.")
