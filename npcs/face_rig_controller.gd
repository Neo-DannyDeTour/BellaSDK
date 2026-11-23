## Facial blendshape, eyelid sync, jaw coupling, and eye [LookAtModifier3D] controller.
class_name FaceRigController
extends Node

## Emitted when the active expression preset changes to [param expression_name].
signal expression_changed(expression_name: StringName)

## Emitted when an automatic or manual eye blink sequence begins.
signal blink_triggered

## Facial rig driver backend selected automatically during [method _ready].
enum RigBackend {
	## Drives [ArrayMesh] blendshapes on head/eyelash meshes and couples [member jaw_bone].
	BLENDSHAPE,
	## Drives Humanizer [AnimationTree] [AnimationNodeAdd2] blend parameters.
	HUMANIZER_ANIM_TREE,
}

## Duration in seconds for the eyelid close phase of a blink.
const BLINK_CLOSE_DURATION: float = 0.06
## Duration in seconds for the eyelid reopen phase of a blink.
const BLINK_OPEN_DURATION: float = 0.08
## Left-eye [LookAtModifier3D] node name created under [Skeleton3D].
const MOD_LEFT_EYE_NAME: String = "LeftEyeLookAt"
## Right-eye [LookAtModifier3D] node name created under [Skeleton3D].
const MOD_RIGHT_EYE_NAME: String = "RightEyeLookAt"
## Blendshape key driving both head morph and [member jaw_bone] opening angle.
const SHAPE_JAW_OPEN: StringName = &"jawOpen"
## Blendshape key driving left eyelid closure.
const SHAPE_BLINK_LEFT: StringName = &"eyeBlinkLeft"
## Blendshape key driving right eyelid closure.
const SHAPE_BLINK_RIGHT: StringName = &"eyeBlinkRight"
## BlendTree node name checked to auto-discover a Humanizer facial [AnimationTree].
const NODE_EYE_BLINK_LEFT: StringName = &"eyeBlinkLeft"
## AnimationTree parameter path checked to auto-discover a Humanizer facial [AnimationTree].
const PARAM_EYE_BLINK_LEFT: StringName = &"parameters/eyeBlinkLeft/add_amount"
## Pre-allocated Humanizer head yaw/pitch/roll [AnimationNodeAdd2] node keys.
const HEAD_ROT_KEYS: Array[StringName] = [
	&"headLeft",
	&"headRight",
	&"headUp",
	&"headDown",
	&"headRollLeft",
	&"headRollRight",
]
## Humanizer [AnimationNodeAdd2] key for leftward head yaw.
const KEY_HEAD_LEFT: StringName = &"headLeft"
## Humanizer [AnimationNodeAdd2] key for rightward head yaw.
const KEY_HEAD_RIGHT: StringName = &"headRight"
## Humanizer [AnimationNodeAdd2] key for upward head pitch.
const KEY_HEAD_UP: StringName = &"headUp"
## Humanizer [AnimationNodeAdd2] key for downward head pitch.
const KEY_HEAD_DOWN: StringName = &"headDown"
## Humanizer [AnimationNodeAdd2] key for counter-clockwise head roll.
const KEY_HEAD_ROLL_LEFT: StringName = &"headRollLeft"
## Humanizer [AnimationNodeAdd2] key for clockwise head roll.
const KEY_HEAD_ROLL_RIGHT: StringName = &"headRollRight"
## Radian range mapped to 1.0 on Humanizer head rotation [AnimationNodeAdd2] parameters (35 deg).
const HEAD_ROT_MAX_RAD: float = 0.610865

## Complete 52 standard ARKit blendshape keys in Live Link Face index order (0..51).
const ARKIT_52_KEYS: Array[StringName] = [
	&"eyeBlinkLeft",
	&"eyeLookDownLeft",
	&"eyeLookInLeft",
	&"eyeLookOutLeft",
	&"eyeLookUpLeft",
	&"eyeSquintLeft",
	&"eyeWideLeft",
	&"eyeBlinkRight",
	&"eyeLookDownRight",
	&"eyeLookInRight",
	&"eyeLookOutRight",
	&"eyeLookUpRight",
	&"eyeSquintRight",
	&"eyeWideRight",
	&"jawForward",
	&"jawRight",
	&"jawLeft",
	&"jawOpen",
	&"mouthClose",
	&"mouthFunnel",
	&"mouthPucker",
	&"mouthRight",
	&"mouthLeft",
	&"mouthSmileLeft",
	&"mouthSmileRight",
	&"mouthFrownLeft",
	&"mouthFrownRight",
	&"mouthDimpleLeft",
	&"mouthDimpleRight",
	&"mouthStretchLeft",
	&"mouthStretchRight",
	&"mouthRollLower",
	&"mouthRollUpper",
	&"mouthShrugLower",
	&"mouthShrugUpper",
	&"mouthPressLeft",
	&"mouthPressRight",
	&"mouthLowerDownLeft",
	&"mouthLowerDownRight",
	&"mouthUpperUpLeft",
	&"mouthUpperUpRight",
	&"browDownLeft",
	&"browDownRight",
	&"browInnerUp",
	&"browOuterUpLeft",
	&"browOuterUpRight",
	&"cheekPuff",
	&"cheekSquintLeft",
	&"cheekSquintRight",
	&"noseSneerLeft",
	&"noseSneerRight",
	&"tongueOut",
]

