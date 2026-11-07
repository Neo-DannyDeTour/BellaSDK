class_name TestDumpster
extends GutTest
## Unit tests for [Dumpster] interactive container prop and collision setup.

## Instantiated [Dumpster] test fixture.
var _dumpster: Dumpster = null


## Instantiates dumpster scene before each test run.
func before_each() -> void:
	print("TestDumpster: Setting up test fixture.")
	var sc: PackedScene = load("res://interactables/dumpster/dumpster.tscn") as PackedScene
	_dumpster = sc.instantiate() as Dumpster
	add_child_autofree(_dumpster)


## Frees test fixture after each test run.
func after_each() -> void:
	print("TestDumpster: Tearing down test fixture.")
	_dumpster = null


## Verifies mandatory child components and mesh references are configured correctly.
func test_initial_hierarchy_and_components() -> void:
	assert_not_null(_dumpster, "Dumpster instance should be valid.")

	var interact_comp: Node = _dumpster.get_node_or_null("InteractComponent")
	assert_not_null(interact_comp, "InteractComponent should be present in scene.")
	assert_true(interact_comp is InteractComponent, "Must be instance of InteractComponent.")

	var highlight_comp: Node = _dumpster.get_node_or_null("HighlightComponent")
	assert_not_null(highlight_comp, "HighlightComponent should be present in scene.")
	assert_true(highlight_comp is HighlightComponent, "Must be instance of HighlightComponent.")

	var body_mesh: MeshInstance3D = (
		_dumpster.find_child("Dumpster_Body", true, false) as MeshInstance3D
	)
	var lid_mesh: MeshInstance3D = (
		_dumpster.find_child("Dumpster_Lid", true, false) as MeshInstance3D
	)
	assert_not_null(body_mesh, "Dumpster_Body MeshInstance3D should exist.")
	assert_not_null(lid_mesh, "Dumpster_Lid MeshInstance3D should exist.")


## Verifies default scene scale is Vector3.ONE.
func test_default_scale_is_one() -> void:
	assert_eq(_dumpster.scale, Vector3.ONE, "Dumpster default scale must be Vector3.ONE.")


## Verifies InteriorArea is present and configured for Layer 2 Player tracking.
func test_interior_area_configured() -> void:
	var interior_area: Area3D = _dumpster.get_node_or_null("InteriorArea") as Area3D
	assert_not_null(interior_area, "InteriorArea must exist.")
	assert_eq(interior_area.collision_layer, 0, "InteriorArea collision_layer must be 0.")
	assert_eq(
		interior_area.collision_mask, CollisionLayers.MASK_PLAYER, "InteriorArea must track player."
	)


## Verifies wall colliders resolve to root Dumpster and no blocking InteractArea exists.
func test_container_colliders_and_root_resolution() -> void:
	var interact_area: Node = _dumpster.get_node_or_null("InteractArea")
	assert_null(
		interact_area, "InteractArea static blocker must be removed to allow entering interior."
	)

	var body_col: StaticBody3D = (
		_dumpster.find_child("Dumpster_Col_Front", true, false) as StaticBody3D
	)
	assert_not_null(body_col, "Dumpster_Col_Front should exist in dumpster scene.")

	var resolved_root: Node3D = NodeQuery.resolve_interactable_root(body_col)
	assert_eq(
		resolved_root, _dumpster, "NodeQuery should resolve body static colliders to root Dumpster."
	)


## Verifies that Dumpster_Col_Rim_Front exists for vaulting support.
func test_rim_collider_exists() -> void:
	var rim_col: StaticBody3D = (
		_dumpster.find_child("Dumpster_Col_Rim_Front", true, false) as StaticBody3D
	)
	assert_not_null(rim_col, "Dumpster_Col_Rim_Front must exist for vaulting ledge detection.")


## Verifies player direct interaction dispatches open and close states.
func test_player_interaction_and_toggle() -> void:
	assert_false(_dumpster.is_open, "Dumpster should start closed.")

	var dummy_char: CharacterBody3D = CharacterBody3D.new()
	dummy_char.name = "TestPlayer"
	_dumpster.interact_with(dummy_char)
	assert_true(_dumpster.is_open, "Dumpster should be opened by direct interaction.")

	_dumpster.interact_with(dummy_char)
	assert_false(_dumpster.is_open, "Dumpster should be closed by second interaction.")
	dummy_char.free()


## Verifies InteractComponent.interact_with propagates to Dumpster without double-toggling.
func test_interact_component_triggers_dumpster_once() -> void:
	assert_false(_dumpster.is_open, "Dumpster should start closed.")

	var interact_comp: InteractComponent = (
		_dumpster.get_node_or_null("InteractComponent") as InteractComponent
	)
	assert_not_null(interact_comp, "InteractComponent must exist.")

	var dummy_char: CharacterBody3D = CharacterBody3D.new()
	dummy_char.name = "TestPlayer"
	interact_comp.interact_with(dummy_char)
	assert_true(
		_dumpster.is_open, "Single interact_with call on InteractComponent must open Dumpster once."
	)

	interact_comp.interact_with(dummy_char)
	assert_false(
		_dumpster.is_open, "Second interact_with call on InteractComponent must close Dumpster."
	)
	dummy_char.free()
