## Unit tests for the RotatorComponent class.
class_name TestRotatorComponent
extends GutTest

## The loaded script reference for [RotatorComponent].
const ROTATOR_COMP_SCRIPT: GDScript = preload("res://shared/rotator_component.gd")

## The instance of the [RotatorComponent] being tested.
var rotator_comp: Variant = null
## Dummy parent node for the rotator component to act upon.
var parent_node: Node3D = null


## Sets up the test environment before each test.
func before_each() -> void:
	print("TestRotatorComponent: before_each() setup.")
	parent_node = Node3D.new()
	add_child_autofree(parent_node)

	rotator_comp = ROTATOR_COMP_SCRIPT.new()
	rotator_comp.speed = 10.0
	parent_node.add_child(rotator_comp)


## Verifies rotation occurs correctly around the X axis.
func test_rotate_x_axis() -> void:
	print("TestRotatorComponent: test_rotate_x_axis() called.")
	rotator_comp.axis = 0  # X axis

	# Simulate process tick
	rotator_comp._process(0.1)

	var rotation: Vector3 = parent_node.rotation
	assert_almost_eq(rotation.x, 1.0, 0.01, "Rotation should occur around X axis.")
	assert_eq(rotation.y, 0.0, "Rotation should not occur around Y axis.")
	assert_eq(rotation.z, 0.0, "Rotation should not occur around Z axis.")


## Verifies rotation occurs correctly around the Y axis.
func test_rotate_y_axis() -> void:
	print("TestRotatorComponent: test_rotate_y_axis() called.")
	rotator_comp.axis = 1  # Y axis

	# Simulate process tick
	rotator_comp._process(0.1)

	var rotation: Vector3 = parent_node.rotation
	assert_eq(rotation.x, 0.0, "Rotation should not occur around X axis.")
	assert_almost_eq(rotation.y, 1.0, 0.01, "Rotation should occur around Y axis.")
	assert_eq(rotation.z, 0.0, "Rotation should not occur around Z axis.")


## Verifies rotation occurs correctly around the Z axis.
func test_rotate_z_axis() -> void:
	print("TestRotatorComponent: test_rotate_z_axis() called.")
	rotator_comp.axis = 2  # Z axis

	# Simulate process tick
	rotator_comp._process(0.1)

	var rotation: Vector3 = parent_node.rotation
	assert_eq(rotation.x, 0.0, "Rotation should not occur around X axis.")
	assert_eq(rotation.y, 0.0, "Rotation should not occur around Y axis.")
	assert_almost_eq(rotation.z, 1.0, 0.01, "Rotation should occur around Z axis.")
