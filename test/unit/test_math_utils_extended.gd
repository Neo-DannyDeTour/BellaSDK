## Extended unit tests verifying uncovered [MathUtils] smoothing, proximity, and transforms.
class_name TestMathUtilsExtended
extends GutTest

## Test suite identifier for log tracking.
var test_name: String = "TestMathUtilsExtended"


## Verifies [method MathUtils.damp] smoothly interpolates float toward target.
func test_damp_scalar() -> void:
	print("TestMathUtilsExtended: test_damp_scalar() executing.")
	var start: float = 0.0
	var target: float = 10.0
	var result: float = MathUtils.damp(start, target, 5.0, 0.1)
	assert_gt(result, start, "Damped value should advance toward target.")
	assert_lt(result, target, "Damped value should not overshoot target.")


## Verifies [method MathUtils.damp_v2] smoothly interpolates [Vector2] coordinates.
func test_damp_v2() -> void:
	print("TestMathUtilsExtended: test_damp_v2() executing.")
	var start: Vector2 = Vector2.ZERO
	var target: Vector2 = Vector2(10.0, 20.0)
	var result: Vector2 = MathUtils.damp_v2(start, target, 5.0, 0.1)
	assert_gt(result.x, start.x, "Damped Vector2 X should move toward target.")
	assert_gt(result.y, start.y, "Damped Vector2 Y should move toward target.")


## Verifies [method MathUtils.damp_v3] smoothly interpolates [Vector3] coordinates.
func test_damp_v3() -> void:
	print("TestMathUtilsExtended: test_damp_v3() executing.")
	var start: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3(10.0, -5.0, 30.0)
	var result: Vector3 = MathUtils.damp_v3(start, target, 5.0, 0.1)
	assert_gt(result.x, start.x, "Damped Vector3 X should advance toward target.")
	assert_lt(result.y, start.y, "Damped Vector3 Y should advance downward toward target.")
	assert_gt(result.z, start.z, "Damped Vector3 Z should advance toward target.")


## Verifies [method MathUtils.get_midpoint] computes exact geometric center between two points.
func test_get_midpoint() -> void:
	print("TestMathUtilsExtended: test_get_midpoint() executing.")
	var a: Vector3 = Vector3(0.0, 10.0, -20.0)
	var b: Vector3 = Vector3(10.0, 20.0, 0.0)
	var mid: Vector3 = MathUtils.get_midpoint(a, b)
	assert_eq(mid, Vector3(5.0, 15.0, -10.0), "Midpoint should match arithmetic mean.")


## Verifies [method MathUtils.snap_to_grid_3d] snaps coordinates to grid intervals.
func test_snap_to_grid_3d() -> void:
	print("TestMathUtilsExtended: test_snap_to_grid_3d() executing.")
	var pos: Vector3 = Vector3(1.23, 4.87, -2.45)
	var snapped_pos: Vector3 = MathUtils.snap_to_grid_3d(pos, 0.5)
	assert_almost_eq(snapped_pos.x, 1.0, 0.01, "X should snap to nearest 0.5 multiple.")
	assert_almost_eq(snapped_pos.y, 5.0, 0.01, "Y should snap to nearest 0.5 multiple.")
	assert_almost_eq(snapped_pos.z, -2.5, 0.01, "Z should snap to nearest 0.5 multiple.")

	var passthrough: Vector3 = MathUtils.snap_to_grid_3d(pos, 0.0)
	assert_eq(passthrough, pos, "Zero or negative grid step must return unmutated pos.")


## Verifies [method MathUtils.normalize_angle] wraps angles properly within [-PI, PI].
func test_normalize_angle() -> void:
	print("TestMathUtilsExtended: test_normalize_angle() executing.")
	var angle_pos: float = MathUtils.normalize_angle(3.0 * PI)
	assert_almost_eq(angle_pos, -PI, 0.01, "3*PI wrapped should equal -PI.")

	var angle_neg: float = MathUtils.normalize_angle(-3.0 * PI)
	assert_almost_eq(angle_neg, -PI, 0.01, "-3*PI wrapped should equal -PI.")

	var angle_mid: float = MathUtils.normalize_angle(0.5)
	assert_almost_eq(angle_mid, 0.5, 0.01, "Angle inside range should remain untouched.")


## Verifies [method MathUtils.is_within_distance_3d] evaluates proximity via squared math.
func test_is_within_distance_3d() -> void:
	print("TestMathUtilsExtended: test_is_within_distance_3d() executing.")
	var a: Vector3 = Vector3.ZERO
	var b: Vector3 = Vector3(3.0, 4.0, 0.0)

	assert_true(
		MathUtils.is_within_distance_3d(a, b, 5.0),
		"Distance exactly equal to threshold must return true."
	)
	assert_true(
		MathUtils.is_within_distance_3d(a, b, 6.0), "Distance less than threshold must return true."
	)
	assert_false(
		MathUtils.is_within_distance_3d(a, b, 4.9),
		"Distance exceeding threshold must return false."
	)
	assert_false(
		MathUtils.is_within_distance_3d(a, b, -1.0),
		"Negative distance threshold must return false."
	)


## Verifies [method MathUtils.calculate_cylinder_span_transform] positions and rotates span.
func test_calculate_cylinder_span_transform() -> void:
	print("TestMathUtilsExtended: test_calculate_cylinder_span_transform() executing.")
	var start_pos: Vector3 = Vector3(0.0, 0.0, 0.0)
	var end_pos: Vector3 = Vector3(0.0, 10.0, 0.0)
	var xform: Transform3D = MathUtils.calculate_cylinder_span_transform(start_pos, end_pos)
	assert_almost_eq(xform.origin.y, 5.0, 0.01, "Span origin Y must be halfway along segment.")

	var zero_xform: Transform3D = MathUtils.calculate_cylinder_span_transform(start_pos, start_pos)
	assert_eq(zero_xform.origin, start_pos, "Collinear degenerate span retains identity origin.")