## Mouth and jaw ARKit keys zeroed when applying a viseme via [method set_viseme].
const MOUTH_JAW_KEYS: Array[StringName] = [
	&"jawOpen",
	&"mouthClose",
	&"mouthFunnel",
	&"mouthPucker",
	&"mouthSmileLeft",
	&"mouthSmileRight",
	&"mouthFrownLeft",
	&"mouthFrownRight",
	&"mouthStretchLeft",
	&"mouthStretchRight",
	&"mouthUpperUpLeft",
	&"mouthUpperUpRight",
	&"mouthLowerDownLeft",
	&"mouthLowerDownRight",
]

## Named facial expression presets using only the 27 ARKit blendshape keys.
const EXPRESSION_PRESETS: Dictionary[StringName, Dictionary] = {
	&"neutral": {},
	&"happy":
	{
		&"mouthSmileLeft": 0.82,
		&"mouthSmileRight": 0.82,
		&"cheekSquintLeft": 0.45,
		&"cheekSquintRight": 0.45,
		&"eyeSquintLeft": 0.28,
		&"eyeSquintRight": 0.28,
		&"jawOpen": 0.18,
		&"mouthUpperUpLeft": 0.22,
		&"mouthUpperUpRight": 0.22,
		&"mouthLowerDownLeft": 0.10,
		&"mouthLowerDownRight": 0.10,
	},
	&"surprised":
	{
		&"browInnerUp": 0.80,
		&"browOuterUpLeft": 0.70,
		&"browOuterUpRight": 0.70,
		&"eyeWideLeft": 0.85,
		&"eyeWideRight": 0.85,
		&"jawOpen": 0.55,
		&"mouthFunnel": 0.35,
	},
	&"angry":
	{
		&"browDownLeft": 0.90,
		&"browDownRight": 0.90,
		&"eyeSquintLeft": 0.45,
		&"eyeSquintRight": 0.45,
		&"mouthFrownLeft": 0.55,
		&"mouthFrownRight": 0.55,
		&"mouthLowerDownLeft": 0.20,
		&"mouthLowerDownRight": 0.20,
		&"jawOpen": 0.08,
	},
	&"sad":
	{
		&"browInnerUp": 0.75,
		&"browDownLeft": 0.20,
		&"browDownRight": 0.20,
		&"mouthFrownLeft": 0.70,
		&"mouthFrownRight": 0.70,
		&"mouthPucker": 0.20,
	},
	&"blink":
	{
		&"eyeBlinkLeft": 1.0,
		&"eyeBlinkRight": 1.0,
	},
}

## Lip-sync viseme blendshape recipes keyed by vowel shape identifier.
const VISEME_MAP: Dictionary[StringName, Dictionary] = {
	&"aa":
	{
		&"jawOpen": 0.75,
		&"mouthLowerDownLeft": 0.30,
		&"mouthLowerDownRight": 0.30,
	},
	&"ee":
	{
		&"jawOpen": 0.22,
		&"mouthStretchLeft": 0.65,
		&"mouthStretchRight": 0.65,
		&"mouthSmileLeft": 0.30,
		&"mouthSmileRight": 0.30,
	},
	&"ih":
	{
		&"jawOpen": 0.32,
		&"mouthStretchLeft": 0.35,
		&"mouthStretchRight": 0.35,
		&"mouthUpperUpLeft": 0.25,
		&"mouthUpperUpRight": 0.25,
	},
	&"oh":
	{
		&"jawOpen": 0.50,
		&"mouthFunnel": 0.80,
	},
	&"ou":
	{
		&"jawOpen": 0.24,
		&"mouthPucker": 0.85,
		&"mouthFunnel": 0.25,
	},
}

@export_group("Scene References")
## Rigged character model root containing [Skeleton3D] and facial meshes.
@export var model_root: Node3D
## Optional [VisibleOnScreenNotifier3D] pausing eye modifiers, blink timer, and tweens.
@export var visibility_notifier: VisibleOnScreenNotifier3D
## World-space gaze [Marker3D] targeted by both eye [LookAtModifier3D] nodes.
@export var look_target: Marker3D:
	set(value):
		look_target = value
		if is_inside_tree():
			_update_eye_look_targets()
