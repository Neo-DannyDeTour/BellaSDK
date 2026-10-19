extends GutTest

## Test suite validating the UpdraftVent modular volume and pickable physics.
var vent: UpdraftVent = null
var vent_scene: PackedScene = null


func before_each() -> void:
	print("test_updraft_vent: before_each() setup.")
	vent_scene = load("res://environment/updraft_vent.tscn") as PackedScene
	vent = vent_scene.instantiate() as UpdraftVent
	add_child_autofree(vent)


func test_initialization() -> void:
	print("test_updraft_vent: test_initialization().")
	assert_not_null(vent, "Vent instance should not be null.")
	assert_eq(vent.radius, 1.0, "Default radius should be 1.0.")
	assert_eq(vent.height, 4.0, "Default height should be 4.0.")
	assert_eq(vent.lift_strength, 12.0, "Default lift strength should be 12.0.")
	assert_eq(
		vent.collision_mask, 6, "Collision mask should include Player (2) and Interactive (4)."
	)


func test_reconfigure_dimensions() -> void:
	print("test_updraft_vent: test_reconfigure_dimensions().")
	vent.radius = 2.5
	vent.height = 8.0

	var cyl_shape: CylinderShape3D = vent.collision_shape.shape as CylinderShape3D
	assert_not_null(cyl_shape, "Cylinder shape should exist.")
	assert_eq(cyl_shape.radius, 2.5, "Collision radius should update.")
	assert_eq(cyl_shape.height, 8.0, "Collision height should update.")
	assert_eq(vent.collision_shape.position.y, 4.0, "Collision Y should center at height * 0.5.")


class MockUpdraftTarget:
	extends Node3D

	var entered: bool = false
	var exited: bool = false
	var strength_received: float = 0.0
	var top_received: float = 0.0

	func enter_updraft(strength: float, top_y: float) -> void:
		entered = true
		strength_received = strength
		top_received = top_y

	func exit_updraft() -> void:
		exited = true


func test_player_entry_and_exit() -> void:
	print("test_updraft_vent: test_player_entry_and_exit().")
	var dummy: MockUpdraftTarget = MockUpdraftTarget.new()
	add_child_autofree(dummy)

	vent._on_body_entered(dummy)
	assert_true(dummy.entered, "enter_updraft() should be called on entering entity.")
	assert_eq(dummy.strength_received, 12.0, "Lift strength should match vent setting.")
	var expected_top: float = vent.global_position.y + 4.0
	assert_eq(dummy.top_received, expected_top, "Top boundary should be height.")

	vent._on_body_exited(dummy)
	assert_true(dummy.exited, "exit_updraft() should be called on exiting entity.")


func test_pickable_physics_registration() -> void:
	print("test_updraft_vent: test_pickable_physics_registration().")
	var pickable: RigidBody3D = RigidBody3D.new()
	add_child_autofree(pickable)

	assert_false(vent.is_physics_processing(), "Physics process should initially be inactive.")

	vent._on_body_entered(pickable)
	assert_true(vent.is_physics_processing(), "Physics process should activate for pickables.")

	vent._on_body_exited(pickable)
	assert_false(vent.is_physics_processing(), "Physics process should deactivate after exit.")


func test_heavy_box_exclusion() -> void:
	print("test_updraft_vent: test_heavy_box_exclusion().")
	var heavy_box: HeavyPickableBox = HeavyPickableBox.new()
	add_child_autofree(heavy_box)

	vent._on_body_entered(heavy_box)
	assert_false(
		vent.is_physics_processing(), "Physics process must NOT activate for HeavyPickableBox."
	)
