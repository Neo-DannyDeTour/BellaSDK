extends GutTest

## A GUT test script for the [MathUtils] class validating fast vector math and wave calculations.
var test_name: String = "Test MathUtils"


func before_all() -> void:
	print("Setting up MathUtils tests...")


func test_damped_spring() -> void:
	print("Testing MathUtils.damped_spring()...")
	var result: Dictionary = MathUtils.damped_spring(0.0, 10.0, 0.0, 10.0, 2.0, 0.1)
	assert_has(result, &"position", "Result should have a position key")
	assert_has(result, &"velocity", "Result should have a velocity key")
	assert_almost_eq(result[&"position"], 1.0, 0.01, "Position should move towards target")


func test_damped_spring_v3() -> void:
	print("Testing MathUtils.damped_spring_v3()...")
	var result: Dictionary = MathUtils.damped_spring_v3(
		Vector3.ZERO, Vector3(10, 0, 0), Vector3.ZERO, 10.0, 2.0, 0.1
	)
	assert_has(result, &"position", "Result should have a position key")
	assert_has(result, &"velocity", "Result should have a velocity key")
	assert_almost_eq(result[&"position"].x, 1.0, 0.01, "Position X should move towards target")


func test_quadratic_bezier() -> void:
	print("Testing MathUtils.quadratic_bezier()...")
	var p0: Vector3 = Vector3(0, 0, 0)
	var p1: Vector3 = Vector3(5, 5, 0)
	var p2: Vector3 = Vector3(10, 0, 0)

	var res_start: Vector3 = MathUtils.quadratic_bezier(p0, p1, p2, 0.0)
	assert_eq(res_start, p0, "t=0 should match start point")

	var res_mid: Vector3 = MathUtils.quadratic_bezier(p0, p1, p2, 0.5)
	assert_eq(res_mid, Vector3(5, 2.5, 0), "t=0.5 should be mid curve")

	var res_end: Vector3 = MathUtils.quadratic_bezier(p0, p1, p2, 1.0)
	assert_eq(res_end, p2, "t=1 should match end point")


func test_cubic_bezier() -> void:
	print("Testing MathUtils.cubic_bezier()...")
	var p0: Vector3 = Vector3(0, 0, 0)
	var p1: Vector3 = Vector3(2.5, 5, 0)
	var p2: Vector3 = Vector3(7.5, 5, 0)
	var p3: Vector3 = Vector3(10, 0, 0)

	var res_start: Vector3 = MathUtils.cubic_bezier(p0, p1, p2, p3, 0.0)
	assert_eq(res_start, p0, "t=0 should match start point")

	var res_mid: Vector3 = MathUtils.cubic_bezier(p0, p1, p2, p3, 0.5)
	assert_eq(res_mid, Vector3(5, 3.75, 0), "t=0.5 should be mid curve")

	var res_end: Vector3 = MathUtils.cubic_bezier(p0, p1, p2, p3, 1.0)
	assert_eq(res_end, p3, "t=1 should match end point")


func test_sine_wave() -> void:
	print("Testing MathUtils.sine_wave()...")
	var res: float = MathUtils.sine_wave(0.0, 1.0, 0.0, 1.0, 5.0)
	assert_eq(res, 0.0, "Sine wave at zero should be zero")

	var res_peak: float = MathUtils.sine_wave(PI / 2, 1.0, 0.0, 1.0, 5.0)
	assert_almost_eq(res_peak, 5.0, 0.01, "Sine wave peak should equal amplitude")


func test_gerstner_wave() -> void:
	print("Testing MathUtils.gerstner_wave()...")
	var pos: Vector3 = Vector3(0, 0, 0)
	var dir: Vector2 = Vector2(1, 0)
	var res: Vector3 = MathUtils.gerstner_wave(pos, dir, 1.0, 10.0, 0.0)
	assert_not_null(res, "Gerstner wave should return a Vector3")
	assert_true(typeof(res) == TYPE_VECTOR3, "Result should be Vector3")


func test_calculate_wave_height() -> void:
	print("Testing MathUtils.calculate_wave_height()...")
	var pos: Vector3 = Vector3(0, 0, 0)
	var params: Vector4 = Vector4(1.0, 5.0, 1.0, 0.0)
	var res: float = MathUtils.calculate_wave_height(pos, params, 0.0)
	assert_eq(res, 0.0, "Wave height at origin should be 0")


func test_compound_wave_height() -> void:
	print("Testing MathUtils.compound_wave_height()...")
	var res: float = MathUtils.compound_wave_height(0.0, 0.0, 0.0)
	assert_eq(res, 0.0, "Compound wave at origin should be 0")


func test_clamp_angle_deg() -> void:
	print("Testing MathUtils.clamp_angle_deg()...")
	var res: float = MathUtils.clamp_angle_deg(370.0, -90.0, 90.0)
	assert_eq(res, 10.0, "Angle should wrap and be clamped")

	var res_clamp: float = MathUtils.clamp_angle_deg(150.0, -90.0, 90.0)
	assert_eq(res_clamp, 90.0, "Angle should be clamped to max")


func test_clamp_angle_rad() -> void:
	print("Testing MathUtils.clamp_angle_rad()...")
	var max_rad: float = PI / 2
	var res: float = MathUtils.clamp_angle_rad(3.0 * PI, -max_rad, max_rad)
	assert_almost_eq(res, max_rad, 0.01, "Angle in rads should be clamped to max")


func test_smooth_damp_angle() -> void:
	print("Testing MathUtils.smooth_damp_angle()...")
	var res: Vector2 = MathUtils.smooth_damp_angle(0.0, PI, 0.0, 0.5, 0.1)
	assert_not_null(res, "Result should return position and velocity")