## Optional Humanizer facial [AnimationTree]; auto-discovered in [member model_root] when null.
@export var face_animation_tree: AnimationTree

@export_group("Face Rig Nodes & Bones")
## Mesh node name exposing the 27 ARKit facial blendshapes.
@export var head_mesh_name: String = "Bella_Head"
## Mesh node name exposing the 6 synced eyelid blendshapes.
@export var eyelash_mesh_name: String = "Bella_Eyelashes"
## Left eye bone name on [Skeleton3D].
@export var left_eye_bone: String = "LeftEye"
## Right eye bone name on [Skeleton3D].
@export var right_eye_bone: String = "RightEye"
## Jaw bone name coupled to [constant SHAPE_JAW_OPEN].
@export var jaw_bone: String = "Jaw"

@export_group("Eye Tracking")
## Enables real-time eye [LookAtModifier3D] tracking toward [member look_target].
@export var eye_look_enabled: bool = true:
	set(value):
		eye_look_enabled = value
		if is_inside_tree():
			_apply_eye_look_state()
## Total horizontal yaw limitation in degrees for each eye modifier.
@export_range(10.0, 90.0, 1.0) var eye_yaw_limit_deg: float = 56.0
## Total vertical pitch limitation in degrees for each eye modifier.
@export_range(10.0, 70.0, 1.0) var eye_pitch_limit_deg: float = 36.0
## Influence weight applied to both eye [LookAtModifier3D] nodes when enabled.
@export_range(0.0, 1.0, 0.02) var eye_look_influence: float = 0.90

@export_group("Blinking & Jaw")
## Enables randomized automatic blinking while visible on screen.
@export var auto_blink_enabled: bool = true:
	set(value):
		auto_blink_enabled = value
		if is_inside_tree():
			if auto_blink_enabled and _is_on_screen:
				_schedule_next_blink()
			elif is_instance_valid(_blink_timer):
				_blink_timer.stop()
## Minimum interval in seconds between automatic blinks.
@export_range(0.5, 15.0, 0.1) var blink_interval_min: float = 2.5
## Maximum interval in seconds between automatic blinks.
@export_range(0.5, 20.0, 0.1) var blink_interval_max: float = 6.0
## Maximum downward rotation in degrees applied to [member jaw_bone] at jawOpen = 1.0.
@export_range(5.0, 45.0, 0.5) var jaw_open_max_deg: float = 22.0

## Active facial driver backend selected in [method _ready].
var _rig_backend: RigBackend = RigBackend.BLENDSHAPE
## Cached [Skeleton3D] discovered inside [member model_root].
var _skeleton: Skeleton3D = null
## Cached head [MeshInstance3D] driving facial blendshapes in blendshape mode.
var _head_mesh: MeshInstance3D = null
## Optional eyelash [MeshInstance3D] mirroring the 6 eyelid blendshapes.
var _eyelash_mesh: MeshInstance3D = null
## Cached Humanizer facial [AnimationTree] driving [AnimationNodeAdd2] blend parameters.
var _face_anim_tree: AnimationTree = null
## Cached blendshape index map on [member _head_mesh].
var _head_shape_indices: Dictionary[StringName, int] = {}
## Cached blendshape index map on [member _eyelash_mesh].
var _eyelash_shape_indices: Dictionary[StringName, int] = {}
## Cached Humanizer [AnimationTree] parameter paths keyed by ARKit blendshape name.
var _anim_tree_param_paths: Dictionary[StringName, StringName] = {}
## Cached Humanizer [AnimationTree] parameter paths keyed by head rotation node name.
var _anim_tree_head_paths: Dictionary[StringName, StringName] = {}
## Ordered list of available blendshape names cached from head mesh or [AnimationTree].
var _available_blendshapes: Array[StringName] = []
## Cached bone index for [member jaw_bone] inside [member _skeleton].
var _jaw_bone_idx: int = -1
## Cached rest-pose rotation quaternion for [member jaw_bone].
var _jaw_rest_rotation: Quaternion = Quaternion.IDENTITY
## Native [LookAtModifier3D] attached for [member left_eye_bone].
var _left_eye_mod: LookAtModifier3D = null
## Native [LookAtModifier3D] attached for [member right_eye_bone].
var _right_eye_mod: LookAtModifier3D = null
## One-shot [Timer] scheduling randomized automatic blinks.
var _blink_timer: Timer = null
## Active [Tween] interpolating facial expression transitions.
var _expression_tween: Tween = null
## Active [Tween] driving eye blink closure and reopening.
var _blink_tween: Tween = null
## Reusable start-weight buffer for zero-allocation expression tweening.
var _expr_start_weights: Dictionary[StringName, float] = {}
## Reusable target-weight buffer for zero-allocation expression tweening.
var _expr_target_weights: Dictionary[StringName, float] = {}
## Currently active facial expression preset name.
var _current_expression: StringName = &"neutral"
## Tracks whether the character is currently inside the active camera frustum.
var _is_on_screen: bool = true


