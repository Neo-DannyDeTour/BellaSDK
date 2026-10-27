## Unit tests for [SunshineCloudsDriverGD] verifying the single-source-of-truth enabled
## formula, quality tier parameters (including shadow gating), and weather preset transitions.
class_name TestSunshineCloudsDriver
extends GutTest


## Lightweight mock overriding RD compute lifecycle methods for headless unit testing.
class MockSunshineClouds:
	extends SunshineCloudsGD

	var refresh_compute_count: int = 0

	func initialize_compute() -> void:
		pass

	func clear_compute() -> void:
		pass

	func refresh_compute() -> void:
		refresh_compute_count += 1
		super.refresh_compute()


var _driver: SunshineCloudsDriverGD = null
var _mock_clouds: MockSunshineClouds = null


## Creates a fresh driver and mock clouds resource before each test.
func before_each() -> void:
	print("TestSunshineCloudsDriver: before_each() setup.")
	_mock_clouds = MockSunshineClouds.new()
	_driver = SunshineCloudsDriverGD.new()
	_driver.clouds_resource = _mock_clouds
	add_child_autofree(_driver)


## Verifies that the driver joins the &"sunshine_clouds" group upon entering the tree.
func test_driver_joins_sunshine_clouds_group() -> void:
	print("TestSunshineCloudsDriver: test_driver_joins_sunshine_clouds_group() called.")
	assert_true(
		_driver.is_in_group(&"sunshine_clouds"),
		"Driver must join the 'sunshine_clouds' group in _enter_tree()."
	)


## Verifies the enabled formula across all visibility x tier x diorama_suspended combinations.
func test_enabled_formula_all_combinations() -> void:
	print("TestSunshineCloudsDriver: test_enabled_formula_all_combinations() called.")
	var tiers: Array[StringName] = [&"Off", &"Low", &"Medium", &"High"]
	var vis_states: Array[bool] = [true, false]
	var suspend_states: Array[bool] = [false, true]

	for vis: bool in vis_states:
		_driver.visible = vis
		for tier: StringName in tiers:
			_driver.set_quality_tier(tier)
			for susp: bool in suspend_states:
				_driver.set_suspended(susp)
				var expected: bool = vis and (tier != &"Off") and (not susp)
				var label: String = (
					"vis=%s, tier=%s, susp=%s -> expected=%s" % [vis, tier, susp, expected]
				)
				assert_eq(_mock_clouds.enabled, expected, label)
				assert_eq(_driver.is_processing(), expected, "process state: " + label)


## Verifies that each quality tier writes
## the exact spec values (including shadow_steps) into the resource.
func test_tier_values_applied_to_resource() -> void:
	print("TestSunshineCloudsDriver: test_tier_values_applied_to_resource() called.")
	_driver.visible = true
	_driver.set_suspended(false)

	_driver.set_quality_tier(&"Low")
	assert_true(_mock_clouds.enabled, "Low tier should enable clouds.")
	assert_eq(_mock_clouds.resolution_scale, 2, "Low tier resolution_scale should be 2 (Quarter).")
	assert_eq(_mock_clouds.max_step_count, 96.0, "Low tier max_step_count should be 96.")
	assert_eq(_mock_clouds.max_lighting_steps, 8.0, "Low tier max_lighting_steps should be 8.")
	assert_eq(_mock_clouds.shadow_steps, 0, "Low tier shadow_steps should be 0 (off).")

	_driver.set_quality_tier(&"Medium")
	assert_true(_mock_clouds.enabled, "Medium tier should enable clouds.")
	assert_eq(_mock_clouds.resolution_scale, 1, "Medium tier resolution_scale should be 1 (Half).")
	assert_eq(_mock_clouds.max_step_count, 160.0, "Medium tier max_step_count should be 160.")
	assert_eq(_mock_clouds.max_lighting_steps, 16.0, "Medium tier max_lighting_steps should be 16.")
	assert_eq(_mock_clouds.shadow_steps, 4, "Medium tier shadow_steps should be 4.")

	_driver.set_quality_tier(&"High")
	assert_true(_mock_clouds.enabled, "High tier should enable clouds.")
	assert_eq(_mock_clouds.resolution_scale, 1, "High tier resolution_scale should be 1 (Half).")
	assert_eq(_mock_clouds.max_step_count, 300.0, "High tier max_step_count should be 300.")
	assert_eq(_mock_clouds.max_lighting_steps, 32.0, "High tier max_lighting_steps should be 32.")
	assert_eq(_mock_clouds.shadow_steps, 6, "High tier shadow_steps should be 6.")

	_driver.set_quality_tier(&"Off")
	assert_false(_mock_clouds.enabled, "Off tier should disable clouds.")


