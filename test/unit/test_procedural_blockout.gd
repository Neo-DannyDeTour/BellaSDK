## Unit tests for [ProceduralBlockout] generator systems.
class_name TestProceduralBlockout
extends GutTest

## Reference to the generator instance being tested.
var generator: ProceduralBlockout = null


## Setup method executed prior to each test run.
func before_each() -> void:
	print("TestProceduralBlockout: Setting up generator test instance.")
	generator = ProceduralBlockout.new()
	generator.auto_generate_on_ready = false
	add_child_autofree(generator)


## Teardown method executed after each test run.
func after_each() -> void:
	print("TestProceduralBlockout: Cleaning up generator test instance.")
	generator = null


## Tests initial level generation populating the internal voxel grid.
func test_level_generation_populates_grid() -> void:
	print("TestProceduralBlockout: Executing test_level_generation_populates_grid().")
	generator.floor_count = 2
	generator.rooms_per_floor = 2
	generator.generate_level()

	var room_count: int = 0
	for coord: Vector3i in generator._grid:
		if generator.get_cell(coord) == ProceduralBlockout.CellType.ROOM:
			room_count += 1

	assert_gt(room_count, 0, "Grid should contain room cells after level generation.")


## Tests radial room shape selection with high radial ratio.
func test_radial_room_shape_selection() -> void:
	print("TestProceduralBlockout: Executing test_radial_room_shape_selection().")
	generator.radial_room_ratio = 1.0
	var shape: ProceduralBlockout.RoomShape = generator._select_room_shape()
	assert_eq(
		shape,
		ProceduralBlockout.RoomShape.RADIAL,
		"Room shape should be RADIAL when radial_room_ratio is 1.0."
	)


## Tests ceiling and roof node container generation.
func test_ceilings_and_roofs_generation() -> void:
	print("TestProceduralBlockout: Executing test_ceilings_and_roofs_generation().")
	generator.enable_roofs_and_ceilings = true
	generator.generate_level()

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
	generator.enable_nested_rooms = true
	generator.min_room_size = 8
	generator.max_room_size = 10
	generator.generate_level()

	var nested_container: Node3D = generator.get_node_or_null("NestedContainer") as Node3D
	assert_not_null(nested_container, "NestedContainer node should exist in generator.")


## Tests parkour elements container placement and cell type assignment.
func test_parkour_elements_generation() -> void:
	print("TestProceduralBlockout: Executing test_parkour_elements_generation().")
	generator.enable_parkour_elements = true
	generator.generate_level()

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
	generator._grid[Vector3i(2, 0, 2)] = ProceduralBlockout.CellType.ROOM
	generator._grid[Vector3i(3, 0, 2)] = ProceduralBlockout.CellType.ROOM
	generator._grid[Vector3i(2, 0, 3)] = ProceduralBlockout.CellType.ROOM
	generator._grid[Vector3i(3, 0, 3)] = ProceduralBlockout.CellType.ROOM

	var is_valid: bool = generator._is_inner_area_fully_in_room(2, 3, 2, 3, 0)
	assert_true(is_valid, "Inner area surrounded by room cells should be valid.")


## Tests grid to world coordinate transformation calculation.
func test_grid_to_world_conversion() -> void:
	print("TestProceduralBlockout: Executing test_grid_to_world_conversion().")
	generator.cell_size = 2.0
	var grid_coord: Vector3i = Vector3i(3, 2, 5)
	var expected_world: Vector3 = Vector3(6.0, 4.0, 10.0)
	var actual_world: Vector3 = generator.grid_to_world(grid_coord)

	assert_eq(actual_world, expected_world, "Grid coordinate conversion to world should match.")
