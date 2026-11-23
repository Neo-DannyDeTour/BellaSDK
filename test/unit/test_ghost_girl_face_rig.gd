## GUT tests for GhostGirl scene, Humanizer integration, preview studio, and ARKit recording.
extends GutTest

## Preloaded GhostGirl NPC scene under test.
const GHOST_GIRL_SCENE: PackedScene = preload("res://npcs/ghost_girl/ghost_girl.tscn")
## Preloaded GhostGirl face preview studio scene under test.
const PREVIEW_SCENE: PackedScene = preload("res://scenes/ghost_girl_face_preview.tscn")
## Temporary user directory for saved facial [Animation] test clips.
const TEST_SAVE_DIR: String = "user://test_ghost_girl_facial_clips"
## Target Humanizer key registered by [code]import_ghost_girl_humanizer.gd[/code].
const HUMANIZER_TARGET_KEY: String = "custom_ghost_girl_anime"
## Humanizer rig preset compatible with [code]face_animation_tree.tscn[/code].
const HUMANIZER_RIG_NAME: String = "default-RETARGETED"
## Humanizer skin material name registered under [code]Body-Default[/code].
const HUMANIZER_SKIN_MAT: String = "ghost_girl_anime_skin"

## Complete list of 27 expected humanoid and facial bones in GhostGirl's skeleton.
const EXPECTED_BASE_BONES: Array[String] = [
	"Root",
	"Hips",
	"Spine",
	"Chest",
	"Neck",
	"Head",
	"LeftEye",
	"RightEye",
	"Jaw",
	"Tongue_01",
	"Tongue_02",
	"LeftShoulder",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightShoulder",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"LeftToes",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
	"RightToes",
]

## Three secondary cape drape bones parented under Chest.
const EXPECTED_CAPE_BONES: Array[String] = [
	"Cape_L",
	"Cape_C",
	"Cape_R",
]

## All 16 modular [MeshInstance3D] nodes inside GhostGirlModel.
const EXPECTED_MODULAR_MESHES: Array[String] = [
	"GhostGirl_Body",
	"GhostGirl_Head",
	"GhostGirl_Eye_L",
	"GhostGirl_Eye_R",
	"GhostGirl_Eyelashes",
	"GhostGirl_Teeth_Upper",
	"GhostGirl_Teeth_Lower",
	"GhostGirl_Tongue",
	"GhostGirl_Hair_Cap",
	"GhostGirl_Hair_Cards",
	"GhostGirl_Hood",
	"GhostGirl_Cape",
	"GhostGirl_CropTop",
	"GhostGirl_Skirt",
	"GhostGirl_Gloves",
	"GhostGirl_Boots",
]

## Compiled GhostGirl Humanizer equipment identifiers registered in [HumanizerRegistry].
const EXPECTED_HUMANIZER_EQUIPS: Array[String] = [
	"GhostGirl_Hair_Cards",
	"GhostGirl_Hood",
	"GhostGirl_Cape",
	"GhostGirl_CropTop",
	"GhostGirl_Skirt",
	"GhostGirl_Gloves",
	"GhostGirl_Boots",
	"GhostGirl_Eye_L",
	"GhostGirl_Eye_R",
	"GhostGirl_Eyelashes",
]

## Six eyelid ARKit blendshape keys mirrored onto GhostGirl_Eyelashes.
const EYELASH_6_SHAPES: Array[StringName] = [
	&"eyeBlinkLeft",
	&"eyeBlinkRight",
	&"eyeWideLeft",
	&"eyeWideRight",
	&"eyeSquintLeft",
	&"eyeSquintRight",
]

## Non-zero default parameters in [code]face_animation_tree.tscn[/code] cleared on ready.
const NOISY_HUMANIZER_PARAMS: Array[StringName] = [
	&"parameters/eyeBlinkLeft/add_amount",
	&"parameters/eyeBlinkRight/add_amount",
	&"parameters/eyeSquintLeft/add_amount",
	&"parameters/eyeSquintRight/add_amount",
	&"parameters/headUp/add_amount",
	&"parameters/headLeft/add_amount",
	&"parameters/mouthSmileRight/add_amount",
	&"parameters/jawOpen/add_amount",
	&"parameters/browInnerUpLeft/add_amount",
	&"parameters/browInnerUpRight/add_amount",
]


