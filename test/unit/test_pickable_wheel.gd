## Unit test suite validating [PickableObject] instantiation, mass, and configuration for wheel.
class_name TestPickableWheel
extends GutTest

## Preloaded wheel packed scene.
const WHEEL_SCENE: PackedScene = preload("res://interactables/pickable_wheel.tscn")

## Instance of the pickable wheel under test.
var wheel: PickableObject = null


## Prepares isolated PickableWheel instance before each test.
func before_each() -> void:
	print("TestPickableWheel: Setting up test environment.")
	wheel = WHEEL_SCENE.instantiate() as PickableObject
	add_child_autofree(wheel)


## Cleans up wheel instance after each test.
func after_each() -> void:
	print("TestPickableWheel: Tearing down test environment.")
	wheel = null


## Validates instantiation and node hierarchy requirements.
func test_wheel_instantiation_and_properties() -> void:
	assert_not_null(wheel, "Wheel instance should instantiate successfully.")
	assert_true(wheel is PickableObject, "Wheel node must be a PickableObject.")
	assert_eq(wheel.mass, 10.0, "Wheel mass must equal 10.0 to match barrel weight.")
	assert_true(wheel.is_in_group(&"interactables"), "Wheel must belong to interactables group.")
	assert_true(wheel.is_in_group(&"magnetizable"), "Wheel must belong to magnetizable group.")
	assert_not_null(wheel.collision, "Wheel must have a CollisionShape3D.")
	assert_true(
		wheel.collision.shape is CylinderShape3D, "Wheel collision shape must be a CylinderShape3D."
	)
	var cyl: CylinderShape3D = wheel.collision.shape as CylinderShape3D
	assert_almost_eq(cyl.radius, 0.33, 0.01, "Cylinder radius should match outer radius.")
	assert_not_null(wheel.mesh, "Wheel visual mesh reference must be assigned.")
	assert_true(wheel.hold_at_chest, "Wheel must have hold_at_chest enabled.")
	assert_eq(wheel.custom_hold_distance, 0.5, "Custom hold distance should be set to 0.5m.")
	assert_eq(wheel.hold_vertical_offset, -0.15, "Vertical offset should position wheel at chest.")
	assert_eq(
		wheel.hold_rotation_offset_deg, Vector3.ZERO, "Default hold rotation offset should be zero."
	)
