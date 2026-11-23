## Unit tests verifying Humanizer Godot 4.7.1 compatibility and PhysicalBoneSimulator3D.
class_name TestHumanizerGodot47
extends GutTest

## Path to the HumanizerAPI scene.
const HUMANIZER_API_SCENE_PATH: String = "res://addons/humanizer/scenes/humanizer_api.tscn"
## Default retargeted rig identifier.
const DEFAULT_RETARGETED_RIG: String = "default-RETARGETED"
## Game engine retargeted rig identifier.
const GAME_ENGINE_RETARGETED_RIG: String = "game_engine-RETARGETED"


## Verifies HumanizerAPI scene loads and instantiates cleanly with ViewportTextures child.
func test_humanizer_api_scene_instantiates_cleanly() -> void:
	print("TestHumanizerGodot47: Verifying humanizer_api.tscn instantiation.")
	var packed_scene: PackedScene = load(HUMANIZER_API_SCENE_PATH) as PackedScene
	assert_not_null(packed_scene, "humanizer_api.tscn should load as PackedScene.")
	if packed_scene == null:
		return

	var api_node: Node = packed_scene.instantiate()
	assert_not_null(api_node, "HumanizerAPI scene should instantiate.")
	if api_node == null:
		return
	add_child_autofree(api_node)

	var viewport_textures: Node = api_node.get_node_or_null("ViewportTextures")
	assert_not_null(viewport_textures, "HumanizerAPI should contain ViewportTextures child.")


## Verifies HumanizerRegistry loads default-RETARGETED and game_engine-RETARGETED rigs.
func test_humanizer_registry_loads_rigs() -> void:
	print("TestHumanizerGodot47: Verifying HumanizerRegistry._get_rigs().")
	HumanizerRegistry._get_rigs()
	assert_true(
		HumanizerRegistry.rigs.has(DEFAULT_RETARGETED_RIG),
		"HumanizerRegistry should contain default-RETARGETED rig."
	)
	assert_true(
		HumanizerRegistry.rigs.has(GAME_ENGINE_RETARGETED_RIG),
		"HumanizerRegistry should contain game_engine-RETARGETED rig."
	)

	var raw_default: Variant = HumanizerRegistry.rigs.get(DEFAULT_RETARGETED_RIG)
	var default_rig: HumanizerRig = raw_default if raw_default is HumanizerRig else null
	assert_not_null(default_rig, "default-RETARGETED should be a valid HumanizerRig.")

	var raw_game_engine: Variant = HumanizerRegistry.rigs.get(GAME_ENGINE_RETARGETED_RIG)
	var game_engine_rig: HumanizerRig = raw_game_engine if raw_game_engine is HumanizerRig else null
	assert_not_null(game_engine_rig, "game_engine-RETARGETED should be a valid HumanizerRig.")


## Verifies HumanizerPhysicalSkeleton builds PhysicalBoneSimulator3D with PhysicalBone3D children.
func test_physical_skeleton_builds_simulator_and_bones() -> void:
	print("TestHumanizerGodot47: Verifying HumanizerPhysicalSkeleton uses PhysicalBoneSimulator3D.")
	var skeleton: Skeleton3D = Skeleton3D.new()
	skeleton.name = "GeneralSkeleton"
	add_child_autofree(skeleton)

	var hips_idx: int = skeleton.add_bone("Hips")
	var chest_idx: int = skeleton.add_bone("UpperChest")
	var neck_idx: int = skeleton.add_bone("Neck")
	var head_idx: int = skeleton.add_bone("Head")
	var head_top_idx: int = skeleton.add_bone("HeadTop")

	skeleton.set_bone_parent(chest_idx, hips_idx)
	skeleton.set_bone_parent(neck_idx, chest_idx)
	skeleton.set_bone_parent(head_idx, neck_idx)
	skeleton.set_bone_parent(head_top_idx, head_idx)

	skeleton.set_bone_rest(hips_idx, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	skeleton.set_bone_rest(chest_idx, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)))
	skeleton.set_bone_rest(neck_idx, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0)))
	skeleton.set_bone_rest(head_idx, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 0.0)))
	skeleton.set_bone_rest(head_top_idx, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.15, 0.0)))
	skeleton.reset_bone_poses()

	var helper_vertices: Array = []
	var phys_builder: HumanizerPhysicalSkeleton = HumanizerPhysicalSkeleton.new(
		skeleton, helper_vertices, 1, 1
	)
	phys_builder.run()

	var simulator: PhysicalBoneSimulator3D = null
	var direct_phys_bones: int = 0
	for child: Node in skeleton.get_children():
		if child is PhysicalBoneSimulator3D:
			simulator = child as PhysicalBoneSimulator3D
		elif child is PhysicalBone3D:
			direct_phys_bones += 1

	assert_not_null(
		simulator, "Skeleton3D should have a PhysicalBoneSimulator3D child in Godot 4.7."
	)
	assert_eq(
		direct_phys_bones, 0, "PhysicalBone3D nodes should not be direct children of Skeleton3D."
	)
	if simulator == null:
		return

	var bone_count: int = 0
	for sim_child: Node in simulator.get_children():
		if sim_child is PhysicalBone3D:
			bone_count += 1

	assert_gt(
		bone_count, 0, "PhysicalBoneSimulator3D should contain created PhysicalBone3D children."
	)