## Removes any temporary `.res` test clips saved under [constant TEST_SAVE_DIR].
func after_all() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(TEST_SAVE_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		var dir: DirAccess = DirAccess.open(TEST_SAVE_DIR)
		if is_instance_valid(dir):
			dir.list_dir_begin()
			var file_name: String = dir.get_next()
			while not file_name.is_empty():
				if not dir.current_is_dir():
					dir.remove(file_name)
				file_name = dir.get_next()
			dir.list_dir_end()


## Verifies GhostGirl root [NpcActor], 27 base + 3 cape bones, and all 16 modular meshes.
func test_ghost_girl_scene_bones_and_modular_meshes() -> void:
	var inst: Node = GHOST_GIRL_SCENE.instantiate()
	assert_true(inst is NpcActor, "ghost_girl.tscn root must be NpcActor.")
	var ghost_girl: NpcActor = inst as NpcActor
	add_child_autofree(ghost_girl)

	assert_eq(ghost_girl.chest_bone_name, "Chest", "GhostGirl chest_bone_name must be Chest.")
	assert_eq(ghost_girl.head_bone_name, "Head", "GhostGirl head_bone_name must be Head.")

	var skel: Skeleton3D = ghost_girl.get_skeleton()
	assert_not_null(skel, "NpcActor.get_skeleton() must return valid Skeleton3D.")
	var expected_total: int = EXPECTED_BASE_BONES.size() + EXPECTED_CAPE_BONES.size()
	assert_eq(
		skel.get_bone_count(),
		expected_total,
		"GhostGirl Skeleton3D must have 27 humanoid/facial bones plus 3 cape bones.",
	)
	for bone_name: String in EXPECTED_BASE_BONES:
		assert_gte(skel.find_bone(bone_name), 0, "Missing Skeleton3D base bone: " + bone_name)
	for cape_bone: String in EXPECTED_CAPE_BONES:
		assert_gte(skel.find_bone(cape_bone), 0, "Missing Skeleton3D cape bone: " + cape_bone)

	var model_root: Node3D = ghost_girl.get_node_or_null(^"GhostGirlModel") as Node3D
	assert_not_null(model_root, "GhostGirl must contain GhostGirlModel child node.")
	for mesh_name: String in EXPECTED_MODULAR_MESHES:
		var mesh_node: MeshInstance3D = (
			model_root.find_child(mesh_name, true, false) as MeshInstance3D
		)
		assert_not_null(mesh_node, "GhostGirlModel missing modular MeshInstance3D: " + mesh_name)

	var face_ctrl: FaceRigController = (
		ghost_girl.get_node_or_null(^"FaceRigController") as FaceRigController
	)
	assert_not_null(face_ctrl, "GhostGirl must contain FaceRigController child node.")
	assert_eq(
		face_ctrl.get_rig_backend(),
		FaceRigController.RigBackend.BLENDSHAPE,
		"GhostGirl FaceRigController must select RigBackend.BLENDSHAPE.",
	)
	assert_gte(face_ctrl.get_jaw_bone_index(), 0, "GhostGirl Jaw bone index must resolve >= 0.")
	assert_not_null(face_ctrl.get_head_mesh(), "FaceRigController.get_head_mesh() must resolve.")
	assert_not_null(
		face_ctrl.get_eyelash_mesh(), "FaceRigController.get_eyelash_mesh() must resolve."
	)


## Verifies 52 ARKit shapes, 6 eyelash shapes, eyelash sync, Jaw coupling, and 52-float apply.
func test_ghost_girl_arkit_52_eyelash_sync_and_jaw_coupling() -> void:
	var ghost_girl: NpcActor = GHOST_GIRL_SCENE.instantiate() as NpcActor
	add_child_autofree(ghost_girl)
	var face_ctrl: FaceRigController = (
		ghost_girl.get_node_or_null(^"FaceRigController") as FaceRigController
	)
	assert_not_null(face_ctrl, "FaceRigController must exist.")
	watch_signals(face_ctrl)

	var head_mesh: MeshInstance3D = face_ctrl.get_head_mesh()
	var lash_mesh: MeshInstance3D = face_ctrl.get_eyelash_mesh()
	assert_not_null(head_mesh, "GhostGirl_Head MeshInstance3D must resolve.")
	assert_not_null(lash_mesh, "GhostGirl_Eyelashes MeshInstance3D must resolve.")

	assert_eq(
		head_mesh.get_blend_shape_count(),
		FaceRigController.ARKIT_52_KEYS.size(),
		"GhostGirl_Head must expose 52 ARKit blendshapes.",
	)
	var available: Array[StringName] = face_ctrl.get_available_blendshapes()
	assert_eq(
		available.size(),
		FaceRigController.ARKIT_52_KEYS.size(),
		"FaceRigController must cache all 52 ARKit blendshapes.",
	)
	for shape_key: StringName in FaceRigController.ARKIT_52_KEYS:
		assert_gte(
			head_mesh.find_blend_shape_by_name(shape_key),
			0,
			"GhostGirl_Head missing blendshape: " + String(shape_key),
		)
		assert_true(
			available.has(shape_key),
			"get_available_blendshapes() missing: " + String(shape_key),
		)

	assert_eq(
		lash_mesh.get_blend_shape_count(),
		EYELASH_6_SHAPES.size(),
		"GhostGirl_Eyelashes must expose 6 eyelid blendshapes.",
	)
	for lash_key: StringName in EYELASH_6_SHAPES:
		assert_gte(
			lash_mesh.find_blend_shape_by_name(lash_key),
			0,
			"GhostGirl_Eyelashes missing eyelid blendshape: " + String(lash_key),
		)

	face_ctrl.set_blendshape(&"eyeBlinkLeft", 0.75)
	var head_blink_idx: int = head_mesh.find_blend_shape_by_name(&"eyeBlinkLeft")
	var lash_blink_idx: int = lash_mesh.find_blend_shape_by_name(&"eyeBlinkLeft")
	assert_almost_eq(head_mesh.get_blend_shape_value(head_blink_idx), 0.75, 0.005)
	assert_almost_eq(lash_mesh.get_blend_shape_value(lash_blink_idx), 0.75, 0.005)
	assert_almost_eq(face_ctrl.get_blendshape_weight(&"eyeBlinkLeft"), 0.75, 0.005)

	var skel: Skeleton3D = ghost_girl.get_skeleton()
	var jaw_idx: int = face_ctrl.get_jaw_bone_index()
	var rest_rot: Quaternion = skel.get_bone_rest(jaw_idx).basis.get_rotation_quaternion()

	var frame52: PackedFloat32Array = PackedFloat32Array()
	frame52.resize(52)
	frame52.fill(0.0)
	frame52[0] = 0.40
	frame52[17] = 0.70
	frame52[23] = 0.85
	frame52[46] = 0.55
	face_ctrl.apply_arkit_weights(frame52)

	assert_almost_eq(face_ctrl.get_blendshape_weight(&"eyeBlinkLeft"), 0.40, 0.005)
	assert_almost_eq(
		lash_mesh.get_blend_shape_value(lash_blink_idx),
		0.40,
		0.005,
		"apply_arkit_weights() must sync eyelash blendshape weights.",
	)
	assert_almost_eq(face_ctrl.get_blendshape_weight(&"jawOpen"), 0.70, 0.005)
	assert_almost_eq(face_ctrl.get_blendshape_weight(&"mouthSmileLeft"), 0.85, 0.005)
	assert_almost_eq(face_ctrl.get_blendshape_weight(&"cheekPuff"), 0.55, 0.005)

	var jaw_open_rot: Quaternion = skel.get_bone_pose_rotation(jaw_idx)
	assert_gt(
		jaw_open_rot.angle_to(rest_rot),
		0.05,
		"jawOpen weight must rotate Jaw bone from rest pose.",
	)

	face_ctrl.set_expression(&"neutral", 0.0)
	assert_signal_emitted_with_parameters(face_ctrl, "expression_changed", [&"neutral"])
	var neutral_rot: Quaternion = skel.get_bone_pose_rotation(jaw_idx)
	assert_lt(neutral_rot.angle_to(rest_rot), 0.005, "Neutral must return Jaw bone to rest.")

	face_ctrl.trigger_blink()
	assert_signal_emitted(face_ctrl, "blink_triggered")


## Verifies idle process sleep, eye [LookAtModifier3D] setup, and visibility gating.
func test_ghost_girl_process_sleep_and_visibility_gating() -> void:
	var ghost_girl: NpcActor = GHOST_GIRL_SCENE.instantiate() as NpcActor
	add_child_autofree(ghost_girl)
	var face_ctrl: FaceRigController = (
		ghost_girl.get_node_or_null(^"FaceRigController") as FaceRigController
	)
	assert_not_null(face_ctrl, "FaceRigController must exist.")

	assert_false(
		face_ctrl.is_processing(),
		"FaceRigController._process() must sleep after _ready().",
	)
	assert_false(
		face_ctrl.is_physics_processing(),
		"FaceRigController._physics_process() must sleep after _ready().",
	)

	var skel: Skeleton3D = ghost_girl.get_skeleton()
	var eye_mods: Array[LookAtModifier3D] = face_ctrl.get_eye_look_modifiers()
	assert_eq(eye_mods.size(), 2, "FaceRigController must attach 2 eye LookAtModifier3D nodes.")

	var mod_names: Array[StringName] = []
	for mod: LookAtModifier3D in eye_mods:
		assert_eq(mod.get_parent(), skel, "Eye LookAtModifier3D must be child of Skeleton3D.")
		assert_true(mod.active, "Eye LookAtModifier3D must start active.")
		assert_true(mod.use_angle_limitation, "Eye modifier must enable angle limitation.")
		assert_eq(mod.forward_axis, SkeletonModifier3D.BONE_AXIS_PLUS_Z)
		mod_names.append(mod.name)
	assert_true(mod_names.has(&"LeftEyeLookAt"), "Missing LeftEyeLookAt modifier.")
	assert_true(mod_names.has(&"RightEyeLookAt"), "Missing RightEyeLookAt modifier.")

	var blink_timer: Timer = face_ctrl.get_node_or_null(^"BlinkTimer") as Timer
	assert_not_null(blink_timer, "BlinkTimer child node must exist under FaceRigController.")

	var notifier: VisibleOnScreenNotifier3D = (
		ghost_girl.get_node_or_null(^"VisibleOnScreenNotifier3D") as VisibleOnScreenNotifier3D
	)
	assert_not_null(notifier, "VisibleOnScreenNotifier3D must exist on GhostGirl.")

	notifier.screen_exited.emit()
	for mod: LookAtModifier3D in eye_mods:
		assert_false(mod.active, "screen_exited must disable eye LookAtModifier3D.")
	assert_true(blink_timer.is_stopped(), "screen_exited must stop BlinkTimer.")

	notifier.screen_entered.emit()
	for mod: LookAtModifier3D in eye_mods:
		assert_true(mod.active, "screen_entered must re-enable eye LookAtModifier3D.")
	assert_false(blink_timer.is_stopped(), "screen_entered must restart BlinkTimer.")


## Verifies Humanizer target/equipment registration, tree reset, and Add2 ARKit driving.
func test_humanizer_registration_build_reset_and_face_rig_drive() -> void:
	_ensure_humanizer_registry_loaded()

	assert_true(
		HumanizerTargetService.data.has(HUMANIZER_TARGET_KEY),
		"HumanizerTargetService.data must contain custom_ghost_girl_anime.",
	)
	assert_true(
		HumanizerRegistry.rigs.has(HUMANIZER_RIG_NAME),
		"HumanizerRegistry.rigs must contain default-RETARGETED.",
	)
	for equip_id: String in EXPECTED_HUMANIZER_EQUIPS:
		assert_true(
			HumanizerRegistry.equipment.has(equip_id),
			"HumanizerRegistry.equipment missing compiled asset: " + equip_id,
		)

	var human_body: CharacterBody3D = await _build_humanizer_ghost_girl()
	assert_not_null(human_body, "Humanizer must build CharacterBody3D on default-RETARGETED.")
	if not is_instance_valid(human_body):
		return

	var gen_skel: Skeleton3D = human_body.get_node_or_null(^"GeneralSkeleton") as Skeleton3D
	var anim_tree: AnimationTree = human_body.get_node_or_null(^"AnimationTree") as AnimationTree
	assert_not_null(gen_skel, "Humanizer rig must yield GeneralSkeleton.")
	assert_not_null(anim_tree, "Humanizer rig must yield AnimationTree.")

	var dirty_blink_r: float = _to_float(anim_tree.get(&"parameters/eyeBlinkRight/add_amount"))
	assert_gt(
		dirty_blink_r,
		0.5,
		"Pre-check: face_animation_tree.tscn ships with noisy eyeBlinkRight default.",
	)

	var face_ctrl: FaceRigController = FaceRigController.new()
	face_ctrl.name = "FaceRigController"
	face_ctrl.model_root = human_body
	face_ctrl.face_animation_tree = anim_tree
	face_ctrl.head_mesh_name = ""
	face_ctrl.eyelash_mesh_name = ""
	human_body.add_child(face_ctrl)
	add_child_autofree(human_body)

	assert_eq(
		face_ctrl.get_rig_backend(),
		FaceRigController.RigBackend.HUMANIZER_ANIM_TREE,
		"FaceRigController must select RigBackend.HUMANIZER_ANIM_TREE.",
	)
	assert_eq(face_ctrl.get_skeleton(), gen_skel)
	assert_eq(face_ctrl.get_face_animation_tree(), anim_tree)
	assert_null(face_ctrl.get_head_mesh())
	assert_true(anim_tree.active, "Humanizer AnimationTree must be active.")
	assert_false(face_ctrl.is_processing(), "Humanizer FaceRigController must sleep _process().")
	assert_false(
		face_ctrl.is_physics_processing(),
		"Humanizer FaceRigController must sleep _physics_process().",
	)

	for param_path: StringName in NOISY_HUMANIZER_PARAMS:
		var reset_val: float = _to_float(anim_tree.get(param_path))
		assert_almost_eq(
			reset_val,
			0.0,
			0.0001,
			"FaceRigController._ready() must zero noisy parameter: " + String(param_path),
		)

	face_ctrl.set_blendshape(&"eyeBlinkLeft", 0.72)
	face_ctrl.set_blendshape(&"jawOpen", 0.64)
	assert_almost_eq(
		_to_float(anim_tree.get(&"parameters/eyeBlinkLeft/add_amount")),
		0.72,
		0.005,
		"eyeBlinkLeft/add_amount must update to 0.72.",
	)
	assert_almost_eq(
		_to_float(anim_tree.get(&"parameters/jawOpen/add_amount")),
		0.64,
		0.005,
		"jawOpen/add_amount must update to 0.64.",
	)
	assert_almost_eq(face_ctrl.get_blendshape_weight(&"eyeBlinkLeft"), 0.72, 0.005)
	assert_almost_eq(face_ctrl.get_blendshape_weight(&"jawOpen"), 0.64, 0.005)

	var weights61: PackedFloat32Array = _make_arkit_weights(
		0.35, 0.50, 0.80, FaceRigController.HEAD_ROT_MAX_RAD * 0.5, 0.0, 0.0
	)
	face_ctrl.apply_arkit_weights(weights61)
	assert_almost_eq(_to_float(anim_tree.get(&"parameters/eyeBlinkLeft/add_amount")), 0.35, 0.005)
	assert_almost_eq(_to_float(anim_tree.get(&"parameters/jawOpen/add_amount")), 0.50, 0.005)
	assert_almost_eq(_to_float(anim_tree.get(&"parameters/headLeft/add_amount")), 0.50, 0.005)


## Verifies preview studio instantiation, H mode cycling, 1-6 expressions, V visemes, and ARKit.
func test_preview_scene_modes_expressions_visemes_and_synthetic_arkit() -> void:
	var preview_node: Node = PREVIEW_SCENE.instantiate()
	assert_true(
		preview_node is GhostGirlFacePreview,
		"ghost_girl_face_preview.tscn root must be GhostGirlFacePreview.",
	)
	var preview: GhostGirlFacePreview = preview_node as GhostGirlFacePreview
	add_child_autofree(preview)
	watch_signals(preview)

	assert_false(preview.is_processing(), "Preview _process() must sleep at idle.")
	assert_false(preview.is_physics_processing(), "Preview _physics_process() must sleep at idle.")

	var ghost_girl: NpcActor = preview.get_ghost_girl()
	var glb_rig: FaceRigController = preview.get_glb_face_rig()
	var hum_body: CharacterBody3D = preview.get_humanizer_body()
	var hum_rig: FaceRigController = preview.get_humanizer_face_rig()
	assert_not_null(ghost_girl, "Preview must instantiate GhostGirl.")
	assert_not_null(glb_rig, "Preview must resolve GhostGirl FaceRigController.")
	assert_not_null(hum_body, "Preview must build runtime Humanizer CharacterBody3D.")
	assert_not_null(hum_rig, "Preview must attach Humanizer FaceRigController.")

	assert_eq(preview.get_display_mode(), GhostGirlFacePreview.RigDisplayMode.BLENDSHAPE_GLB)
	assert_true(ghost_girl.visible)
	assert_false(hum_body.visible)

	preview._unhandled_input(_make_key_event(KEY_H))
	assert_eq(preview.get_display_mode(), GhostGirlFacePreview.RigDisplayMode.HUMANIZER)
	assert_false(ghost_girl.visible)
	assert_true(hum_body.visible)
	assert_signal_emitted_with_parameters(
		preview, "display_mode_changed", [GhostGirlFacePreview.RigDisplayMode.HUMANIZER]
	)

	preview._unhandled_input(_make_key_event(KEY_H))
	assert_eq(preview.get_display_mode(), GhostGirlFacePreview.RigDisplayMode.SIDE_BY_SIDE)
	assert_true(ghost_girl.visible)
	assert_true(hum_body.visible)
	assert_lt(ghost_girl.position.x, 0.0)
	assert_gt(hum_body.position.x, 0.0)

	preview._unhandled_input(_make_key_event(KEY_H))
	assert_eq(preview.get_display_mode(), GhostGirlFacePreview.RigDisplayMode.BLENDSHAPE_GLB)

	var expected_exprs: Dictionary[Key, StringName] = {
		KEY_2: &"happy",
		KEY_3: &"surprised",
		KEY_4: &"angry",
		KEY_5: &"sad",
		KEY_6: &"blink",
		KEY_1: &"neutral",
	}
	for expr_key: Key in [KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_1]:
		preview._unhandled_input(_make_key_event(expr_key))
		var target_expr: StringName = expected_exprs[expr_key]
		assert_eq(glb_rig.get_current_expression(), target_expr)
		assert_eq(hum_rig.get_current_expression(), target_expr)

	preview._unhandled_input(_make_key_event(KEY_2))
	await wait_seconds(0.25)
	assert_almost_eq(glb_rig.get_blendshape_weight(&"mouthSmileLeft"), 0.82, 0.02)
	assert_almost_eq(hum_rig.get_blendshape_weight(&"mouthSmileLeft"), 0.82, 0.02)

	preview._unhandled_input(_make_key_event(KEY_1))
	await wait_seconds(0.25)
	assert_almost_eq(glb_rig.get_blendshape_weight(&"mouthSmileLeft"), 0.0, 0.02)
	assert_almost_eq(hum_rig.get_blendshape_weight(&"mouthSmileLeft"), 0.0, 0.02)

	preview._unhandled_input(_make_key_event(KEY_V))
	assert_almost_eq(glb_rig.get_blendshape_weight(&"jawOpen"), 0.75, 0.005)
	assert_almost_eq(hum_rig.get_blendshape_weight(&"jawOpen"), 0.75, 0.005)

	preview._unhandled_input(_make_key_event(KEY_V))
	assert_almost_eq(glb_rig.get_blendshape_weight(&"mouthStretchLeft"), 0.65, 0.005)
	assert_almost_eq(glb_rig.get_blendshape_weight(&"mouthSmileLeft"), 0.30, 0.005)
	assert_almost_eq(hum_rig.get_blendshape_weight(&"mouthSmileLeft"), 0.30, 0.005)
	assert_almost_eq(hum_rig.get_blendshape_weight(&"jawOpen"), 0.22, 0.005)

	preview._unhandled_input(_make_key_event(KEY_V))
	assert_almost_eq(glb_rig.get_blendshape_weight(&"jawOpen"), 0.32, 0.005)
	assert_almost_eq(hum_rig.get_blendshape_weight(&"jawOpen"), 0.32, 0.005)
	assert_almost_eq(hum_rig.get_blendshape_weight(&"mouthUpperUpLeft"), 0.25, 0.005)

	preview._unhandled_input(_make_key_event(KEY_V))
	assert_almost_eq(glb_rig.get_blendshape_weight(&"mouthFunnel"), 0.80, 0.005)
	assert_almost_eq(hum_rig.get_blendshape_weight(&"mouthFunnel"), 0.80, 0.005)

	preview._unhandled_input(_make_key_event(KEY_V))
	assert_almost_eq(glb_rig.get_blendshape_weight(&"mouthPucker"), 0.85, 0.005)
	assert_almost_eq(hum_rig.get_blendshape_weight(&"mouthPucker"), 0.85, 0.005)

	preview._unhandled_input(_make_key_event(KEY_T))
	assert_true(preview.is_synthetic_sweep_active(), "T key must start synthetic ARKit sweep.")
	assert_true(preview.is_processing(), "Synthetic sweep must wake _process().")

	var pkt: ARKitPacket = preview.step_synthetic_arkit_frame(1.1)
	assert_not_null(pkt, "step_synthetic_arkit_frame() must return ARKitPacket.")
	assert_true(pkt.is_valid, "Synthetic ARKitPacket must be valid.")
	assert_eq(pkt.number_of_blendshapes, 61, "Synthetic ARKitPacket must hold 61 channels.")
	var expected_jaw: float = pkt.blendshapes_array[ARKitServer.BlendShape.JAW_OPEN]
	assert_almost_eq(glb_rig.get_blendshape_weight(&"jawOpen"), expected_jaw, 0.005)
	assert_almost_eq(hum_rig.get_blendshape_weight(&"jawOpen"), expected_jaw, 0.005)

	preview._unhandled_input(_make_key_event(KEY_T))
	assert_false(preview.is_synthetic_sweep_active(), "Second T key must stop synthetic sweep.")
	assert_false(preview.is_processing(), "Preview _process() must sleep after stopping sweep.")


## Verifies [method ARKitRecorder.configure_from_controller] for Blendshape and Humanizer rigs.
func test_arkit_recorder_configure_from_controller_both_modes() -> void:
	var preview: GhostGirlFacePreview = PREVIEW_SCENE.instantiate() as GhostGirlFacePreview
	add_child_autofree(preview)

	var ghost_girl: NpcActor = preview.get_ghost_girl()
	var glb_rig: FaceRigController = preview.get_glb_face_rig()
	var hum_body: CharacterBody3D = preview.get_humanizer_body()
	var hum_rig: FaceRigController = preview.get_humanizer_face_rig()
	assert_not_null(glb_rig)
	assert_not_null(hum_rig)

	var rec_glb: ARKitRecorder = ARKitRecorder.new()
	rec_glb.configure_from_controller(glb_rig)
	assert_false(rec_glb.record_humanizer_anim_tree)
	assert_true(rec_glb.anim_tree_path.is_empty())
	assert_eq(
		ghost_girl.get_node_or_null(NodePath(rec_glb.head_mesh_path)),
		glb_rig.get_head_mesh(),
		"GLB recorder head_mesh_path must resolve to GhostGirl_Head.",
	)
	assert_eq(
		ghost_girl.get_node_or_null(NodePath(rec_glb.lash_mesh_path)),
		glb_rig.get_eyelash_mesh(),
		"GLB recorder lash_mesh_path must resolve to GhostGirl_Eyelashes.",
	)
	assert_eq(
		ghost_girl.get_node_or_null(NodePath(rec_glb.skeleton_path)),
		glb_rig.get_skeleton(),
		"GLB recorder skeleton_path must resolve to Skeleton3D.",
	)

	rec_glb.start_recording("GG-GLB")
	for frame_i: int in range(3):
		var alpha: float = float(frame_i) * 0.4
		var weights_glb: PackedFloat32Array = _make_arkit_weights(
			alpha, alpha * 0.5, alpha * 0.8, 0.1 * alpha
		)
		var pkt_glb: ARKitPacket = ARKitPacket.new(
			ARKitPacket.build_packet_bytes("GG-GLB", "GhostGirlGLB", frame_i, 60, weights_glb)
		)
		rec_glb.record_packet(pkt_glb, float(frame_i) / 60.0)
	var anim_glb: Animation = rec_glb.stop_recording()
	assert_not_null(anim_glb, "GLB recorder must build valid Animation.")
	assert_eq(anim_glb.get_track_count(), 62, "GLB Animation must contain 52 + 6 + 4 = 62 tracks.")
	var glb_blink_track: int = anim_glb.find_track(
		NodePath(rec_glb.head_mesh_path + ":eyeBlinkLeft"), Animation.TYPE_BLEND_SHAPE
	)
	assert_gte(glb_blink_track, 0, "Missing GhostGirl_Head:eyeBlinkLeft blendshape track.")
	assert_almost_eq(float(anim_glb.track_get_key_value(glb_blink_track, 2)), 0.8, 0.005)
	var glb_lash_track: int = anim_glb.find_track(
		NodePath(rec_glb.lash_mesh_path + ":eyeBlinkLeft"), Animation.TYPE_BLEND_SHAPE
	)
	assert_gte(glb_lash_track, 0, "Missing GhostGirl_Eyelashes:eyeBlinkLeft blendshape track.")
	var saved_glb: String = rec_glb.save_animation(anim_glb, TEST_SAVE_DIR, "ghost_girl_glb_test")
	assert_true(FileAccess.file_exists(saved_glb), "Saved GLB animation .res must exist.")

	var rec_hum: ARKitRecorder = ARKitRecorder.new()
	rec_hum.configure_from_controller(hum_rig)
	assert_true(rec_hum.record_humanizer_anim_tree)
	assert_true(rec_hum.head_mesh_path.is_empty())
	assert_true(rec_hum.lash_mesh_path.is_empty())
	assert_eq(
		hum_body.get_node_or_null(NodePath(rec_hum.anim_tree_path)),
		hum_rig.get_face_animation_tree(),
		"Humanizer recorder anim_tree_path must resolve to AnimationTree.",
	)
	assert_eq(
		hum_body.get_node_or_null(NodePath(rec_hum.skeleton_path)),
		hum_rig.get_skeleton(),
		"Humanizer recorder skeleton_path must resolve to GeneralSkeleton.",
	)

	rec_hum.start_recording("GG-HUM")
	for hum_frame: int in range(3):
		var hum_alpha: float = float(hum_frame) * 0.45
		var weights_hum: PackedFloat32Array = _make_arkit_weights(
			hum_alpha, hum_alpha * 0.6, hum_alpha * 0.9, 0.15 * hum_alpha
		)
		var pkt_hum: ARKitPacket = ARKitPacket.new(
			ARKitPacket.build_packet_bytes("GG-HUM", "GhostGirlHum", hum_frame, 60, weights_hum)
		)
		rec_hum.record_packet(pkt_hum, float(hum_frame) / 60.0)
	var anim_hum: Animation = rec_hum.stop_recording()
	assert_not_null(anim_hum, "Humanizer recorder must build valid Animation.")
	assert_eq(
		anim_hum.get_track_count(),
		ARKitRecorder.HUMANIZER_ARKIT_KEYS.size() + 4,
		"Humanizer Animation must contain 41 Add2 value tracks + 4 bone rotation tracks.",
	)
	var hum_blink_track: int = (
		anim_hum
		. find_track(
			NodePath(rec_hum.anim_tree_path + ":parameters/eyeBlinkLeft/add_amount"),
			Animation.TYPE_VALUE,
		)
	)
	assert_gte(hum_blink_track, 0, "Missing Humanizer eyeBlinkLeft/add_amount track.")
	assert_almost_eq(float(anim_hum.track_get_key_value(hum_blink_track, 2)), 0.9, 0.005)
	var hum_jaw_track: int = (
		anim_hum
		. find_track(
			NodePath(rec_hum.anim_tree_path + ":parameters/jawOpen/add_amount"),
			Animation.TYPE_VALUE,
		)
	)
	assert_gte(hum_jaw_track, 0, "Missing Humanizer jawOpen/add_amount track.")
	var saved_hum: String = rec_hum.save_animation(anim_hum, TEST_SAVE_DIR, "ghost_girl_hum_test")
	assert_true(FileAccess.file_exists(saved_hum), "Saved Humanizer animation .res must exist.")


## Verifies P-key playback of the exported facial `.tres` clip on GhostGirl GLB.
func test_preview_p_key_facial_clip_playback() -> void:
	var preview: GhostGirlFacePreview = PREVIEW_SCENE.instantiate() as GhostGirlFacePreview
	add_child_autofree(preview)

	var ghost_girl: NpcActor = preview.get_ghost_girl()
	var glb_rig: FaceRigController = preview.get_glb_face_rig()
	var player: AnimationPlayer = preview.get_facial_clip_player()
	assert_not_null(preview.facial_clip, "Default facial_clip must preload.")
	assert_not_null(player, "FacialClipPlayer must be attached to GhostGirl.")
	assert_eq(
		preview.facial_clip.get_track_count(),
		59,
		"Exported facial clip must contain 52 head + 6 lash + 1 Head rotation tracks.",
	)
	assert_false(preview.is_facial_clip_playing(), "Facial clip must start stopped.")

	preview._unhandled_input(_make_key_event(KEY_P))
	assert_true(preview.is_facial_clip_playing(), "P key must start facial_clip playback.")
	assert_true(player.is_playing(), "FacialClipPlayer must be playing after P key.")
	assert_false(ghost_girl.look_at_enabled, "Look-at must pause while facial_clip plays.")
	assert_false(glb_rig.auto_blink_enabled, "Auto-blink must pause while facial_clip plays.")
	assert_false(preview.is_processing(), "Preview _process() must stay asleep during playback.")

	preview._unhandled_input(_make_key_event(KEY_P))
	assert_false(preview.is_facial_clip_playing(), "Second P key must stop facial_clip playback.")
	assert_false(player.is_playing(), "FacialClipPlayer must stop on second P key.")
	assert_true(ghost_girl.look_at_enabled, "Look-at must restore after stopping facial_clip.")
	assert_true(glb_rig.auto_blink_enabled, "Auto-blink must restore after stopping facial_clip.")


## Ensures [HumanizerRegistry] rigs, targets, and equipment are loaded for headless tests.
func _ensure_humanizer_registry_loaded() -> void:
	if HumanizerRegistry.rigs.is_empty():
		HumanizerRegistry._get_rigs()
	if (
		HumanizerRegistry.equipment.is_empty()
		or not HumanizerRegistry.equipment.has("GhostGirl_Hair_Cards")
		or not HumanizerTargetService.data.has(HUMANIZER_TARGET_KEY)
	):
		HumanizerRegistry.load_all()


## Instantiates a fresh Humanizer GhostGirl character on [constant HUMANIZER_RIG_NAME].
func _build_humanizer_ghost_girl() -> CharacterBody3D:
	var config: HumanConfig = HumanConfig.new()
	config.rig = HUMANIZER_RIG_NAME
	config.skin_color = Color.WHITE
	config.hair_color = Color.WHITE
	config.set_targets({HUMANIZER_TARGET_KEY: 1.0})
	config.add_equipment(HumanizerEquipment.new("Body-Default", HUMANIZER_SKIN_MAT))
	for equip_id: String in EXPECTED_HUMANIZER_EQUIPS:
		config.add_equipment(HumanizerEquipment.new(equip_id, equip_id))

	var humanizer: Humanizer = Humanizer.new()
	await humanizer.load_config_async(config)
	var body_raw: Variant = humanizer.get_CharacterBody3D(false)
	return body_raw as CharacterBody3D if body_raw is CharacterBody3D else null


## Builds a synthetic pressed [InputEventKey] for [param keycode].
func _make_key_event(keycode: Key) -> InputEventKey:
	var key_ev: InputEventKey = InputEventKey.new()
	key_ev.keycode = keycode
	key_ev.pressed = true
	key_ev.echo = false
	return key_ev


## Builds a 61-float ARKit weights buffer with customizable blink, jaw, smile, and head pose.
func _make_arkit_weights(
	blink_l: float,
	jaw_open: float,
	smile_l: float,
	head_yaw: float = 0.0,
	head_pitch: float = 0.0,
	head_roll: float = 0.0,
) -> PackedFloat32Array:
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(61)
	weights.fill(0.0)
	weights[ARKitServer.BlendShape.EYE_BLINK_LEFT] = blink_l
	weights[ARKitServer.BlendShape.JAW_OPEN] = jaw_open
	weights[ARKitServer.BlendShape.MOUTH_SMILE_LEFT] = smile_l
	weights[ARKitServer.BlendShape.HEAD_YAW] = head_yaw
	weights[ARKitServer.BlendShape.HEAD_PITCH] = head_pitch
	weights[ARKitServer.BlendShape.HEAD_ROLL] = head_roll
	return weights


## Safely narrows a [Variant] numeric parameter value into a typed [code]float[/code].
func _to_float(raw_value: Variant) -> float:
	if raw_value is float:
		return raw_value
	if raw_value is int:
		return float(raw_value)
	return 0.0