## Resolves rig nodes, caches blendshapes and jaw rest pose, and wires eye modifiers and blink.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	if not is_instance_valid(model_root):
		model_root = get_node_or_null(^"../BellaModel") as Node3D
	if not is_instance_valid(visibility_notifier):
		visibility_notifier = (
			get_node_or_null(^"../VisibleOnScreenNotifier3D") as VisibleOnScreenNotifier3D
		)
	if not is_instance_valid(look_target):
		look_target = get_node_or_null(^"../LookTarget") as Marker3D

	assert(is_instance_valid(model_root), "FaceRigController requires model_root.")

	_skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if not is_instance_valid(_skeleton):
		_skeleton = model_root.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if not head_mesh_name.is_empty():
		_head_mesh = model_root.find_child(head_mesh_name, true, false) as MeshInstance3D
	if not eyelash_mesh_name.is_empty():
		_eyelash_mesh = model_root.find_child(eyelash_mesh_name, true, false) as MeshInstance3D

	_face_anim_tree = face_animation_tree
	if not is_instance_valid(_face_anim_tree):
		_face_anim_tree = _discover_face_animation_tree(model_root)

	if not is_instance_valid(_head_mesh) and is_instance_valid(_face_anim_tree):
		_rig_backend = RigBackend.HUMANIZER_ANIM_TREE
	else:
		_rig_backend = RigBackend.BLENDSHAPE

	assert(is_instance_valid(_skeleton), "FaceRigController requires Skeleton3D in model_root.")
	assert(
		is_instance_valid(_head_mesh) or is_instance_valid(_face_anim_tree),
		"FaceRigController requires head mesh or face AnimationTree in model_root.",
	)

	_cache_blendshape_maps()
	_setup_face_animation_tree()
	_jaw_bone_idx = _skeleton.find_bone(jaw_bone) if not jaw_bone.is_empty() else -1
	if _jaw_bone_idx >= 0:
		_jaw_rest_rotation = (
			_skeleton.get_bone_rest(_jaw_bone_idx).basis.get_rotation_quaternion().normalized()
		)

	_left_eye_mod = _create_eye_look_modifier(MOD_LEFT_EYE_NAME, left_eye_bone)
	_right_eye_mod = _create_eye_look_modifier(MOD_RIGHT_EYE_NAME, right_eye_bone)
	_setup_blink_timer()
	_setup_visibility_gating()
	_schedule_next_blink()


## Disconnects signals, stops [member _blink_timer], and kills active tweens on exit.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_expression_tween)
	_expression_tween = null
	Utilities.safe_kill_tween(_blink_tween)
	_blink_tween = null

	if is_instance_valid(_blink_timer):
		_blink_timer.stop()
		if _blink_timer.timeout.is_connected(_on_blink_timer_timeout):
			_blink_timer.timeout.disconnect(_on_blink_timer_timeout)

	if is_instance_valid(visibility_notifier):
		if visibility_notifier.screen_entered.is_connected(_on_screen_entered):
			visibility_notifier.screen_entered.disconnect(_on_screen_entered)
		if visibility_notifier.screen_exited.is_connected(_on_screen_exited):
			visibility_notifier.screen_exited.disconnect(_on_screen_exited)


## Transitions facial blendshapes to [param expression_name] over [param duration] seconds.
func set_expression(expression_name: StringName, duration: float = 0.18) -> void:
	if not EXPRESSION_PRESETS.has(expression_name):
		print("FaceRigController: Unknown expression '", expression_name, "'")
		return

	Utilities.safe_kill_tween(_blink_tween)
	_blink_tween = null
	_current_expression = expression_name
	if is_instance_valid(_face_anim_tree):
		_reset_head_anim_params()

	var preset: Dictionary = EXPRESSION_PRESETS[expression_name]
	_expr_start_weights.clear()
	_expr_target_weights.clear()

	for shape_key: StringName in _available_blendshapes:
		_expr_start_weights[shape_key] = get_blendshape_weight(shape_key)
		var raw_weight: Variant = preset.get(shape_key, 0.0)
		_expr_target_weights[shape_key] = clampf(_to_float(raw_weight), 0.0, 1.0)

	if duration <= 0.0 or not is_inside_tree():
		Utilities.safe_kill_tween(_expression_tween)
		_expression_tween = null
		for shape_key: StringName in _available_blendshapes:
			set_blendshape(shape_key, _expr_target_weights[shape_key])
	else:
		_expression_tween = Utilities.reset_tween(self, _expression_tween)
		if is_instance_valid(_expression_tween):
			_expression_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_expression_tween.tween_method(_apply_expression_blend, 0.0, 1.0, duration)
			if not _is_on_screen:
				_expression_tween.pause()

	expression_changed.emit(expression_name)
	print("FaceRigController: expression -> ", expression_name)


