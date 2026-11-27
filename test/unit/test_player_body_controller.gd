## GUT unit tests for [PlayerBodyController], [bella_player.tscn], and [player.tscn] wiring.
class_name TestPlayerBodyController
extends GutTest

## Preloaded NPC Bella scene verified untouched.
const BELLA_NPC_SCENE: PackedScene = preload("res://npcs/bella/bella.tscn")
## Preloaded player Bella body scene under test.
const BELLA_PLAYER_SCENE: PackedScene = preload("res://npcs/bella/bella_player.tscn")
## Preloaded main FPS player scene verified for integration wiring.
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

## Expected 7 modular meshes remaining in [bella_player.glb].
const EXPECTED_PLAYER_MESHES: Array[String] = [
	"Bella_Arms",
	"Bella_Boots",
	"Bella_CollarShadow",
	"Bella_Dress",
	"Bella_Gloves",
	"Bella_Skirt",
	"Bella_TorsoLegs",
]

## Head, face, hair, and glasses meshes that must be stripped from [bella_player.glb].
const STRIPPED_HEAD_MESHES: Array[String] = [
	"Bella_Body",
	"Bella_Head",
	"Bella_Eye_L",
	"Bella_Eye_R",
	"Bella_Eyelashes",
	"Bella_Teeth_Upper",
	"Bella_Teeth_Lower",
	"Bella_Tongue",
	"Bella_Hair_Cap",
	"Bella_Hair_Cards",
	"Bella_Glasses",
]

## Complete list of 11 expected 60 FPS looping animation clips.
const EXPECTED_CLIPS: Array[StringName] = [
	&"idle",
	&"walk_fwd",
	&"walk_back",
	&"strafe_left",
	&"strafe_right",
	&"run_fwd",
	&"crouch_idle",
	&"crouch_walk",
	&"jump_air",
	&"hold_revolver",
	&"hold_shotgun",
]


## Minimal mock [CharacterBody3D] supporting [member is_wolf_mode] and floor testing.
class MockBodyPlayer:
	extends CharacterBody3D

	## Mirrors [member Player.is_wolf_mode] for visibility toggle tests.
	var is_wolf_mode: bool = false


## Minimal mock firearm exposing [member weapon_tag] for initial inventory sync tests.
class MockEquippedWeapon:
	extends Node3D

	## Weapon identifier string read by [WeaponInventoryComponent] and [PlayerBodyController].
	var weapon_tag: String = "revolver"


## Verifies [bella.tscn] NPC rig and facial nodes remain untouched.
func test_bella_npc_scene_untouched() -> void:
	var npc: NpcActor = BELLA_NPC_SCENE.instantiate() as NpcActor
	assert_not_null(npc, "bella.tscn root must remain NpcActor.")
	add_child_autofree(npc)

	var model: Node3D = npc.get_node_or_null(^"BellaModel") as Node3D
	assert_not_null(model, "bella.tscn must keep BellaModel.")
	assert_not_null(
		model.find_child("Bella_Body", true, false), "bella.tscn must still have Bella_Body."
	)
	assert_not_null(
		model.find_child("Bella_Head", true, false), "bella.tscn must still have Bella_Head."
	)
	assert_not_null(
		npc.get_node_or_null(^"FaceRigController"), "bella.tscn must keep FaceRigController."
	)
	assert_null(npc.get_node_or_null(^"HeadCubeAttachment"), "bella.tscn must have no HeadCube.")