## Verifies immediate weather transition (duration = 0.0) and optional height_gradient swap.
func test_weather_transition_immediate_and_gradient_swap() -> void:
	print("TestSunshineCloudsDriver: test_weather_transition_immediate_and_gradient_swap() called.")
	var storm: SunshineCloudsWeather = SunshineCloudsWeather.new()
	storm.clouds_coverage = 1.0
	storm.clouds_density = 0.45
	storm.atmospheric_density = 1.25
	storm.extra_large_structures_wind_speed = 280.0
	storm.large_structures_wind_speed = 200.0
	storm.medium_structures_wind_speed = 85.0
	storm.small_structures_wind_speed = 28.0

	_driver.transition_to(storm, 0.0)

	assert_almost_eq(_mock_clouds.clouds_coverage, 1.0, 0.001, "Coverage should match storm.")
	assert_almost_eq(_mock_clouds.clouds_density, 0.45, 0.001, "Density should match storm.")
	assert_almost_eq(
		_mock_clouds.atmospheric_density, 1.25, 0.001, "Atmospheric density should match storm."
	)
	assert_almost_eq(_driver.extra_large_structures_wind_speed, 280.0, 0.001, "XL wind speed.")
	assert_almost_eq(_driver.large_structures_wind_speed, 200.0, 0.001, "L wind speed.")
	assert_almost_eq(_driver.medium_structures_wind_speed, 85.0, 0.001, "M wind speed.")
	assert_almost_eq(_driver.small_structures_wind_speed, 28.0, 0.001, "S wind speed.")
	assert_eq(
		_mock_clouds.refresh_compute_count,
		0,
		"Null height_gradient must not trigger refresh_compute()."
	)

	var grad_tex: GradientTexture1D = GradientTexture1D.new()
	storm.height_gradient = grad_tex
	_driver.transition_to(storm, 0.0)
	assert_same(_mock_clouds.height_gradient, grad_tex, "New height_gradient should be assigned.")
	assert_eq(
		_mock_clouds.refresh_compute_count,
		1,
		"Changing height_gradient must trigger refresh_compute() exactly once."
	)


## Verifies that starting a new tweened weather transition kills the previous active tween.
func test_weather_transition_kills_previous_tween() -> void:
	print("TestSunshineCloudsDriver: test_weather_transition_kills_previous_tween() called.")
	var clear_w: SunshineCloudsWeather = SunshineCloudsWeather.new()
	clear_w.clouds_coverage = 0.25

	var overcast_w: SunshineCloudsWeather = SunshineCloudsWeather.new()
	overcast_w.clouds_coverage = 0.96

	_driver.transition_to(clear_w, 2.0)
	var first_tween: Tween = _driver.get_weather_tween()
	assert_not_null(first_tween, "First transition should spawn a Tween.")
	assert_true(first_tween.is_valid(), "First Tween should be valid initially.")

	_driver.transition_to(overcast_w, 2.0)
	var second_tween: Tween = _driver.get_weather_tween()
	assert_false(first_tween.is_valid(), "First Tween must be killed before spawning the second.")
	assert_not_null(second_tween, "Second transition should spawn a new Tween.")
	assert_true(second_tween.is_valid(), "Second Tween should be valid.")
