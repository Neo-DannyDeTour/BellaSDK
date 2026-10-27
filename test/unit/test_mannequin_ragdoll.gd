## Unit tests for the 2.0m articulated [MannequinRagdoll] scene and physical bone setup.
extends GutTest

const MANNEQUIN_SCENE: PackedScene = preload("res://interactables/mannequin_ragdoll.tscn")


## Verifies 60 FPS event-driven invariants, Layer 3 assignments, and 17-bone ragdoll activation.
func test_mannequin_ragdoll_setup_and_activation() -> void:
	var ragdoll: MannequinRagdoll = MANNEQUIN_SCENE.instantiate() as MannequinRagdoll
	add_child_autofree(ragdoll)

	assert_false(ragdoll.is_processing(), "Process must be disabled in _ready() for 60 FPS safety.")
	assert_false(
		ragdoll.is_physics_processing(),
		"Physics process must be disabled in _ready() for 60 FPS safety."
	)
	assert_false(ragdoll.is_ragdoll_active, "Mannequin must start standing in A-pose.")

	var skel: Skeleton3D = ragdoll.get_skeleton()
	assert_not_null(skel, "Skeleton3D must be present.")
	assert_eq(skel.get_bone_count(), 17, "Mannequin armature must have 17 articulated bones.")
	assert_eq(
		ragdoll.get_physical_bone_count(),
		17,
		"PhysicalBoneSimulator3D must contain 17 PhysicalBone3D segments."
	)

	var chest_bone: PhysicalBone3D = ragdoll.get_physical_bone(&"Chest")
	assert_not_null(chest_bone, "Chest PhysicalBone3D must exist.")
	assert_eq(
		chest_bone.collision_layer,
		CollisionLayers.MASK_INTERACTIVE,
		"PhysicalBone3D must be on Physics Layer 3 (Interactive)."
	)
	assert_eq(
		chest_bone.collision_mask,
		(
			CollisionLayers.MASK_ENVIRONMENT
			| CollisionLayers.MASK_PLAYER
			| CollisionLayers.MASK_INTERACTIVE
		),
		"PhysicalBone3D must collide with Environment, Player, and Interactive layers."
	)

	ragdoll.take_damage(50.0, Vector3(0.0, 1.45, 0.0), Vector3.BACK)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(ragdoll.is_ragdoll_active, "Ragdoll simulation must activate after taking damage.")
	assert_gt(
		chest_bone.linear_velocity.length_squared(),
		0.001,
		"Chest bone must register velocity from deferred impulse."
	)

	ragdoll.reset_ragdoll()
	await get_tree().physics_frame
	assert_false(ragdoll.is_ragdoll_active, "Ragdoll must return to standing A-pose after reset.")