## Applies lip-sync [param viseme_name] scaled by [param weight] and zeros unused mouth keys.
func set_viseme(viseme_name: StringName, weight: float) -> void:
	if not VISEME_MAP.has(viseme_name) and not viseme_name.is_empty():
		print("FaceRigController: Unknown viseme '", viseme_name, "'")
		return

	Utilities.safe_kill_tween(_expression_tween)
	_expression_tween = null

	var clamped_scale: float = clampf(weight, 0.0, 1.0)
	var viseme_weights: Dictionary = VISEME_MAP[viseme_name] if not viseme_name.is_empty() else {}
	for mouth_key: StringName in MOUTH_JAW_KEYS:
		var raw_target: Variant = viseme_weights.get(mouth_key, 0.0)
		set_blendshape(mouth_key, _to_float(raw_target) * clamped_scale)

	print("FaceRigController: viseme -> ", viseme_name, " weight=", clamped_scale)


## Sets a single blendshape weight on head, eyelash, or Humanizer tree and couples jaw bone.
func set_blendshape(shape_name: StringName, weight: float) -> void:
	var clamped: float = clampf(weight, 0.0, 1.0)
	if is_instance_valid(_head_mesh) and _head_shape_indices.has(shape_name):
		var head_idx: int = _head_shape_indices[shape_name]
		_head_mesh.set_blend_shape_value(head_idx, clamped)

	if is_instance_valid(_eyelash_mesh) and _eyelash_shape_indices.has(shape_name):
		var lash_idx: int = _eyelash_shape_indices[shape_name]
		_eyelash_mesh.set_blend_shape_value(lash_idx, clamped)

	if is_instance_valid(_face_anim_tree) and _anim_tree_param_paths.has(shape_name):
		_face_anim_tree.set(_anim_tree_param_paths[shape_name], clamped)

	if (
		_rig_backend == RigBackend.BLENDSHAPE
		and shape_name == SHAPE_JAW_OPEN
		and is_instance_valid(_skeleton)
		and _jaw_bone_idx >= 0
	):
		var jaw_angle: float = deg_to_rad(clamped * jaw_open_max_deg)
		var target_rot: Quaternion = _jaw_rest_rotation * Quaternion(Vector3.LEFT, jaw_angle)
		_skeleton.set_bone_pose_rotation(_jaw_bone_idx, target_rot)


## Applies a live ARKit frame (52 shapes + optional head rotations) without heap allocations.
func apply_arkit_weights(weights: PackedFloat32Array) -> void:
	var count: int = mini(weights.size(), ARKIT_52_KEYS.size())
	for idx: int in range(count):
		set_blendshape(ARKIT_52_KEYS[idx], weights[idx])

	if is_instance_valid(_face_anim_tree) and _face_anim_tree.active and weights.size() >= 55:
		_apply_head_rotation_params(weights[52], weights[53], weights[54])


## Plays a 0.06s close then 0.08s open eye blink tween and emits [signal blink_triggered].
func trigger_blink() -> void:
	var start_weight: float = maxf(
		get_blendshape_weight(SHAPE_BLINK_LEFT), get_blendshape_weight(SHAPE_BLINK_RIGHT)
	)
	var rest_weight: float = 1.0 if _current_expression == &"blink" else 0.0

	_blink_tween = Utilities.reset_tween(self, _blink_tween)
	if is_instance_valid(_blink_tween):
		_blink_tween.tween_method(_set_blink_weights, start_weight, 1.0, BLINK_CLOSE_DURATION)
		_blink_tween.tween_method(_set_blink_weights, 1.0, rest_weight, BLINK_OPEN_DURATION)
		if not _is_on_screen:
			_blink_tween.pause()

	blink_triggered.emit()
	print("FaceRigController: blink triggered")


## Enables or disables both eye [LookAtModifier3D] nodes.
func set_eye_look_enabled(enabled: bool) -> void:
	eye_look_enabled = enabled
	_apply_eye_look_state()
	print("FaceRigController: eye_look_enabled=", enabled)


## Returns the current blendshape weight on head mesh or Humanizer [AnimationTree].
func get_blendshape_weight(shape_name: StringName) -> float:
	if is_instance_valid(_head_mesh) and _head_shape_indices.has(shape_name):
		var head_idx: int = _head_shape_indices[shape_name]
		return _head_mesh.get_blend_shape_value(head_idx)
	if is_instance_valid(_face_anim_tree) and _anim_tree_param_paths.has(shape_name):
		return _to_float(_face_anim_tree.get(_anim_tree_param_paths[shape_name]))
	return 0.0