## Verifies [bella_player.tscn] meshes, render layers, HeadCube, and bone attachments.
func test_bella_player_meshes_layers_and_head_cube() -> void:
	var body: PlayerBodyController = BELLA_PLAYER_SCENE.instantiate() as PlayerBodyController
	assert_not_null(body, "bella_player.tscn root must be PlayerBodyController.")
	add_child_autofree(body)

	assert_false(body.is_processing(), "PlayerBodyController must disable _process().")
	assert_true(body.is_physics_processing(), "PlayerBodyController requires _physics_process().")
	assert_null(
		body.find_child("CollisionShape3D", true, false),
		"bella_player.tscn must not duplicate physics colliders."
	)
	assert_null(
		body.find_child("FaceRigController", true, false),
		"bella_player.tscn must not include FaceRigController."
	)

	var model: Node3D = body.model_root
	assert_not_null(model, "model_root must be wired.")
	for mesh_name: String in EXPECTED_PLAYER_MESHES:
		assert_not_null(
			model.find_child(mesh_name, true, false) as MeshInstance3D,
			"Missing player body mesh: " + mesh_name
		)
	for stripped_name: String in STRIPPED_HEAD_MESHES:
		assert_null(
			model.find_child(stripped_name, true, false),
			"Head/split mesh must not exist in bella_player.glb: " + stripped_name
		)

	for env_name: StringName in PlayerBodyController.ENV_LAYER_MESHES:
		var env_mesh: MeshInstance3D = (
			model.find_child(String(env_name), true, false) as MeshInstance3D
		)
		assert_eq(
			env_mesh.layers,
			CollisionLayers.RENDER_MASK_ENVIRONMENT,
			String(env_name) + " must render on Layer 1."
		)

	for player_name: StringName in PlayerBodyController.PLAYER_LAYER_MESHES:
		var p_mesh: MeshInstance3D = (
			model.find_child(String(player_name), true, false) as MeshInstance3D
		)
		assert_not_null(p_mesh, "Missing PLAYER_LAYER_MESHES node: " + String(player_name))
		assert_eq(
			p_mesh.layers,
			CollisionLayers.RENDER_MASK_PLAYER,
			String(player_name) + " must render on Layer 2."
		)
		assert_eq(
			p_mesh.cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			String(player_name) + " must cast shadows."
		)

	var collar_mesh: MeshInstance3D = (
		model.find_child("Bella_CollarShadow", true, false) as MeshInstance3D
	)
	assert_not_null(collar_mesh, "Bella_CollarShadow mesh must exist in bella_player.glb.")
	assert_eq(
		collar_mesh.layers,
		CollisionLayers.RENDER_MASK_PLAYER,
		"Bella_CollarShadow must render on Layer 2."
	)
	assert_eq(
		collar_mesh.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"Bella_CollarShadow must cast shadows."
	)

	var head_cube: MeshInstance3D = (
		body.head_cube_attachment.get_node_or_null(^"HeadCube") as MeshInstance3D
	)
	assert_not_null(head_cube, "HeadCube must exist under HeadCubeAttachment.")
	assert_eq(head_cube.layers, CollisionLayers.RENDER_MASK_PLAYER, "HeadCube must be Layer 2.")
	assert_eq(
		head_cube.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"HeadCube must cast shadows."
	)
	var box_mesh: BoxMesh = head_cube.mesh as BoxMesh
	assert_not_null(box_mesh, "HeadCube must use BoxMesh.")
	assert_eq(box_mesh.size, Vector3(0.32, 0.32, 0.32), "HeadCube size must be 0.32m cube.")
	var mat: StandardMaterial3D = box_mesh.material as StandardMaterial3D
	assert_not_null(mat, "HeadCube BoxMesh must have StandardMaterial3D.")
	assert_eq(
		mat.shading_mode,
		BaseMaterial3D.SHADING_MODE_UNSHADED,
		"HeadCube material must be unshaded."
	)
	assert_eq(mat.albedo_color, Color(0, 0, 0, 1), "HeadCube albedo must be pure black.")

	var skel: Skeleton3D = body.get_skeleton()
	assert_not_null(skel, "Skeleton3D must resolve inside BellaModel.")
	assert_true(
		body.head_cube_attachment.use_external_skeleton,
		"HeadCubeAttachment must enable use_external_skeleton."
	)
	assert_eq(
		body.head_cube_attachment.get_external_skeleton(),
		skel.get_path(),
		"HeadCubeAttachment must bind to _skeleton.get_path()."
	)
	assert_gte(body.head_cube_attachment.bone_idx, 0, "Head bone index must resolve.")
	assert_eq(
		body.right_hand_attachment.get_external_skeleton(),
		skel.get_path(),
		"RightHandAttachment must bind to _skeleton.get_path()."
	)
	assert_gte(body.right_hand_attachment.bone_idx, 0, "RightHand bone index must resolve.")

	assert_false(body.world_revolver.visible, "WorldRevolver must start hidden.")
	assert_false(body.world_shotgun.visible, "WorldShotgun must start hidden.")
	var rev_meshes: Array[Node] = body.world_revolver.find_children(
		"*", "MeshInstance3D", true, false
	)
	assert_gt(rev_meshes.size(), 0, "WorldRevolver must contain MeshInstance3D nodes.")
	for rev_node: Node in rev_meshes:
		var rev_mesh: MeshInstance3D = rev_node as MeshInstance3D
		assert_eq(
			rev_mesh.layers,
			CollisionLayers.RENDER_MASK_PLAYER,
			"WorldRevolver mesh must be Layer 2."
		)
		assert_eq(
			rev_mesh.cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"WorldRevolver mesh must cast shadows."
		)

	var sg_mesh: MeshInstance3D = body.world_shotgun as MeshInstance3D
	assert_not_null(sg_mesh, "WorldShotgun must be a MeshInstance3D.")
	assert_eq(sg_mesh.layers, CollisionLayers.RENDER_MASK_PLAYER, "WorldShotgun must be Layer 2.")
	assert_eq(
		sg_mesh.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"WorldShotgun must cast shadows."
	)


