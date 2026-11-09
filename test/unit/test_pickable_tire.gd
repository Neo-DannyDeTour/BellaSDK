## Unit test suite validating [PickableTire] instantiation, mass, and configuration.
class_name TestPickableTire
extends GutTest

## Preloaded tire packed scene.
const TIRE_SCENE: PackedScene = preload("res://interactables/pickable_tire.tscn")

## Instance of the pickable tire under test.
var tire: PickableTire = null


## Prepares isolated PickableTire instance before each test.
func before_each() -> void:
	print("TestPickableTire: Setting up test environment.")
	tire = TIRE_SCENE.instantiate() as PickableTire
	add_child_autofree(tire)


## Cleans up tire instance after each test.
func after_each() -> void:
	print("TestPickableTire: Tearing down test environment.")
	tire = null


## Validates instantiation and node hierarchy requirements.
func test_tire_instantiation_and_properties() -> void:
	assert_not_null(tire, "Tire instance should instantiate successfully.")
	assert_true(tire is PickableTire, "Tire node must be a PickableTire.")
	assert_true(tire is PickableObject, "Tire node must be a PickableObject.")
	assert_eq(tire.mass, 9.5, "Tire mass must equal 9.5 to match carcass weight.")
	assert_true(tire.is_in_group(&"interactables"), "Tire must belong to interactables group.")
	assert_true(tire.is_in_group(&"magnetizable"), "Tire must belong to magnetizable group.")
	assert_not_null(tire.collision, "Tire must have a CollisionShape3D.")
	assert_true(
		tire.collision.shape is CylinderShape3D, "Tire collision shape must be a CylinderShape3D."
	)
	var cyl: CylinderShape3D = tire.collision.shape as CylinderShape3D
	assert_almost_eq(cyl.radius, 0.325, 0.01, "Cylinder radius should match carcass radius.")
	assert_almost_eq(cyl.height, 0.22, 0.01, "Cylinder height should match carcass width.")
	assert_not_null(tire.mesh, "Tire visual mesh reference must be assigned.")
	assert_true(tire.hold_at_chest, "Tire must have hold_at_chest enabled.")
	assert_eq(tire.custom_hold_distance, 0.5, "Custom hold distance should be set to 0.5m.")
	assert_eq(tire.hold_vertical_offset, -0.15, "Vertical offset should position tire at chest.")
	assert_not_null(tire.physics_material_override, "Tire must have physics material override.")
	assert_almost_eq(tire.physics_material_override.friction, 0.9, 0.01, "Friction should be 0.9.")
	assert_almost_eq(tire.physics_material_override.bounce, 0.35, 0.01, "Bounce should be 0.35.")