## Returns all blendshape names exposed by head mesh or Humanizer [AnimationTree].
func get_available_blendshapes() -> Array[StringName]:
	return _available_blendshapes.duplicate()


## Returns the active left and right eye [LookAtModifier3D] nodes.
func get_eye_look_modifiers() -> Array[LookAtModifier3D]:
	var mods: Array[LookAtModifier3D] = []
	if is_instance_valid(_left_eye_mod):
		mods.append(_left_eye_mod)
	if is_instance_valid(_right_eye_mod):
		mods.append(_right_eye_mod)
	return mods


## Returns the currently active facial expression preset name.
func get_current_expression() -> StringName:
	return _current_expression


## Returns the cached [Skeleton3D] bone index for [member jaw_bone].
func get_jaw_bone_index() -> int:
	return _jaw_bone_idx


## Returns the active facial rig driver backend ([enum RigBackend]).
func get_rig_backend() -> RigBackend:
	return _rig_backend


## Returns the resolved facial head [MeshInstance3D], or null in Humanizer mode.
func get_head_mesh() -> MeshInstance3D:
	return _head_mesh


## Returns the resolved eyelash [MeshInstance3D], or null if not present.
func get_eyelash_mesh() -> MeshInstance3D:
	return _eyelash_mesh


## Returns the resolved [Skeleton3D] inside [member model_root].
func get_skeleton() -> Skeleton3D:
	return _skeleton


## Returns the resolved Humanizer facial [AnimationTree], or null in blendshape mode.
func get_face_animation_tree() -> AnimationTree:
	return _face_anim_tree


## Caches blendshape name-to-index lookup maps for head and eyelash meshes.
func _cache_blendshape_maps() -> void:
	_available_blendshapes.clear()
	_head_shape_indices = _extract_blendshape_map(_head_mesh, true)
	_eyelash_shape_indices = _extract_blendshape_map(_eyelash_mesh, false)


## Searches [param root_node] for an [AnimationTree] exposing Humanizer facial Add2 nodes.
func _discover_face_animation_tree(root_node: Node) -> AnimationTree:
	if not is_instance_valid(root_node):
		return null
	if root_node is AnimationTree:
		var root_tree: AnimationTree = root_node as AnimationTree
		if _is_face_animation_tree(root_tree):
			return root_tree
	for child: Node in root_node.find_children("*", "AnimationTree", true, false):
		if child is AnimationTree:
			var cand_tree: AnimationTree = child as AnimationTree
			if _is_face_animation_tree(cand_tree):
				return cand_tree
	return null


## Returns true if [param anim_tree] exposes [code]eyeBlinkLeft[/code] as a blend tree node.
func _is_face_animation_tree(anim_tree: AnimationTree) -> bool:
	if not is_instance_valid(anim_tree):
		return false
	if anim_tree.tree_root is AnimationNodeBlendTree:
		var blend_tree: AnimationNodeBlendTree = anim_tree.tree_root as AnimationNodeBlendTree
		if blend_tree.has_node(NODE_EYE_BLINK_LEFT):
			return true
	var raw_val: Variant = anim_tree.get(PARAM_EYE_BLINK_LEFT)
	return raw_val is float or raw_val is int


## Caches Humanizer Add2 paths on [member _face_anim_tree] and resets all Add2 defaults to zero.
func _setup_face_animation_tree() -> void:
	_anim_tree_param_paths.clear()
	_anim_tree_head_paths.clear()
	if not is_instance_valid(_face_anim_tree):
		return

	_face_anim_tree.active = true
	var blend_tree: AnimationNodeBlendTree = (
		_face_anim_tree.tree_root as AnimationNodeBlendTree
		if _face_anim_tree.tree_root is AnimationNodeBlendTree
		else null
	)

	if is_instance_valid(blend_tree):
		for node_name_str: String in blend_tree.get_node_list():
			var node_sn: StringName = StringName(node_name_str)
			if blend_tree.get_node(node_sn) is AnimationNodeAdd2:
				var reset_path: StringName = StringName(
					"parameters/" + node_name_str + "/add_amount"
				)
				_face_anim_tree.set(reset_path, 0.0)

	for arkit_key: StringName in ARKIT_52_KEYS:
		var param_path: StringName = StringName("parameters/" + String(arkit_key) + "/add_amount")
		var supported: bool = false
		if is_instance_valid(blend_tree):
			supported = (
				blend_tree.has_node(arkit_key)
				and blend_tree.get_node(arkit_key) is AnimationNodeAdd2
			)
		if not supported:
			var raw_val: Variant = _face_anim_tree.get(param_path)
			supported = raw_val is float or raw_val is int
		if supported:
			_anim_tree_param_paths[arkit_key] = param_path
			_face_anim_tree.set(param_path, 0.0)
			if not _available_blendshapes.has(arkit_key):
				_available_blendshapes.append(arkit_key)

	for head_key: StringName in HEAD_ROT_KEYS:
		var head_path: StringName = StringName("parameters/" + String(head_key) + "/add_amount")
		var head_supported: bool = false
		if is_instance_valid(blend_tree):
			head_supported = (
				blend_tree.has_node(head_key) and blend_tree.get_node(head_key) is AnimationNodeAdd2
			)
		if not head_supported:
			var raw_head: Variant = _face_anim_tree.get(head_path)
			head_supported = raw_head is float or raw_head is int
		if head_supported:
			_anim_tree_head_paths[head_key] = head_path
			_face_anim_tree.set(head_path, 0.0)