## Verifies all 11 looping clips and runtime [AnimationNodeBlendTree] graph setup.
func test_11_clips_and_animation_tree_graph() -> void:
	var body: PlayerBodyController = BELLA_PLAYER_SCENE.instantiate() as PlayerBodyController
	add_child_autofree(body)

	var anim_player: AnimationPlayer = (
		body.model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	)
	assert_not_null(anim_player, "AnimationPlayer must exist in BellaModel.")
	for clip_name: StringName in EXPECTED_CLIPS:
		assert_true(anim_player.has_animation(clip_name), "Missing clip: " + String(clip_name))
		var anim: Animation = anim_player.get_animation(clip_name)
		assert_eq(
			anim.loop_mode,
			Animation.LOOP_LINEAR,
			String(clip_name) + " must be configured as LOOP_LINEAR."
		)

	var tree: AnimationTree = body.get_animation_tree()
	assert_not_null(tree, "Runtime AnimationTree must be created.")
	assert_true(tree.active, "AnimationTree must be active.")

	var blend_tree: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	assert_not_null(blend_tree, "tree_root must be AnimationNodeBlendTree.")
	assert_true(blend_tree.has_node(&"state_machine"), "Missing state_machine node.")
	assert_true(blend_tree.has_node(&"weapon_blend"), "Missing weapon_blend node.")
	assert_true(blend_tree.has_node(&"weapon_pose"), "Missing weapon_pose node.")

	var sm: AnimationNodeStateMachine = (
		blend_tree.get_node(&"state_machine") as AnimationNodeStateMachine
	)
	assert_not_null(sm, "state_machine must be AnimationNodeStateMachine.")
	assert_true(sm.has_node(&"locomotion"), "State machine missing locomotion BlendSpace2D.")
	assert_true(sm.has_node(&"crouch"), "State machine missing crouch BlendSpace1D.")
	assert_true(sm.has_node(&"air"), "State machine missing air state.")
	assert_true(
		sm.get_node(&"locomotion") is AnimationNodeBlendSpace2D,
		"locomotion node must be AnimationNodeBlendSpace2D."
	)
	assert_true(
		sm.get_node(&"crouch") is AnimationNodeBlendSpace1D,
		"crouch node must be AnimationNodeBlendSpace1D."
	)

	var weapon_blend: AnimationNodeBlend2 = (
		blend_tree.get_node(&"weapon_blend") as AnimationNodeBlend2
	)
	assert_not_null(weapon_blend, "weapon_blend must be AnimationNodeBlend2.")
	assert_true(weapon_blend.filter_enabled, "weapon_blend must enable bone filtering.")

	var skel_rel: String = String(body.model_root.get_path_to(body.get_skeleton()))
	assert_true(
		weapon_blend.is_path_filtered(NodePath(skel_rel + ":RightHand")),
		"RightHand must be filtered in weapon_blend."
	)
	assert_true(
		weapon_blend.is_path_filtered(NodePath(skel_rel + ":Spine")),
		"Spine must be filtered in weapon_blend."
	)
	assert_false(
		weapon_blend.is_path_filtered(NodePath(skel_rel + ":LeftUpperLeg")),
		"Lower-body LeftUpperLeg must NOT be filtered in weapon_blend."
	)


