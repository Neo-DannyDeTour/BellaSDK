## Unit test suite validating viewport painting raycasts, tool toggles, and UI status.
##
## Tests ray-plane travel distance calculation, brush radius scaling limits, and
## driver binding retrieval using the GUT (Godot Unit Test) framework.
@tool
class_name TestCloudsEditorController
extends GutTest

## The instantiated [CloudsEditorController] editor dock under test.
var _dock: CloudsEditorController

## The mock scene root [Node3D] containing editor test nodes.
var _scene_root: Node3D


## Initial setup executed before each individual test method.
func before_each() -> void:
	print("TestCloudsEditorController: Initializing test harness before test case.")
	_dock = CloudsEditorController.new()
	_scene_root = Node3D.new()
	add_child_autofree(_dock)
	add_child_autofree(_scene_root)


## Teardown executed following each individual test method.
func after_each() -> void:
	print("TestCloudsEditorController: Tearing down test harness after test case.")
	_dock = null
	_scene_root = null


## Validates ray-plane intersection in [method CloudsEditorController.retrieve_travel_distance].
func test_retrieve_travel_distance_downward_ray() -> void:
	print("TestCloudsEditorController: Running test_retrieve_travel_distance_downward_ray.")
	_dock.current_clouds_height = 2000.0

	# Camera at altitude 5000.0 pointing straight down
	var ray_pos: Vector3 = Vector3(0.0, 5000.0, 0.0)
	var ray_dir: Vector3 = Vector3(0.0, -1.0, 0.0)

	var dist: float = _dock.retrieve_travel_distance(ray_pos, ray_dir)
	assert_almost_eq(
		dist, 3000.0, 0.01, "Travel distance from 5000m to 2000m straight down must equal 3000m."
	)


## Validates ray-plane parallel miss in [method CloudsEditorController.retrieve_travel_distance].
func test_retrieve_travel_distance_parallel_ray() -> void:
	print("TestCloudsEditorController: Running test_retrieve_travel_distance_parallel_ray.")
	_dock.current_clouds_height = 2000.0

	# Ray pointing purely horizontally along X-axis
	var ray_pos: Vector3 = Vector3(0.0, 5000.0, 0.0)
	var ray_dir: Vector3 = Vector3(1.0, 0.0, 0.0)

	var dist: float = _dock.retrieve_travel_distance(ray_pos, ray_dir)
	assert_eq(dist, -1.0, "Horizontal ray parallel to cloud plane must return -1.0.")


## Validates ray-plane opposing direction
## in [method CloudsEditorController.retrieve_travel_distance].
func test_retrieve_travel_distance_pointing_away() -> void:
	print("TestCloudsEditorController: Running test_retrieve_travel_distance_pointing_away.")
	_dock.current_clouds_height = 2000.0

	# Camera at 5000.0 pointing upwards away from the cloud layer
	var ray_pos: Vector3 = Vector3(0.0, 5000.0, 0.0)
	var ray_dir: Vector3 = Vector3(0.0, 1.0, 0.0)

	var dist: float = _dock.retrieve_travel_distance(ray_pos, ray_dir)
	assert_eq(dist, -1.0, "Ray pointing upwards away from the target cloud layer must return -1.0.")


## Validates brush scaling in [method CloudsEditorController.scale_drawing_circle_up].
func test_brush_circle_scaling_limits() -> void:
	print("TestCloudsEditorController: Running test_brush_circle_scaling_limits.")
	_dock.draw_scale = 1000.0

	# Scale up by 10%
	_dock.scale_drawing_circle_up()
	assert_almost_eq(
		_dock.draw_scale, 1100.0, 0.01, "Brush scale must increase by 10% when scaled up."
	)

	# Scale down by 10%
	_dock.scale_drawing_circle_down()
	assert_almost_eq(
		_dock.draw_scale, 990.0, 0.01, "Brush scale must decrease by 10% when scaled down."
	)

	# Test lower clamp boundary (100.0m)
	_dock.draw_scale = 105.0
	_dock.scale_drawing_circle_down()
	assert_eq(_dock.draw_scale, 100.0, "Brush scale must not fall below minimum limit of 100.0m.")

	# Test upper clamp boundary (100,000.0m)
	_dock.draw_scale = 95000.0
	_dock.scale_drawing_circle_up()
	assert_eq(_dock.draw_scale, 100000.0, "Brush scale must not exceed maximum limit of 100000.0m.")


## Validates recursive driver discovery in [method CloudsEditorController.retrieve_clouds_driver].
func test_retrieve_clouds_driver_from_hierarchy() -> void:
	print("TestCloudsEditorController: Running test_retrieve_clouds_driver_from_hierarchy.")
	var driver: SunshineCloudsDriverGD = SunshineCloudsDriverGD.new()
	var intermediate_node: Node3D = Node3D.new()

	_scene_root.add_child(intermediate_node)
	intermediate_node.add_child(driver)

	var found_driver: SunshineCloudsDriverGD = _dock.retrieve_clouds_driver(_scene_root)
	assert_not_null(found_driver, "Controller must discover nested SunshineCloudsDriverGD.")
	assert_eq(found_driver, driver, "Discovered driver must match instantiated node.")


## Validates draw mode state reset in [method CloudsEditorController.disable_draw_mode].
func test_disable_draw_mode_resets_state() -> void:
	print("TestCloudsEditorController: Running test_disable_draw_mode_resets_state.")
	_dock.current_draw_mode = CloudsEditorController.DrawingMode.WEIGHT
	_dock.drawing_currently = true
	_dock.draw_inverted = true

	_dock.disable_draw_mode()

	assert_eq(
		_dock.current_draw_mode,
		CloudsEditorController.DrawingMode.NONE,
		"Draw mode must reset to NONE."
	)
	assert_false(_dock.drawing_currently, "Drawing flag must be reset to false.")
	assert_false(_dock.draw_inverted, "Inverted flag must be reset to false.")
