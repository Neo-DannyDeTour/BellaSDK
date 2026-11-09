## Unit test suite for validating [MannequinVolume] metric sync and climbability checks.
class_name TestMannequinVolume
extends GutTest

const MANNEQUIN_VOLUME_SCENE: PackedScene = preload("res://environment/mannequin_volume.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")


## Verifies metric extraction from player scene into volume tool.
func test_sync_with_target() -> void:
	var vol: Node3D = MANNEQUIN_VOLUME_SCENE.instantiate() as Node3D
	add_child_autofree(vol)

	vol.set("player_scene", PLAYER_SCENE)
	vol.call(&"_sync_with_target")

	var char_height: float = float(vol.get(&"_character_height"))
	var stand_height: float = float(vol.get(&"_standing_height"))
	var crouch_height: float = float(vol.get(&"_crouch_height"))
	var capsule_h: float = float(vol.get(&"_capsule_height"))
	var capsule_r: float = float(vol.get(&"_capsule_radius"))
	var reach: float = float(vol.get(&"_standing_reach"))

	assert_almost_eq(char_height, 1.64, 0.01, "Character height must sync to 1.64m.")
	assert_almost_eq(stand_height, 1.52, 0.01, "Standing eye level must sync to 1.52m.")
	assert_almost_eq(crouch_height, 0.9, 0.01, "Crouch eye level must sync to 0.9m.")
	assert_almost_eq(capsule_h, 1.64, 0.01, "Capsule height must sync to 1.64m.")
	assert_almost_eq(capsule_r, 0.35, 0.01, "Capsule radius must sync to 0.35m.")
	assert_almost_eq(reach, 2.1, 0.01, "Standing reach must sync to 2.1m.")

	var heights: Array[float] = vol.get(&"box_heights")
	assert_eq(heights.size(), 3, "box_heights must have 3 entries.")
	assert_almost_eq(heights[0], 0.9, 0.01, "First box height should match crouch height.")
	assert_almost_eq(heights[1], 1.64, 0.01, "Second box height should match character height.")


## Verifies that not_climbable group on node or parent rejects climbing.
func test_not_climbable_rejection() -> void:
	var vol: Node3D = MANNEQUIN_VOLUME_SCENE.instantiate() as Node3D
	add_child_autofree(vol)

	var parent_body: StaticBody3D = StaticBody3D.new()
	var child_body: StaticBody3D = StaticBody3D.new()
	parent_body.add_child(child_body)
	add_child_autofree(parent_body)

	assert_false(
		bool(vol.call(&"_is_not_climbable", child_body)),
		"Normal body should not be flagged as not_climbable."
	)

	parent_body.add_to_group(&"not_climbable")
	assert_true(
		bool(vol.call(&"_is_not_climbable", child_body)),
		"Child of not_climbable node must be rejected."
	)