## Verifies standing 2D locomotion, crouch, air, wolf visibility, and camera pitch follow.
func test_locomotion_crouch_air_wolf_and_pitch_reactions() -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	add_child_autofree(floor_body)

	var mock_player: MockBodyPlayer = MockBodyPlayer.new()
	var player_col: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.64
	player_col.shape = cap
	player_col.position = Vector3(0.0, 0.82, 0.0)
	mock_player.add_child(player_col)
	add_child_autofree(mock_player)

	var loco: PlayerLocomotionComponent = PlayerLocomotionComponent.new()
	loco.walking_speed = 5.0
	loco.sprinting_speed = 6.5
	loco.crouching_speed = 3.0
	mock_player.add_child(loco)

	var head_node: Node3D = Node3D.new()
	mock_player.add_child(head_node)
	var cam_ctrl: CameraController = CameraController.new()
	cam_ctrl.player_body = mock_player
	cam_ctrl.head = head_node
	mock_player.add_child(cam_ctrl)

	var body: PlayerBodyController = BELLA_PLAYER_SCENE.instantiate() as PlayerBodyController
	body.player = mock_player
	body.locomotion_component = loco
	body.camera_controller = cam_ctrl
	mock_player.add_child(body)

	# Ground mock_player on the StaticBody3D floor
	mock_player.velocity = Vector3(0.0, -1.0, 0.0)
	mock_player.move_and_slide()
	assert_true(mock_player.is_on_floor(), "Mock player must touch test floor.")

	var tree: AnimationTree = body.get_animation_tree()
	_step_body_physics(body, Vector3.ZERO, 0.5, 5)
	assert_eq(body.get_current_state(), &"locomotion", "Standing should use locomotion state.")
	var blend_idle: Vector2 = tree.get(PlayerBodyController.PARAM_LOCOMOTION_BLEND) as Vector2
	assert_almost_eq(blend_idle.length(), 0.0, 0.05, "Idle velocity should map near (0, 0).")

	_step_body_physics(body, Vector3(0.0, 0.0, -5.0), 0.2, 6)
	var blend_walk: Vector2 = tree.get(PlayerBodyController.PARAM_LOCOMOTION_BLEND) as Vector2
	assert_almost_eq(blend_walk.x, 0.0, 0.05, "Forward walk X must be near 0.")
	assert_almost_eq(blend_walk.y, 1.0, 0.08, "Forward walk Y must map near 1.0.")

	_step_body_physics(body, Vector3(0.0, 0.0, -6.5), 0.2, 6)
	var blend_run: Vector2 = tree.get(PlayerBodyController.PARAM_LOCOMOTION_BLEND) as Vector2
	assert_gt(blend_run.y, 1.35, "Sprint velocity must push Y blend toward run_fwd (1.5).")

	_step_body_physics(body, Vector3(0.0, 0.0, 5.0), 0.2, 6)
	var blend_back: Vector2 = tree.get(PlayerBodyController.PARAM_LOCOMOTION_BLEND) as Vector2
	assert_lt(blend_back.y, -0.9, "Backward walk must map Y toward -1.0.")

	_step_body_physics(body, Vector3(-5.0, 0.0, 0.0), 0.2, 6)
	var blend_left: Vector2 = tree.get(PlayerBodyController.PARAM_LOCOMOTION_BLEND) as Vector2
	assert_lt(blend_left.x, -0.9, "Strafe left must map X toward -1.0.")

	_step_body_physics(body, Vector3(5.0, 0.0, 0.0), 0.2, 6)
	var blend_right: Vector2 = tree.get(PlayerBodyController.PARAM_LOCOMOTION_BLEND) as Vector2
	assert_gt(blend_right.x, 0.9, "Strafe right must map X toward +1.0.")

	# Crouch idle & crouch walk
	loco.crouching = true
	_step_body_physics(body, Vector3.ZERO, 0.2, 6)
	assert_eq(body.get_current_state(), &"crouch", "Crouching must transition to crouch state.")
	var crouch_idle_val: float = float(tree.get(PlayerBodyController.PARAM_CROUCH_BLEND))
	assert_almost_eq(crouch_idle_val, 0.0, 0.05, "Stationary crouch must blend near 0.0.")

	_step_body_physics(body, Vector3(0.0, 0.0, -3.0), 0.2, 6)
	var crouch_walk_val: float = float(tree.get(PlayerBodyController.PARAM_CROUCH_BLEND))
	assert_gt(crouch_walk_val, 0.9, "Moving at crouching_speed must blend toward 1.0.")

	# Airborne state
	loco.crouching = false
	mock_player.global_position = Vector3(0.0, 4.0, 0.0)
	mock_player.velocity = Vector3(0.0, 2.0, 0.0)
	mock_player.move_and_slide()
	assert_false(mock_player.is_on_floor(), "Elevated player must be airborne.")
	_step_body_physics(body, Vector3(0.0, 2.0, 0.0), 0.2, 4)
	assert_eq(body.get_current_state(), &"air", "Airborne player must enter air state.")

	# Wolf mode visibility hide/restore
	mock_player.is_wolf_mode = true
	body._physics_process(0.016)
	assert_false(body.visible, "Wolf mode must hide BellaPlayer body.")
	mock_player.is_wolf_mode = false
	body._physics_process(0.016)
	assert_true(body.visible, "Exiting wolf mode must restore BellaPlayer visibility.")

	# Camera pitch follow updates Head bone upward when head.rotation.x > 0
	var skel: Skeleton3D = body.get_skeleton()
	var head_idx: int = skel.find_bone("Head")
	head_node.rotation.x = 0.0
	_step_body_physics(body, Vector3.ZERO, 0.1, 12)
	await get_tree().physics_frame
	await get_tree().process_frame
	var neutral_pos: Vector3 = body.position
	var neutral_head_fwd: Vector3 = (
		(body.global_transform.affine_inverse() * body.head_cube_attachment.global_transform)
		. basis
		. z
	)

	head_node.rotation.x = 0.6
	_step_body_physics(body, Vector3.ZERO, 0.1, 10)
	await get_tree().physics_frame
	await get_tree().process_frame
	var pitched_head_fwd: Vector3 = (
		(body.global_transform.affine_inverse() * body.head_cube_attachment.global_transform)
		. basis
		. z
	)
	assert_gt(
		pitched_head_fwd.y,
		neutral_head_fwd.y + 0.08,
		"Looking up (head.rotation.x > 0) must pitch Head bone upward."
	)
	assert_gte(head_idx, 0, "Head bone index must remain valid.")

	# Looking straight down shifts BellaBody backward (+Z) cleanly without hunching Chest
	head_node.rotation.x = -1.45
	_step_body_physics(body, Vector3.ZERO, 0.1, 12)
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_gt(
		body.position.z,
		neutral_pos.z + 0.04,
		"Looking down (-83 deg) must shift BellaBody local +Z backward to frame chest."
	)
	var look_down_head_fwd: Vector3 = (
		(body.global_transform.affine_inverse() * body.head_cube_attachment.global_transform)
		. basis
		. z
	)
	assert_lt(
		look_down_head_fwd.y,
		neutral_head_fwd.y - 0.10,
		"Looking down must pitch Head bone downward."
	)


