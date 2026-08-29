## Unit test suite validating scene driver state, light packing, and coordinate wrapping.
##
## Tests coordinate wrapping bounds, light buffer std140 array packing, and
## [SunshineCloudsGD] resource integration using the GUT (Godot Unit Test) framework.
@tool
class_name TestSunshineCloudsDriver
extends GutTest

## The instantiated [SunshineCloudsDriverGD] driver node under test.
var _driver: SunshineCloudsDriverGD

## The mock [SunshineCloudsGD] compositor resource under test.
var _clouds_res


## Initial setup executed before each individual test method.
func before_each() -> void:
	print("TestSunshineCloudsDriver: Initializing test harness before test case.")
	_driver = SunshineCloudsDriverGD.new()
	_clouds_res = load("res://addons/SunshineClouds2/SunshineClouds.gd").new()
	_driver.clouds_resource = _clouds_res
	add_child_autofree(_driver)


## Teardown executed following each individual test method.
func after_each() -> void:
	print("TestSunshineCloudsDriver: Tearing down test harness after test case.")
	_driver = null
	_clouds_res = null


## Validates that [method SunshineCloudsDriverGD.wrap_vector] wraps coordinates across boundaries.
func test_wrap_vector_within_domain() -> void:
	print("TestSunshineCloudsDriver: Running test_wrap_vector_within_domain.")
	var domain: float = 1000.0

	# Test values inside bounds
	var in_bounds: Vector3 = Vector3(500.0, -300.0, 100.0)
	var wrapped_in: Vector3 = _driver.wrap_vector(in_bounds, domain)
	assert_almost_eq(wrapped_in.x, 500.0, 0.01, "In-bounds X should not change.")
	assert_almost_eq(wrapped_in.y, -300.0, 0.01, "In-bounds Y should not change.")
	assert_almost_eq(wrapped_in.z, 100.0, 0.01, "In-bounds Z should not change.")

	# Test values outside positive bound (exceeds +1000.0)
	var out_pos: Vector3 = Vector3(1200.0, 0.0, 0.0)
	var wrapped_pos: Vector3 = _driver.wrap_vector(out_pos, domain)
	assert_almost_eq(
		wrapped_pos.x, -800.0, 0.01, "Positive out-of-bounds X must wrap to negative side."
	)

	# Test values outside negative bound (below -1000.0)
	var out_neg: Vector3 = Vector3(0.0, 0.0, -1400.0)
	var wrapped_neg: Vector3 = _driver.wrap_vector(out_neg, domain)
	assert_almost_eq(
		wrapped_neg.z, 600.0, 0.01, "Negative out-of-bounds Z must wrap to positive side."
	)


## Validates that [method SunshineCloudsDriverGD.update_wind_direction] normalizes vectors.
func test_update_wind_direction_normalization() -> void:
	print("TestSunshineCloudsDriver: Running test_update_wind_direction_normalization.")
	var input_dir: Vector3 = Vector3(10.0, 0.0, 10.0)
	_driver.update_wind_direction(input_dir)

	assert_almost_eq(
		_driver.wind_direction.length(), 1.0, 0.001, "Wind direction vector must be unit length."
	)
	assert_almost_eq(
		_driver.wind_direction.x, sqrt(0.5), 0.001, "Wind direction X must be normalized."
	)
	assert_almost_eq(
		_driver.wind_direction.z, sqrt(0.5), 0.001, "Wind direction Z must be normalized."
	)