## Extracts a typed blendshape index map from [param mesh_inst] when backed by an [ArrayMesh].
func _extract_blendshape_map(
	mesh_inst: MeshInstance3D, collect_names: bool
) -> Dictionary[StringName, int]:
	var index_map: Dictionary[StringName, int] = {}
	if not is_instance_valid(mesh_inst) or not (mesh_inst.mesh is ArrayMesh):
		return index_map
	var array_mesh: ArrayMesh = mesh_inst.mesh as ArrayMesh
	var shape_count: int = array_mesh.get_blend_shape_count()
	for idx: int in range(shape_count):
		var shape_key: StringName = array_mesh.get_blend_shape_name(idx)
		index_map[shape_key] = idx
		if collect_names:
			_available_blendshapes.append(shape_key)
	return index_map


## Attaches or updates a single eye [LookAtModifier3D] child on [member _skeleton].
func _create_eye_look_modifier(mod_name: String, bone: String) -> LookAtModifier3D:
	if not is_instance_valid(_skeleton) or bone.is_empty() or _skeleton.find_bone(bone) < 0:
		return null

	var mod: LookAtModifier3D = _skeleton.get_node_or_null(NodePath(mod_name)) as LookAtModifier3D
	if not is_instance_valid(mod):
		mod = LookAtModifier3D.new()
		mod.name = mod_name
		_skeleton.add_child(mod)

	mod.bone_name = bone
	if is_instance_valid(look_target):
		mod.target_node = mod.get_path_to(look_target)
	if _rig_backend == RigBackend.HUMANIZER_ANIM_TREE:
		mod.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Y
		mod.primary_rotation_axis = Vector3.AXIS_Z
	else:
		mod.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
		mod.primary_rotation_axis = Vector3.AXIS_Y
	mod.use_secondary_rotation = true
	mod.use_angle_limitation = true
	mod.symmetry_limitation = true
	mod.primary_limit_angle = deg_to_rad(eye_yaw_limit_deg)
	mod.secondary_limit_angle = deg_to_rad(eye_pitch_limit_deg)
	mod.influence = eye_look_influence if eye_look_enabled else 0.0
	mod.active = _is_on_screen and eye_look_enabled
	return mod


## Updates [code]target_node[/code] on both eye modifiers when [member look_target] changes.
func _update_eye_look_targets() -> void:
	if is_instance_valid(_left_eye_mod):
		_left_eye_mod.target_node = (
			_left_eye_mod.get_path_to(look_target) if is_instance_valid(look_target) else ^""
		)
	if is_instance_valid(_right_eye_mod):
		_right_eye_mod.target_node = (
			_right_eye_mod.get_path_to(look_target) if is_instance_valid(look_target) else ^""
		)


## Maps Live Link Face head yaw, pitch, and roll radians onto Humanizer Add2 pose parameters.
func _apply_head_rotation_params(yaw: float, pitch: float, roll: float) -> void:
	var left_w: float = clampf(yaw / HEAD_ROT_MAX_RAD, 0.0, 1.0) if yaw > 0.0 else 0.0
	var right_w: float = clampf(-yaw / HEAD_ROT_MAX_RAD, 0.0, 1.0) if yaw < 0.0 else 0.0
	var down_w: float = clampf(pitch / HEAD_ROT_MAX_RAD, 0.0, 1.0) if pitch > 0.0 else 0.0
	var up_w: float = clampf(-pitch / HEAD_ROT_MAX_RAD, 0.0, 1.0) if pitch < 0.0 else 0.0
	var roll_r: float = clampf(roll / HEAD_ROT_MAX_RAD, 0.0, 1.0) if roll > 0.0 else 0.0
	var roll_l: float = clampf(-roll / HEAD_ROT_MAX_RAD, 0.0, 1.0) if roll < 0.0 else 0.0

	_set_head_anim_param(KEY_HEAD_LEFT, left_w)
	_set_head_anim_param(KEY_HEAD_RIGHT, right_w)
	_set_head_anim_param(KEY_HEAD_DOWN, down_w)
	_set_head_anim_param(KEY_HEAD_UP, up_w)
	_set_head_anim_param(KEY_HEAD_ROLL_RIGHT, roll_r)
	_set_head_anim_param(KEY_HEAD_ROLL_LEFT, roll_l)


