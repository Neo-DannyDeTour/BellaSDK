## Unit test suite validating ConveyorBelt physics velocity and size updates.
extends GutTest

const CONVEYOR_BELT_SCRIPT: GDScript = preload("res://interactables/conveyor_belt.gd")

## ConveyorBelt StaticBody3D instance under test.
var _belt: StaticBody3D

## MeshInstance3D child node for visual surface.
var _mesh_inst: MeshInstance3D

## CollisionShape3D child node for physical bounds.
var _col_shape: CollisionShape3D


## Instantiates ConveyorBelt with mesh and collision children before tests.
func before_each() -> void:
	print("Setting up ConveyorBelt instance for testing.")
	_belt = CONVEYOR_BELT_SCRIPT.new() as StaticBody3D

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "MeshInstance3D"
	var box_mesh: BoxMesh = BoxMesh.new()
	_mesh_inst.mesh = box_mesh
	_belt.add_child(_mesh_inst)

	_col_shape = CollisionShape3D.new()
	_col_shape.name = "CollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	_col_shape.shape = box_shape
	_belt.add_child(_col_shape)

	add_child_autofree(_belt)


## Cleans up ConveyorBelt instance after test execution.
func after_each() -> void:
	print("Tearing down ConveyorBelt test instance.")
	_belt = null
	_mesh_inst = null
	_col_shape = null


## Verifies default linear velocity calculation based on move_direction and speed.
func test_physics_linear_velocity_calculation() -> void:
	print("Testing ConveyorBelt constant_linear_velocity calculation.")
	_belt.set("move_direction", Vector3(1.0, 0.0, 0.0))
	_belt.set("speed", 5.0)
	_belt.call("_update_physics")

	assert_eq(
		_belt.constant_linear_velocity,
		Vector3(5.0, 0.0, 0.0),
		"Belt constant_linear_velocity should match move_direction * speed."
	)


## Verifies diagonal move direction normalization in linear velocity.
func test_physics_diagonal_move_direction() -> void:
	print("Testing ConveyorBelt diagonal move direction velocity.")
	_belt.set("move_direction", Vector3(3.0, 0.0, 4.0))
	_belt.set("speed", 10.0)
	_belt.call("_update_physics")

	assert_almost_eq(
		_belt.constant_linear_velocity.length(),
		10.0,
		0.001,
		"Velocity magnitude should match set speed regardless of direction scale."
	)


## Verifies collision shape size update when conveyor_size property changes.
func test_conveyor_size_updates_collision_shape() -> void:
	print("Testing ConveyorBelt size update for collision shape.")
	_belt.set("conveyor_size", Vector2(4.0, 12.0))
	_belt.call("_update_size")

	var box_shape: BoxShape3D = _col_shape.shape as BoxShape3D
	assert_eq(
		box_shape.size,
		Vector3(4.0, 0.1, 12.0),
		"Collision box shape size should update to match conveyor_size."
	)
