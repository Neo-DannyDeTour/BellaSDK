## Unit tests for the 2.0m articulated [BimboMannequin] scene and variant physical bone setup.
extends GutTest

const BIMBO_MANNEQUIN_SCENE: PackedScene = preload("res://interactables/bimbo_mannequin.tscn")


## Verifies 60 FPS invariants, Layer 3 setup, variant collider radii, and 17-bone ragdoll physics.
func test_bimbo_mannequin_setup_and_activation() -> void:
	var ragdoll: MannequinRagdoll = BIMBO_MANNEQUIN_SCENE.instantiate() as MannequinRagdoll
	add_child_autofree(ragdoll)

	assert_false(ragdoll.is_processing(), "Process must be disabled in _ready() for 60 FPS safety.")
	assert_false(
		ragdoll.is_physics_processing(),
		"Physics process must be disabled in _ready() for 60 FPS safety."
	)
	assert_false(ragdoll.is_ragdoll_active, "Bimbo mannequin must start standing in A-pose.")

	var skel: Skeleton3D = ragdoll.get_skeleton()
	if skel == null:
		pending("LFS bimbo_mannequin.glb unavailable in CI stub mode.")
		return
	assert_not_null(skel, "Skeleton3D must be present.")
	assert_eq(skel.get_bone_count(), 17, "Bimbo mannequin armature must have 17 articulated bones.")
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

	var chest_col: CollisionShape3D = (
		chest_bone.get_node_or_null("CollisionShape3D") as CollisionShape3D
	)
	assert_not_null(chest_col, "Chest bone must have a CollisionShape3D.")
	var chest_capsule: CapsuleShape3D = chest_col.shape as CapsuleShape3D
	assert_not_null(chest_capsule, "Chest collider must be a CapsuleShape3D.")
	assert_almost_eq(
		chest_capsule.radius,
		0.165,
		0.001,
		"Chest capsule radius must match bimbo variant override."
	)

	var waist_bone: PhysicalBone3D = ragdoll.get_physical_bone(&"Waist")
	assert_not_null(waist_bone, "Waist PhysicalBone3D must exist.")
	var waist_col: CollisionShape3D = (
		waist_bone.get_node_or_null("CollisionShape3D") as CollisionShape3D
	)
	var waist_capsule: CapsuleShape3D = waist_col.shape as CapsuleShape3D
	assert_almost_eq(
		waist_capsule.radius,
		0.088,
		0.001,
		"Waist capsule radius must match cinched waist override."
	)

	ragdoll.take_damage(50.0, Vector3(0.0, 1.45, 0.0), Vector3.BACK)
	await get_tree().process_frame
	var wait_attempts: int = 0
	while chest_bone.linear_velocity.length_squared() <= 0.001 and wait_attempts < 15:
		await get_tree().physics_frame
		wait_attempts += 1
	assert_true(ragdoll.is_ragdoll_active, "Ragdoll simulation must activate after taking damage.")
	assert_gt(
		chest_bone.linear_velocity.length_squared(),
		0.001,
		"Chest bone must register velocity from deferred impulse."
	)

	ragdoll.reset_ragdoll()
	await get_tree().physics_frame
	assert_false(ragdoll.is_ragdoll_active, "Ragdoll must return to standing A-pose after reset.")