## Sets a single cached Humanizer head rotation [AnimationNodeAdd2] weight without allocation.
func _set_head_anim_param(head_key: StringName, weight: float) -> void:
	if _anim_tree_head_paths.has(head_key):
		_face_anim_tree.set(_anim_tree_head_paths[head_key], weight)


## Zeros all cached Humanizer head rotation [AnimationNodeAdd2] parameters.
func _reset_head_anim_params() -> void:
	for head_key: StringName in _anim_tree_head_paths:
		_face_anim_tree.set(_anim_tree_head_paths[head_key], 0.0)


## Creates or reuses the one-shot [code]BlinkTimer[/code] child node.
func _setup_blink_timer() -> void:
	_blink_timer = get_node_or_null(^"BlinkTimer") as Timer
	if not is_instance_valid(_blink_timer):
		_blink_timer = Timer.new()
		_blink_timer.name = "BlinkTimer"
		add_child(_blink_timer)

	_blink_timer.one_shot = true
	_blink_timer.autostart = false
	Utilities.safe_connect(_blink_timer.timeout, _on_blink_timer_timeout)


## Hooks [member visibility_notifier] enter and exit callbacks for off-screen gating.
func _setup_visibility_gating() -> void:
	_is_on_screen = true
	if not is_instance_valid(visibility_notifier):
		return
	Utilities.safe_connect(visibility_notifier.screen_entered, _on_screen_entered)
	Utilities.safe_connect(visibility_notifier.screen_exited, _on_screen_exited)


## Schedules the next randomized automatic blink when enabled and visible.
func _schedule_next_blink() -> void:
	if not is_instance_valid(_blink_timer) or not is_inside_tree():
		return
	if not auto_blink_enabled or not _is_on_screen:
		_blink_timer.stop()
		return
	var min_wait: float = maxf(0.1, blink_interval_min)
	var max_wait: float = maxf(min_wait, blink_interval_max)
	_blink_timer.wait_time = randf_range(min_wait, max_wait)
	_blink_timer.start()


## Synchronizes eye modifier [code]active[/code] and [code]influence[/code] flags.
func _apply_eye_look_state() -> void:
	var should_run: bool = _is_on_screen and eye_look_enabled
	var target_influence: float = eye_look_influence if eye_look_enabled else 0.0
	if is_instance_valid(_left_eye_mod):
		_left_eye_mod.influence = target_influence
		_left_eye_mod.active = should_run
	if is_instance_valid(_right_eye_mod):
		_right_eye_mod.influence = target_influence
		_right_eye_mod.active = should_run


## Interpolates all cached blendshape weights during an expression tween step.
func _apply_expression_blend(alpha: float) -> void:
	for shape_key: StringName in _available_blendshapes:
		var start_w: float = _expr_start_weights[shape_key]
		var target_w: float = _expr_target_weights[shape_key]
		set_blendshape(shape_key, lerpf(start_w, target_w, alpha))


## Updates both eyelid blink blendshapes symmetrically during a blink tween.
func _set_blink_weights(weight: float) -> void:
	set_blendshape(SHAPE_BLINK_LEFT, weight)
	set_blendshape(SHAPE_BLINK_RIGHT, weight)


## Narrows a [Variant] numeric value safely into a typed [code]float[/code].
func _to_float(raw_value: Variant) -> float:
	if raw_value is float:
		return raw_value
	if raw_value is int:
		return float(raw_value)
	return 0.0


## Pauses or resumes [param tw] if currently valid.
func _set_tween_paused(tw: Tween, paused: bool) -> void:
	if is_instance_valid(tw) and tw.is_valid():
		if paused:
			tw.pause()
		else:
			tw.play()


## Resumes eye modifiers, active tweens, and auto-blink when entering camera view.
func _on_screen_entered() -> void:
	_is_on_screen = true
	_apply_eye_look_state()
	_set_tween_paused(_expression_tween, false)
	_set_tween_paused(_blink_tween, false)
	_schedule_next_blink()


## Pauses eye modifiers, active tweens, and [member _blink_timer] when off-screen.
func _on_screen_exited() -> void:
	_is_on_screen = false
	_apply_eye_look_state()
	_set_tween_paused(_expression_tween, true)
	_set_tween_paused(_blink_tween, true)
	if is_instance_valid(_blink_timer):
		_blink_timer.stop()


## Triggers a natural blink on timer timeout unless holding the blink expression.
func _on_blink_timer_timeout() -> void:
	if _is_on_screen and auto_blink_enabled:
		if _current_expression != &"blink":
			trigger_blink()
		_schedule_next_blink()
