## Unit test suite validating [PickableTinCan] setup, layers, tinting, drop/throw caps, and impacts.
class_name TestPickableTinCan
extends GutTest

## Preloaded pickable tin can scene.
const TIN_CAN_SCENE: PackedScene = preload("res://interactables/pickable_tin_can.tscn")

## Active [PickableTinCan] instance under test.
var can: PickableTinCan = null


## Instantiates a fresh [PickableTinCan] before each test case.
func before_each() -> void:
	print("TestPickableTinCan: Setting up test instance.")
	can = TIN_CAN_SCENE.instantiate() as PickableTinCan
	add_child_autofree(can)


## Clears test reference after each test case.
func after_each() -> void:
	print("TestPickableTinCan: Tearing down test instance.")
	can = null


## Validates scene hierarchy, dimensions, layers, mass, and pickable configuration.
func test_instantiation_layers_and_dimensions() -> void:
	assert_not_null(can, "PickableTinCan should instantiate cleanly.")
	assert_true(can is PickableTinCan, "Node must be a PickableTinCan.")
	assert_true(can is PickableObject, "Node must extend PickableObject.")
	assert_almost_eq(can.mass, 0.12, 0.001, "Can mass should default to 0.12 kg.")
	assert_eq(
		can.collision_layer,
		CollisionLayers.MASK_INTERACTIVE,
		"Physics layer must be Layer 3 (Interactive)."
	)
	assert_true(can.is_in_group(&"interactables"), "Can must belong to interactables group.")
	assert_true(can.is_in_group(&"magnetizable"), "Can must belong to magnetizable group.")
	assert_false(can.lock_on_player_stand, "Can must not lock into a standing platform.")
	assert_eq(can.projectile_damage, 0, "Tin can should deal zero projectile damage.")
	assert_true(can.hold_at_chest, "Can should hold at chest height.")
	assert_almost_eq(can.custom_hold_distance, 0.45, 0.001, "Hold distance should be 0.45 m.")

	assert_not_null(can.collision, "Can must expose CollisionShape3D.")
	assert_true(can.collision.shape is CylinderShape3D, "Collision shape must be CylinderShape3D.")
	var cyl: CylinderShape3D = can.collision.shape as CylinderShape3D
	assert_almost_eq(cyl.radius, 0.04, 0.001, "Cylinder radius must be 0.04 m.")
	assert_almost_eq(cyl.height, 0.11, 0.001, "Cylinder height must be 0.11 m.")

	assert_true(can.mesh is MeshInstance3D, "Visual mesh must be a MeshInstance3D.")
	var mesh_inst: MeshInstance3D = can.mesh as MeshInstance3D
	assert_not_null(mesh_inst.mesh, "Can mesh resource must be assigned.")
	assert_eq(
		mesh_inst.layers,
		CollisionLayers.RENDER_MASK_INTERACTIVE,
		"Render layer must be Layer 3 (Interactive)."
	)
	var mat: Material = mesh_inst.get_surface_override_material(0)
	assert_true(mat is ShaderMaterial, "Can must use tin_can ShaderMaterial.")


## Validates that updating [member PickableTinCan.instance_tint] pushes the instance uniform.
func test_instance_tint_updates_shader_parameter() -> void:
	var target_tint: Color = Color(0.85, 0.75, 0.65, 1.0)
	can.instance_tint = target_tint
	var mesh_inst: MeshInstance3D = can.mesh as MeshInstance3D
	var applied: Variant = mesh_inst.get_instance_shader_parameter(PickableTinCan.SHADER_PARAM_TINT)
	assert_true(applied is Color, "Shader instance tint uniform must store a Color.")
	if applied is Color:
		var applied_color: Color = applied
		assert_eq(applied_color, target_tint, "Instance shader tint must match exported value.")


## Validates mass-proportional drop impulse avoids launching ultra-light cans.
func test_drop_impulse_is_mass_proportional() -> void:
	var expected_mag: float = can.mass * PickableTinCan.DROP_SPEED
	var actual_mag: float = can._get_drop_impulse_magnitude()
	assert_almost_eq(
		actual_mag, expected_mag, 0.001, "Drop impulse must scale proportionally with can mass."
	)
	assert_lt(actual_mag, 1.0, "Drop impulse must remain well below heavy-prop 5.0 N*s floor.")


## Validates [signal PickableTinCan.impact_detected] emits only above the squared speed threshold.
func test_impact_detected_signal_threshold() -> void:
	watch_signals(can)
	var dummy_wall: StaticBody3D = StaticBody3D.new()
	dummy_wall.name = "ConcreteWall"
	add_child_autofree(dummy_wall)

	can.linear_velocity = Vector3(0.2, 0.0, 0.0)
	can._last_velocity = Vector3.ZERO
	can._on_body_entered(dummy_wall)
	assert_signal_not_emitted(can, "impact_detected", "Slow contact should not emit impact.")

	can.linear_velocity = Vector3(2.0, 0.0, 0.0)
	can._on_body_entered(dummy_wall)
	assert_signal_emit_count(can, "impact_detected", 1, "Fast impact must emit impact_detected.")