## Validates std140 directional light packing in
## [method SunshineCloudsDriverGD.retrieve_texture_data].
func test_directional_light_data_packing() -> void:
	print("TestSunshineCloudsDriver: Running test_directional_light_data_packing.")
	var dir_light: DirectionalLight3D = DirectionalLight3D.new()
	dir_light.light_color = Color(1.0, 0.5, 0.25, 1.0)
	dir_light.light_energy = 2.5
	add_child_autofree(dir_light)

	_driver.tracked_directional_lights = [dir_light]
	_driver.tracked_directional_light_shadow_steps = [16]
	_driver.directional_light_power_multiplier = 1.0
	_driver.retrieve_texture_data()

	assert_eq(
		_clouds_res.directional_lights_data.size(),
		2,
		"One directional light must produce exactly two Vector4 elements."
	)

	# Element 0: Look direction (xyz) and Shadow Steps (w)
	var look_dir: Vector3 = dir_light.global_transform.basis.z.normalized()
	var elem_0: Vector4 = _clouds_res.directional_lights_data[0]
	assert_almost_eq(elem_0.x, look_dir.x, 0.01, "Element 0.x must store light direction X.")
	assert_almost_eq(elem_0.y, look_dir.y, 0.01, "Element 0.y must store light direction Y.")
	assert_almost_eq(elem_0.z, look_dir.z, 0.01, "Element 0.z must store light direction Z.")
	assert_almost_eq(elem_0.w, 16.0, 0.01, "Element 0.w must store shadow steps count.")

	# Element 1: Light color (rgb) and Intensity (a)
	var elem_1: Vector4 = _clouds_res.directional_lights_data[1]
	assert_almost_eq(elem_1.x, 1.0, 0.01, "Element 1.x must store light red color.")
	assert_almost_eq(elem_1.y, 0.5, 0.01, "Element 1.y must store light green color.")
	assert_almost_eq(elem_1.z, 0.25, 0.01, "Element 1.z must store light blue color.")
	assert_almost_eq(elem_1.w, 2.5, 0.01, "Element 1.w must store snapped light energy.")


## Validates std140 point effector packing in [method SunshineCloudsDriverGD.retrieve_texture_data].
func test_point_effector_data_packing() -> void:
	print("TestSunshineCloudsDriver: Running test_point_effector_data_packing.")
	var effector: SunshineCloudsEffector = SunshineCloudsEffector.new()
	effector.position = Vector3(100.0, 2000.0, -300.0)
	effector.radius = 1500.0
	effector.power = -2.5
	effector.attenuation = 1.8
	add_child_autofree(effector)

	_driver.tracked_point_effectors = [effector]
	_driver.retrieve_texture_data()

	assert_eq(
		_clouds_res.point_effector_data.size(),
		2,
		"One point effector must produce exactly two Vector4 elements."
	)

	# Element 0: Position (xyz) and Radius (w)
	var elem_0: Vector4 = _clouds_res.point_effector_data[0]
	assert_almost_eq(elem_0.x, 100.0, 0.01, "Element 0.x must match effector position X.")
	assert_almost_eq(elem_0.y, 2000.0, 0.01, "Element 0.y must match effector position Y.")
	assert_almost_eq(elem_0.z, -300.0, 0.01, "Element 0.z must match effector position Z.")
	assert_almost_eq(elem_0.w, 1500.0, 0.01, "Element 0.w must match effector radius.")

	# Element 1: Power (x) and Attenuation (y)
	var elem_1: Vector4 = _clouds_res.point_effector_data[1]
	assert_almost_eq(elem_1.x, -2.5, 0.01, "Element 1.x must match effector power.")
	assert_almost_eq(elem_1.y, 1.8, 0.01, "Element 1.y must match effector attenuation.")


## Validates recursive discovery of [WorldEnvironment] nodes in the scene tree.
func test_recursively_find_env() -> void:
	print("TestSunshineCloudsDriver: Running test_recursively_find_env.")
	var parent_node: Node3D = Node3D.new()
	var branch_node: Node3D = Node3D.new()
	var env_node: WorldEnvironment = WorldEnvironment.new()

	parent_node.add_child(branch_node)
	branch_node.add_child(env_node)
	add_child_autofree(parent_node)

	var found_env: WorldEnvironment = _driver.recursively_find_env(parent_node)
	assert_not_null(found_env, "Driver must locate nested WorldEnvironment instance.")
	assert_eq(found_env, env_node, "Located environment must match instantiated child.")