## Verifies weapon equip signal switching, upper-body blend, and initial inventory sync.
func test_weapon_equip_reactions_and_initial_sync() -> void:
	var inv_holder: Node3D = Node3D.new()
	add_child_autofree(inv_holder)
	var inv: WeaponInventoryComponent = WeaponInventoryComponent.new()
	inv.weapon_holder = inv_holder
	var mock_rev: MockEquippedWeapon = MockEquippedWeapon.new()
	mock_rev.weapon_tag = "revolver"
	inv_holder.add_child(mock_rev)
	inv.slots[0] = mock_rev
	inv.current_slot_index = 0
	add_child_autofree(inv)

	var mock_player: MockBodyPlayer = MockBodyPlayer.new()
	add_child_autofree(mock_player)

	var body: PlayerBodyController = BELLA_PLAYER_SCENE.instantiate() as PlayerBodyController
	body.player = mock_player
	body.weapon_inventory_component = inv
	add_child_autofree(body)

	var tree: AnimationTree = body.get_animation_tree()
	assert_true(body.world_revolver.visible, "Initial revolver slot must show WorldRevolver.")
	assert_false(body.world_shotgun.visible, "WorldShotgun must remain hidden initially.")
	assert_almost_eq(
		float(tree.get(PlayerBodyController.PARAM_WEAPON_BLEND)),
		1.0,
		0.05,
		"Initial equipped revolver must snap weapon_blend to 1.0."
	)

	Events.active_weapon_changed.emit("shotgun")
	for i: int in range(6):
		body._physics_process(0.1)
		tree.advance(0.1)
	assert_false(body.world_revolver.visible, "Equipping shotgun must hide WorldRevolver.")
	assert_true(body.world_shotgun.visible, "Equipping shotgun must show WorldShotgun.")
	assert_eq(
		String(tree.get(&"parameters/weapon_pose/current_state")),
		"shotgun",
		"weapon_pose transition must select shotgun."
	)

	Events.active_weapon_changed.emit("smoke_grenade")
	for i: int in range(10):
		body._physics_process(0.1)
		tree.advance(0.1)
	assert_false(body.world_revolver.visible, "Non-firearm must hide WorldRevolver.")
	assert_false(body.world_shotgun.visible, "Non-firearm must hide WorldShotgun.")
	assert_lt(
		float(tree.get(PlayerBodyController.PARAM_WEAPON_BLEND)),
		0.05,
		"Unarmed/non-firearm must blend weapon_blend back to 0.0."
	)

	Events.active_weapon_changed.emit("revolver")
	for i: int in range(10):
		body._physics_process(0.1)
		tree.advance(0.1)
	assert_true(body.world_revolver.visible, "Re-equipping revolver must show WorldRevolver.")
	assert_eq(
		String(tree.get(&"parameters/weapon_pose/current_state")),
		"revolver",
		"weapon_pose transition must select revolver."
	)
	assert_gt(
		float(tree.get(PlayerBodyController.PARAM_WEAPON_BLEND)),
		0.95,
		"Equipping revolver must blend weapon_blend back to 1.0."
	)


