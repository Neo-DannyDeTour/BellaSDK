## Unit tests for [ProceduralBlockout] generator systems.
class_name TestProceduralBlockout
extends GutTest

## Reference to the generator instance being tested.
var generator: Node = null


## Setup method executed prior to each test run.
func before_each() -> void:
	print("TestProceduralBlockout: Setting up generator test instance.")
	var script: GDScript = load("res://levels/procedural_blockout.gd") as GDScript
	generator = script.new() as Node
	if is_instance_valid(generator):
		generator.set("auto_generate_on_ready", false)
		add_child_autofree(generator)


## Teardown method executed after each test run.
func after_each() -> void:
	print("TestProceduralBlockout: Cleaning up generator test instance.")
	generator = null


## Tests initial level generation populating the internal voxel grid.
func test_level_generation_populates_grid() -> void:
	print("TestProceduralBlockout: Executing test_level_generation_populates_grid().")
	if not is_instance_valid(generator):
		assert_true(false, "Generator is invalid")
		return
	generator.set("floor_count", 2)
	generator.set("rooms_per_floor", 2)
	generator.call("generate_level")

	var grid: Dictionary = generator.get("_grid") as Dictionary
	var room_count: int = 0
	for coord: Vector3i in grid:
		if int(generator.call("get_cell", coord)) == 1:
			room_count += 1

	assert_gt(room_count, 0, "Grid should contain room cells after level generation.")


## Tests radial room shape selection with high radial ratio.
func test_radial_room_shape_selection() -> void:
	print("TestProceduralBlockout: Executing test_radial_room_shape_selection().")
	if not is_instance_valid(generator):
		assert_true(false, "Generator is invalid")
		return
	generator.set("radial_room_ratio", 1.0)
	var shape: int = int(generator.call("_select_room_shape"))
	assert_eq(shape, 4, "Room shape should be RADIAL (4) when radial_room_ratio is 1.0.")


## Tests ceiling and roof node container generation.
func test_ceilings_and_roofs_generation() -> void:
	print("TestProceduralBlockout: Executing test_ceilings_and_roofs_generation().")
	if not is_instance_valid(generator):
		assert_true(false, "Generator is invalid")
		return
	generator.set("enable_roofs_and_ceilings", true)
	generator.call("generate_level")

	var ceiling_container: Node3D = generator.get_node_or_null("CeilingContainer") as Node3D
	assert_not_null(ceiling_container, "CeilingContainer node should exist in generator.")
	if ceiling_container:
		assert_gt(
			ceiling_container.get_child_count(),
			0,
			"CeilingContainer should host generated ceiling/roof geometry."
		)


## Tests nested room inner volume generation in large room halls.
func test_nested_rooms_generation() -> void:
	print("TestProceduralBlockout: Executing test_nested_rooms_generation().")
	if not is_instance_valid(generator):
		assert_true(false, "Generator is invalid")
		return
	generator.set("enable_nested_rooms", true)
	generator.set("min_room_size", 8)
	generator.set("max_room_size", 10)
	generator.call("generate_level")

	var nested_container: Node3D = generator.get_node_or_null("NestedContainer") as Node3D
	assert_not_null(nested_container, "NestedContainer node should exist in generator.")


## Tests parkour elements container placement and cell type assignment.
func test_parkour_elements_generation() -> void:
	print("TestProceduralBlockout: Executing test_parkour_elements_generation().")
	if not is_instance_valid(generator):
		assert_true(false, "Generator is invalid")
		return
	generator.set("enable_parkour_elements", true)
	generator.call("generate_level")

	var parkour_container: Node3D = generator.get_node_or_null("ParkourContainer") as Node3D
	assert_not_null(parkour_container, "ParkourContainer node should exist in generator.")
	if parkour_container:
		assert_gt(
			parkour_container.get_child_count(),
			0,
			"ParkourContainer should host spawned traversal elements."
		)


## Tests inner area bounding box room validation helper.
func test_inner_area_fully_in_room() -> void:
	print("TestProceduralBlockout: Executing test_inner_area_fully_in_room().")
	if not is_instance_valid(generator):
		assert_true(false, "Generator is invalid")
		return
	var grid: Dictionary = generator.get("_grid") as Dictionary
	grid[Vector3i(2, 0, 2)] = 1
	grid[Vector3i(3, 0, 2)] = 1
	grid[Vector3i(2, 0, 3)] = 1
	grid[Vector3i(3, 0, 3)] = 1

	var is_valid: bool = bool(generator.call("_is_inner_area_fully_in_room", 2, 3, 2, 3, 0))
	assert_true(is_valid, "Inner area surrounded by room cells should be valid.")


## Tests grid to world coordinate transformation calculation.
func test_grid_to_world_conversion() -> void:
	print("TestProceduralBlockout: Executing test_grid_to_world_conversion().")
	if not is_instance_valid(generator):
		assert_true(false, "Generator is invalid")
		return
	generator.set("cell_size", 2.0)
	var grid_coord: Vector3i = Vector3i(3, 2, 5)
	var expected_world: Vector3 = Vector3(6.0, 4.0, 10.0)
	var actual_world: Vector3 = generator.call("grid_to_world", grid_coord) as Vector3

	assert_eq(actual_world, expected_world, "Grid coordinate conversion to world should match.")
