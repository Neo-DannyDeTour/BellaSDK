## Unit test suite validating [PickablePaintCan] setup, layers, geometry, texture, and impulses.
class_name TestPickablePaintCan
extends GutTest

## Preloaded pickable paint can scene.
const PAINT_CAN_SCENE: PackedScene = preload("res://interactables/pickable_paint_can.tscn")

## Active [PickablePaintCan] instance under test.
var can: PickablePaintCan = null


## Instantiates a fresh [PickablePaintCan] before each test case.
func before_each() -> void:
	print("TestPickablePaintCan: Setting up test instance.")
	can = PAINT_CAN_SCENE.instantiate() as PickablePaintCan
	add_child_autofree(can)


## Clears test reference after each test case.
func after_each() -> void:
	print("TestPickablePaintCan: Tearing down test instance.")
	can = null


## Validates scene hierarchy, dimensions, layers, mass, material, and pickable configuration.
func test_instantiation_layers_and_geometry() -> void:
	assert_not_null(can, "PickablePaintCan should instantiate cleanly.")
	assert_true(can is PickablePaintCan, "Node must be a PickablePaintCan.")
	assert_true(can is PickableObject, "Node must extend PickableObject.")
	assert_almost_eq(can.mass, 1.2, 0.001, "Can mass should default to 1.2 kg.")
	assert_eq(
		can.collision_layer,
		CollisionLayers.MASK_INTERACTIVE,
		"Physics layer must be Layer 3 (Interactive)."
	)
	assert_eq(
		can.collision_mask,
		(
			CollisionLayers.MASK_ENVIRONMENT
			| CollisionLayers.MASK_PLAYER
			| CollisionLayers.MASK_INTERACTIVE
		),
		"Physics mask must match PickableObject standard layers (Env, Player, Interactive)."
	)
	assert_true(can.is_in_group(&"interactables"), "Can must belong to interactables group.")
	assert_true(can.is_in_group(&"magnetizable"), "Can must belong to magnetizable group.")
	assert_false(can.lock_on_player_stand, "Can must not lock into a standing platform.")
	assert_true(can.hold_at_chest, "Can should hold at chest height.")
	assert_almost_eq(can.custom_hold_distance, 0.5, 0.001, "Hold distance should be 0.5 m.")

	assert_not_null(can.collision, "Can must expose CollisionShape3D.")
	assert_true(can.collision.shape is CylinderShape3D, "Collision shape must be CylinderShape3D.")
	var cyl_shape: CylinderShape3D = can.collision.shape as CylinderShape3D
	assert_almost_eq(cyl_shape.radius, 0.08, 0.001, "Cylinder shape radius must be 0.08 m.")
	assert_almost_eq(cyl_shape.height, 0.18, 0.001, "Cylinder shape height must be 0.18 m.")

	assert_true(can.mesh is MeshInstance3D, "Visual mesh must be a MeshInstance3D.")
	var mesh_inst: MeshInstance3D = can.mesh as MeshInstance3D
	assert_eq(
		mesh_inst.layers,
		CollisionLayers.RENDER_MASK_INTERACTIVE,
		"Render layer must be Layer 3 (Interactive)."
	)
	assert_true(mesh_inst.mesh is CylinderMesh, "Mesh resource must be CylinderMesh.")
	var cyl_mesh: CylinderMesh = mesh_inst.mesh as CylinderMesh
	assert_almost_eq(cyl_mesh.top_radius, 0.08, 0.001, "Top radius must be 0.08 m.")
	assert_almost_eq(cyl_mesh.bottom_radius, 0.08, 0.001, "Bottom radius must be 0.08 m.")
	assert_almost_eq(cyl_mesh.height, 0.18, 0.001, "Mesh height must be 0.18 m.")
	assert_eq(cyl_mesh.radial_segments, 12, "Mesh must have 12 radial segments.")

	assert_true(cyl_mesh.material is StandardMaterial3D, "Material must be StandardMaterial3D.")
	var mat: StandardMaterial3D = cyl_mesh.material as StandardMaterial3D
	assert_not_null(mat.albedo_texture, "Albedo texture must be assigned.")
	assert_eq(
		mat.albedo_texture.resource_path,
		"res://assets/textures/kveta_paint_can.png",
		"Albedo texture must point to kveta_paint_can.png."
	)
	assert_eq(
		mat.texture_filter,
		BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS,
		"Material must use nearest-with-mipmaps texture filtering."
	)


## Validates mass-proportional drop impulse avoids launching the paint can on drop.
func test_drop_impulse_is_mass_proportional() -> void:
	var expected_mag: float = can.mass * PickablePaintCan.DROP_SPEED
	var actual_mag: float = can._get_drop_impulse_magnitude()
	assert_almost_eq(
		actual_mag, expected_mag, 0.001, "Drop impulse must scale proportionally with can mass."
	)
	assert_lt(actual_mag, 5.0, "Drop impulse must remain below heavy-prop 5.0 N*s floor.")