## Verifies [player.tscn] hides Sprite3D, excludes Layer 2 on Camera3D, and wires BellaBody.
func test_player_scene_integration() -> void:
	var p: Player = PLAYER_SCENE.instantiate() as Player
	assert_not_null(p, "player.tscn root must be Player.")
	add_child_autofree(p)
	await get_tree().process_frame

	var sprite: Sprite3D = p.get_node_or_null(^"Sprite3D") as Sprite3D
	assert_not_null(sprite, "Sprite3D node must still exist in player.tscn.")
	assert_false(sprite.visible, "Sprite3D placeholder must be hidden.")

	var cam: Camera3D = p.get_node_or_null(^"Head/Eyes/Camera3D") as Camera3D
	assert_not_null(cam, "Player Camera3D must exist.")
	assert_eq(cam.cull_mask, 1048573, "Player Camera3D must exclude Render Layer 2.")
	assert_lte(cam.near, 0.03, "Player Camera3D near clip must be <= 0.03m to avoid chest clip.")

	var bella_body: PlayerBodyController = p.get_node_or_null(^"BellaBody") as PlayerBodyController
	assert_not_null(bella_body, "player.tscn must instance BellaBody as PlayerBodyController.")
	assert_eq(
		bella_body.position, Vector3(0.0, 0.0, 0.08), "BellaBody must sit at Z=+0.08m offset."
	)
	assert_eq(bella_body.player, p, "BellaBody.player must wire to Player.")
	assert_eq(
		bella_body.locomotion_component,
		p.locomotion_component,
		"BellaBody.locomotion_component must wire to LocomotionComponent."
	)
	assert_eq(
		bella_body.camera_controller,
		p.camera_controller,
		"BellaBody.camera_controller must wire to CameraController."
	)
	assert_eq(
		bella_body.weapon_inventory_component,
		p.weapon_inventory_component,
		"BellaBody.weapon_inventory_component must wire to WeaponInventoryComponent."
	)

	Events.wolf_mode_toggled.emit(true)
	bella_body._physics_process(0.016)
	assert_false(bella_body.visible, "Wolf mode event must hide BellaBody.")
	Events.wolf_mode_toggled.emit(false)
	bella_body._physics_process(0.016)
	assert_true(bella_body.visible, "Leaving wolf mode must restore BellaBody.")


## Advances [param body] physics multiple steps at [param vel] and advances its [AnimationTree].
func _step_body_physics(
	body: PlayerBodyController, vel: Vector3, step_delta: float, steps: int
) -> void:
	body.player.velocity = vel
	var tree: AnimationTree = body.get_animation_tree()
	for i: int in range(steps):
		body._physics_process(step_delta)
		if is_instance_valid(tree):
			tree.advance(step_delta)
