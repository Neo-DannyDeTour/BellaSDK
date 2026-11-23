## Controls first-person/shadow player body [AnimationTree], layers, and hand weapon visuals.
class_name PlayerBodyController
extends Node3D

## Fallback ground walking speed (m/s) when [member locomotion_component] is unassigned.
const DEFAULT_WALK_SPEED: float = 5.0
## Fallback sprint speed (m/s) when [member locomotion_component] is unassigned.
const DEFAULT_RUN_SPEED: float = 6.5
## Fallback crouch walking speed (m/s) when [member locomotion_component] is unassigned.
const DEFAULT_CROUCH_SPEED: float = 3.0
## Exponential damping rate for locomotion, crouch, pitch, and weapon blend weights.
const BLEND_SMOOTH_SPEED: float = 12.0
## Crossfade duration (seconds) between locomotion, crouch, and air states.
const STATE_CROSSFADE_SEC: float = 0.12
## Maximum camera head pitch (radians) mirrored to upper spine and head bones.
const MAX_LOOK_PITCH_RAD: float = 1.4835
## Planar locomotion blend coordinate assigned to forward sprint speed.
const RUN_BLEND_Y: float = 1.5

## AnimationTree parameter key for the base [AnimationNodeStateMachine] playback.
const PARAM_SM_PLAYBACK: StringName = &"parameters/state_machine/playback"
## AnimationTree parameter key for the 2D standing locomotion blend space.
const PARAM_LOCOMOTION_BLEND: StringName = &"parameters/state_machine/locomotion/blend_position"
## AnimationTree parameter key for the 1D crouched locomotion blend space.
const PARAM_CROUCH_BLEND: StringName = &"parameters/state_machine/crouch/blend_position"
## AnimationTree parameter key for upper-body firearm overlay blend amount.
const PARAM_WEAPON_BLEND: StringName = &"parameters/weapon_blend/blend_amount"
## AnimationTree parameter key for selecting active firearm pose transition.
const PARAM_WEAPON_POSE_REQ: StringName = &"parameters/weapon_pose/transition_request"

## Base state machine node name for standing 2D locomotion.
const STATE_LOCOMOTION: StringName = &"locomotion"
## Base state machine node name for crouched 1D locomotion.
const STATE_CROUCH: StringName = &"crouch"
## Base state machine node name for airborne jump pose.
const STATE_AIR: StringName = &"air"

## Head bone name used for [member head_cube_attachment] and camera pitch follow.
const BONE_HEAD: StringName = &"Head"
## Right hand bone name used for [member right_hand_attachment].
const BONE_RIGHT_HAND: StringName = &"RightHand"
## Spine bone name receiving subtle pitch follow.
const BONE_SPINE: StringName = &"Spine"
## Chest bone name receiving subtle pitch follow.
const BONE_CHEST: StringName = &"Chest"

## Weapon tag string emitted when Colt SAA revolver is active.
const WEAPON_TAG_REVOLVER: String = "revolver"
## Weapon tag string emitted when pump shotgun is active.
const WEAPON_TAG_SHOTGUN: String = "shotgun"

## All 11 looping clip names baked in [bella_player.glb].
const LOOPING_CLIPS: Array[StringName] = [
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

## Meshes rendered on Layer 1 so first-person camera sees lower body and shadow.
const ENV_LAYER_MESHES: Array[StringName] = [
	&"Bella_TorsoLegs",
	&"Bella_Dress",
	&"Bella_Skirt",
	&"Bella_Boots",
]

## Meshes rendered on Layer 2 so first-person camera culls arms/gloves while keeping shadows.
const PLAYER_LAYER_MESHES: Array[StringName] = [
	&"Bella_Arms",
	&"Bella_Gloves",
]

## Upper-body humanoid bones filtered onto [code]weapon_blend[/code] overlay.
const UPPER_BODY_BONES: Array[String] = [
	"Spine",
	"Chest",
	"UpperChest",
	"Neck",
	"Head",
	"LeftShoulder",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightShoulder",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
]

## Finger bone substrings included in [code]weapon_blend[/code] filter when present.
const FINGER_SUBSTRINGS: Array[String] = [
	"finger",
	"thumb",
	"index",
	"middle",
	"ring",
	"pinky",
	"little",
]

@export_group("Player References")
## Owning [CharacterBody3D] player providing velocity, floor state, and wolf mode flag.
@export var player: CharacterBody3D
## Player [PlayerLocomotionComponent] providing crouch state and walk/run speeds.
@export var locomotion_component: PlayerLocomotionComponent
## Player [CameraController] providing [member CameraController.head] vertical pitch.
@export var camera_controller: CameraController
## Player [WeaponInventoryComponent] synced on startup for initial equipped weapon.
@export var weapon_inventory_component: WeaponInventoryComponent

@export_group("Body Rig & Attachments")
## Child [Node3D] instancing [bella_player.glb] ([Skeleton3D] and [AnimationPlayer]).
@export var model_root: Node3D
## [BoneAttachment3D] bound to [constant BONE_HEAD] carrying [code]HeadCube[/code].
@export var head_cube_attachment: BoneAttachment3D
## [BoneAttachment3D] bound to [constant BONE_RIGHT_HAND] carrying world weapon meshes.
@export var right_hand_attachment: BoneAttachment3D
## Third-person/shadow revolver model parented under [member right_hand_attachment].
@export var world_revolver: Node3D
## Third-person/shadow shotgun model parented under [member right_hand_attachment].
@export var world_shotgun: Node3D

## Cached [Skeleton3D] resolved inside [member model_root].
var _skeleton: Skeleton3D = null
## Cached [AnimationPlayer] resolved inside [member model_root].
var _anim_player: AnimationPlayer = null
## Runtime [AnimationTree] driving base locomotion state machine and upper-body weapon blend.
var _anim_tree: AnimationTree = null
## Cached playback handle for [code]state_machine[/code] inside [member _anim_tree].
var _sm_playback: AnimationNodeStateMachinePlayback = null
## Current smoothed 2D locomotion blend position.
var _locomotion_blend: Vector2 = Vector2.ZERO
## Current smoothed 1D crouch blend position in [0.0, 1.0].
var _crouch_blend: float = 0.0
## Current smoothed upper-body weapon overlay blend amount in [0.0, 1.0].
var _weapon_blend: float = 0.0
## Target upper-body weapon overlay blend amount (1.0 with firearm, 0.0 unarmed).
var _target_weapon_blend: float = 0.0
## Active normalized weapon tag string.
var _active_weapon_tag: String = ""
## Active base locomotion state machine state name.
var _current_state: StringName = &""
## Current smoothed vertical camera look pitch in radians.
var _look_pitch_rad: float = 0.0
## Cached bone index for [constant BONE_SPINE].
var _spine_bone_idx: int = -1
## Cached bone index for [constant BONE_CHEST].
var _chest_bone_idx: int = -1
## Cached bone index for [constant BONE_HEAD].
var _head_bone_idx: int = -1


## Resolves rig nodes, binds bone attachments, sets render layers, and builds [AnimationTree].
func _ready() -> void:
	set_process(false)
	set_physics_process(true)

	if not is_instance_valid(model_root):
		model_root = get_node_or_null(^"BellaModel") as Node3D
	if not is_instance_valid(head_cube_attachment):
		head_cube_attachment = get_node_or_null(^"HeadCubeAttachment") as BoneAttachment3D
	if not is_instance_valid(right_hand_attachment):
		right_hand_attachment = get_node_or_null(^"RightHandAttachment") as BoneAttachment3D
	if not is_instance_valid(world_revolver) and is_instance_valid(right_hand_attachment):
		world_revolver = right_hand_attachment.get_node_or_null(^"WorldRevolver") as Node3D
	if not is_instance_valid(world_shotgun) and is_instance_valid(right_hand_attachment):
		world_shotgun = right_hand_attachment.get_node_or_null(^"WorldShotgun") as Node3D

	assert(is_instance_valid(model_root), "PlayerBodyController requires model_root.")

	_skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	_anim_player = model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(is_instance_valid(_skeleton), "PlayerBodyController requires Skeleton3D.")
	assert(is_instance_valid(_anim_player), "PlayerBodyController requires AnimationPlayer.")

	_spine_bone_idx = _skeleton.find_bone(BONE_SPINE)
	_chest_bone_idx = _skeleton.find_bone(BONE_CHEST)
	_head_bone_idx = _skeleton.find_bone(BONE_HEAD)

	_bind_bone_attachments()
	_configure_render_layers()
	_setup_animation_tree()

	if is_instance_valid(Events):
		Utilities.safe_connect(Events.active_weapon_changed, _on_active_weapon_changed)

	_sync_initial_weapon()


## Disconnects [Events] and [AnimationTree] signals when leaving the scene tree.
func _exit_tree() -> void:
	if is_instance_valid(Events):
		if Events.active_weapon_changed.is_connected(_on_active_weapon_changed):
			Events.active_weapon_changed.disconnect(_on_active_weapon_changed)
	if is_instance_valid(_anim_tree) and _anim_tree.mixer_applied.is_connected(_on_mixer_applied):
		_anim_tree.mixer_applied.disconnect(_on_mixer_applied)


## Samples player locomotion, crouch, air, wolf mode, and pitch to drive [AnimationTree].
func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	var wolf_val: Variant = player.get(&"is_wolf_mode")
	var is_wolf: bool = wolf_val if wolf_val is bool else false
	visible = not is_wolf
	if is_wolf:
		return

	var is_airborne: bool = not player.is_on_floor()
	var is_crouching: bool = (
		is_instance_valid(locomotion_component) and locomotion_component.crouching
	)

	var walk_speed: float = (
		locomotion_component.walking_speed
		if is_instance_valid(locomotion_component)
		else DEFAULT_WALK_SPEED
	)
	var run_speed: float = (
		locomotion_component.sprinting_speed
		if is_instance_valid(locomotion_component)
		else DEFAULT_RUN_SPEED
	)
	var crouch_speed: float = (
		locomotion_component.crouching_speed
		if is_instance_valid(locomotion_component)
		else DEFAULT_CROUCH_SPEED
	)
	walk_speed = maxf(walk_speed, 0.1)
	run_speed = maxf(run_speed, walk_speed + 0.1)
	crouch_speed = maxf(crouch_speed, 0.1)

	var basis_right: Vector3 = Vector3(
		player.global_transform.basis.x.x, 0.0, player.global_transform.basis.x.z
	)
	basis_right = (
		basis_right.normalized() if basis_right.length_squared() > 0.0001 else Vector3.RIGHT
	)
	var basis_fwd: Vector3 = Vector3(
		-player.global_transform.basis.z.x, 0.0, -player.global_transform.basis.z.z
	)
	basis_fwd = basis_fwd.normalized() if basis_fwd.length_squared() > 0.0001 else Vector3.FORWARD

	var right_vel: float = player.velocity.dot(basis_right)
	var fwd_vel: float = player.velocity.dot(basis_fwd)

	var target_x: float = clampf(right_vel / walk_speed, -1.0, 1.0)
	var target_y: float = 0.0
	if fwd_vel >= 0.0:
		if fwd_vel <= walk_speed:
			target_y = fwd_vel / walk_speed
		else:
			var run_alpha: float = clampf(
				(fwd_vel - walk_speed) / (run_speed - walk_speed), 0.0, 1.0
			)
			target_y = 1.0 + run_alpha * (RUN_BLEND_Y - 1.0)
	else:
		target_y = clampf(fwd_vel / walk_speed, -1.0, 0.0)

	var planar_speed: float = Vector2(right_vel, fwd_vel).length()
	var target_crouch: float = clampf(planar_speed / crouch_speed, 0.0, 1.0)

	_locomotion_blend = MathUtils.damp_v2(
		_locomotion_blend, Vector2(target_x, target_y), BLEND_SMOOTH_SPEED, delta
	)
	_crouch_blend = MathUtils.damp(_crouch_blend, target_crouch, BLEND_SMOOTH_SPEED, delta)
	_weapon_blend = MathUtils.damp(_weapon_blend, _target_weapon_blend, BLEND_SMOOTH_SPEED, delta)

	if is_instance_valid(_anim_tree):
		_anim_tree.set(PARAM_LOCOMOTION_BLEND, _locomotion_blend)
		_anim_tree.set(PARAM_CROUCH_BLEND, _crouch_blend)
		_anim_tree.set(PARAM_WEAPON_BLEND, _weapon_blend)

	var target_state: StringName = (
		STATE_AIR if is_airborne else (STATE_CROUCH if is_crouching else STATE_LOCOMOTION)
	)
	if _current_state != target_state:
		_travel_to_state(target_state)

	var target_pitch: float = 0.0
	if is_instance_valid(camera_controller) and is_instance_valid(camera_controller.head):
		target_pitch = clampf(
			camera_controller.head.rotation.x, -MAX_LOOK_PITCH_RAD, MAX_LOOK_PITCH_RAD
		)
	_look_pitch_rad = MathUtils.damp(_look_pitch_rad, target_pitch, BLEND_SMOOTH_SPEED, delta)


## Returns the rigged [Skeleton3D] discovered inside [member model_root].
func get_skeleton() -> Skeleton3D:
	return _skeleton


## Returns the runtime [AnimationTree] built for locomotion and weapon overlay blending.
func get_animation_tree() -> AnimationTree:
	return _anim_tree


## Returns the active base state machine state name.
func get_current_state() -> StringName:
	return _current_state


## Returns the currently active normalized weapon tag string.
func get_active_weapon_tag() -> String:
	return _active_weapon_tag


## Binds [member head_cube_attachment] and [member right_hand_attachment] to [member _skeleton].
func _bind_bone_attachments() -> void:
	var skel_path: NodePath = _skeleton.get_path()
	if is_instance_valid(head_cube_attachment):
		head_cube_attachment.use_external_skeleton = true
		head_cube_attachment.set_external_skeleton(skel_path)
		head_cube_attachment.bone_name = BONE_HEAD
	if is_instance_valid(right_hand_attachment):
		right_hand_attachment.use_external_skeleton = true
		right_hand_attachment.set_external_skeleton(skel_path)
		right_hand_attachment.bone_name = BONE_RIGHT_HAND


## Assigns Layer 1 to visible body/clothing and Layer 2 + shadows to arms/head/weapons.
func _configure_render_layers() -> void:
	for mesh_name: StringName in ENV_LAYER_MESHES:
		var env_mesh: MeshInstance3D = (
			model_root.find_child(String(mesh_name), true, false) as MeshInstance3D
		)
		if is_instance_valid(env_mesh):
			env_mesh.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
			env_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	for mesh_name: StringName in PLAYER_LAYER_MESHES:
		var player_mesh: MeshInstance3D = (
			model_root.find_child(String(mesh_name), true, false) as MeshInstance3D
		)
		if is_instance_valid(player_mesh):
			player_mesh.layers = CollisionLayers.RENDER_MASK_PLAYER
			player_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	if is_instance_valid(head_cube_attachment):
		var head_cube: MeshInstance3D = (
			head_cube_attachment.find_child("HeadCube", true, false) as MeshInstance3D
		)
		if is_instance_valid(head_cube):
			head_cube.layers = CollisionLayers.RENDER_MASK_PLAYER
			head_cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	if is_instance_valid(world_revolver):
		_set_mesh_layers_recursive(
			world_revolver,
			CollisionLayers.RENDER_MASK_PLAYER,
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
	if is_instance_valid(world_shotgun):
		_set_mesh_layers_recursive(
			world_shotgun,
			CollisionLayers.RENDER_MASK_PLAYER,
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)


## Recursively sets render [param layer_mask] and [param shadow_mode] on [MeshInstance3D] nodes.
func _set_mesh_layers_recursive(
	node: Node, layer_mask: int, shadow_mode: GeometryInstance3D.ShadowCastingSetting
) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		mesh_inst.layers = layer_mask
		mesh_inst.cast_shadow = shadow_mode
	for child: Node in node.get_children():
		_set_mesh_layers_recursive(child, layer_mask, shadow_mode)


## Builds the runtime [AnimationTree] ([AnimationNodeBlendTree]) and enables clip looping.
func _setup_animation_tree() -> void:
	for clip_name: StringName in LOOPING_CLIPS:
		if _anim_player.has_animation(clip_name):
			var anim: Animation = _anim_player.get_animation(clip_name)
			if is_instance_valid(anim):
				anim.loop_mode = Animation.LOOP_LINEAR

	_anim_tree = get_node_or_null(^"AnimationTree") as AnimationTree
	if not is_instance_valid(_anim_tree):
		_anim_tree = AnimationTree.new()
		_anim_tree.name = "AnimationTree"
		add_child(_anim_tree)

	var blend_tree: AnimationNodeBlendTree = AnimationNodeBlendTree.new()
	var state_machine: AnimationNodeStateMachine = _build_base_state_machine()
	blend_tree.add_node(&"state_machine", state_machine)

	var weapon_pose: AnimationNodeTransition = AnimationNodeTransition.new()
	weapon_pose.xfade_time = STATE_CROSSFADE_SEC
	weapon_pose.set_input_count(2)
	weapon_pose.set_input_name(0, WEAPON_TAG_REVOLVER)
	weapon_pose.set_input_name(1, WEAPON_TAG_SHOTGUN)

	var revolver_anim: AnimationNodeAnimation = AnimationNodeAnimation.new()
	revolver_anim.animation = &"hold_revolver"
	var shotgun_anim: AnimationNodeAnimation = AnimationNodeAnimation.new()
	shotgun_anim.animation = &"hold_shotgun"

	blend_tree.add_node(&"hold_revolver", revolver_anim)
	blend_tree.add_node(&"hold_shotgun", shotgun_anim)
	blend_tree.add_node(&"weapon_pose", weapon_pose)
	blend_tree.connect_node(&"weapon_pose", 0, &"hold_revolver")
	blend_tree.connect_node(&"weapon_pose", 1, &"hold_shotgun")

	var weapon_blend: AnimationNodeBlend2 = AnimationNodeBlend2.new()
	_configure_upper_body_filter(weapon_blend)
	blend_tree.add_node(&"weapon_blend", weapon_blend)
	blend_tree.connect_node(&"weapon_blend", 0, &"state_machine")
	blend_tree.connect_node(&"weapon_blend", 1, &"weapon_pose")
	blend_tree.connect_node(&"output", 0, &"weapon_blend")

	_anim_tree.tree_root = blend_tree
	_anim_tree.root_node = _anim_tree.get_path_to(model_root)
	_anim_tree.anim_player = _anim_tree.get_path_to(_anim_player)
	_anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_anim_tree.active = true

	_anim_tree.set(PARAM_LOCOMOTION_BLEND, Vector2.ZERO)
	_anim_tree.set(PARAM_CROUCH_BLEND, 0.0)
	_anim_tree.set(PARAM_WEAPON_BLEND, 0.0)
	_anim_tree.set(PARAM_WEAPON_POSE_REQ, WEAPON_TAG_REVOLVER)

	var raw_pb: Variant = _anim_tree.get(PARAM_SM_PLAYBACK)
	if raw_pb is AnimationNodeStateMachinePlayback:
		_sm_playback = raw_pb as AnimationNodeStateMachinePlayback
		_sm_playback.start(STATE_LOCOMOTION, true)
	_current_state = STATE_LOCOMOTION

	if not _anim_tree.mixer_applied.is_connected(_on_mixer_applied):
		_anim_tree.mixer_applied.connect(_on_mixer_applied)
	_anim_tree.advance(0.0)


## Constructs the base [AnimationNodeStateMachine] with locomotion, crouch, and air states.
func _build_base_state_machine() -> AnimationNodeStateMachine:
	var state_machine: AnimationNodeStateMachine = AnimationNodeStateMachine.new()

	var loco_bs: AnimationNodeBlendSpace2D = AnimationNodeBlendSpace2D.new()
	loco_bs.min_space = Vector2(-1.0, -1.0)
	loco_bs.max_space = Vector2(1.0, RUN_BLEND_Y)
	loco_bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	_add_blend_point_2d(loco_bs, &"idle", Vector2(0.0, 0.0))
	_add_blend_point_2d(loco_bs, &"walk_fwd", Vector2(0.0, 1.0))
	_add_blend_point_2d(loco_bs, &"run_fwd", Vector2(0.0, RUN_BLEND_Y))
	_add_blend_point_2d(loco_bs, &"walk_back", Vector2(0.0, -1.0))
	_add_blend_point_2d(loco_bs, &"strafe_left", Vector2(-1.0, 0.0))
	_add_blend_point_2d(loco_bs, &"strafe_right", Vector2(1.0, 0.0))
	state_machine.add_node(STATE_LOCOMOTION, loco_bs)

	var crouch_bs: AnimationNodeBlendSpace1D = AnimationNodeBlendSpace1D.new()
	crouch_bs.min_space = 0.0
	crouch_bs.max_space = 1.0
	crouch_bs.blend_mode = AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED
	_add_blend_point_1d(crouch_bs, &"crouch_idle", 0.0)
	_add_blend_point_1d(crouch_bs, &"crouch_walk", 1.0)
	state_machine.add_node(STATE_CROUCH, crouch_bs)

	var air_anim: AnimationNodeAnimation = AnimationNodeAnimation.new()
	air_anim.animation = &"jump_air"
	state_machine.add_node(STATE_AIR, air_anim)

	var start_trans: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
	start_trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	state_machine.add_transition(&"Start", STATE_LOCOMOTION, start_trans)

	var states: Array[StringName] = [STATE_LOCOMOTION, STATE_CROUCH, STATE_AIR]
	for from_state: StringName in states:
		for to_state: StringName in states:
			if from_state == to_state:
				continue
			var xfade_trans: AnimationNodeStateMachineTransition = (
				AnimationNodeStateMachineTransition.new()
			)
			xfade_trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			xfade_trans.xfade_time = STATE_CROSSFADE_SEC
			state_machine.add_transition(from_state, to_state, xfade_trans)

	return state_machine


## Adds a named animation point to a 2D locomotion [AnimationNodeBlendSpace2D].
func _add_blend_point_2d(
	blend_space: AnimationNodeBlendSpace2D, clip_name: StringName, pos: Vector2
) -> void:
	var anim_node: AnimationNodeAnimation = AnimationNodeAnimation.new()
	anim_node.animation = clip_name
	blend_space.add_blend_point(anim_node, pos, -1, clip_name)


## Adds a named animation point to a 1D crouch [AnimationNodeBlendSpace1D].
func _add_blend_point_1d(
	blend_space: AnimationNodeBlendSpace1D, clip_name: StringName, pos: float
) -> void:
	var anim_node: AnimationNodeAnimation = AnimationNodeAnimation.new()
	anim_node.animation = clip_name
	blend_space.add_blend_point(anim_node, pos, -1, clip_name)


## Enables bone filtering on upper-body and finger bones present in [member _skeleton].
func _configure_upper_body_filter(weapon_blend: AnimationNodeBlend2) -> void:
	weapon_blend.filter_enabled = true
	var skel_rel: String = String(model_root.get_path_to(_skeleton))
	for bone_name: String in UPPER_BODY_BONES:
		if _skeleton.find_bone(bone_name) >= 0:
			weapon_blend.set_filter_path(NodePath(skel_rel + ":" + bone_name), true)

	for i: int in range(_skeleton.get_bone_count()):
		var skel_bone_name: String = _skeleton.get_bone_name(i)
		if _is_finger_bone(skel_bone_name):
			weapon_blend.set_filter_path(NodePath(skel_rel + ":" + skel_bone_name), true)


## Returns true when [param bone_name] matches a finger bone naming pattern.
func _is_finger_bone(bone_name: String) -> bool:
	var lower_name: String = bone_name.to_lower()
	for substr: String in FINGER_SUBSTRINGS:
		if lower_name.contains(substr):
			return true
	return false


## Transitions the base state machine cleanly to [param target_state].
func _travel_to_state(target_state: StringName) -> void:
	_current_state = target_state
	if not is_instance_valid(_sm_playback):
		return
	var cur_node: StringName = _sm_playback.get_current_node()
	if cur_node.is_empty() or cur_node == &"Start":
		_sm_playback.start(target_state, true)
	elif cur_node != target_state:
		_sm_playback.travel(target_state)


## Syncs initial world weapon visibility and pose from [member weapon_inventory_component].
func _sync_initial_weapon() -> void:
	if not is_instance_valid(weapon_inventory_component):
		_apply_active_weapon("", true)
		return

	var slot_idx: int = weapon_inventory_component.current_slot_index
	if slot_idx < 0 or slot_idx >= weapon_inventory_component.slots.size():
		_apply_active_weapon("", true)
		return

	var active_gun: Node3D = weapon_inventory_component.slots[slot_idx]
	if not is_instance_valid(active_gun):
		_apply_active_weapon("", true)
		return

	var tag_val: Variant = active_gun.get(&"weapon_tag")
	var tag: String = tag_val if tag_val is String else String(active_gun.name)
	_apply_active_weapon(tag, true)


## Updates world weapon visibility and upper-body pose parameters for [param weapon_id].
func _apply_active_weapon(weapon_id: String, immediate: bool = false) -> void:
	var normalized: String = weapon_id.strip_edges().to_lower()
	_active_weapon_tag = normalized

	var has_revolver: bool = normalized == WEAPON_TAG_REVOLVER
	var has_shotgun: bool = normalized == WEAPON_TAG_SHOTGUN

	if is_instance_valid(world_revolver):
		world_revolver.visible = has_revolver
	if is_instance_valid(world_shotgun):
		world_shotgun.visible = has_shotgun

	_target_weapon_blend = 1.0 if (has_revolver or has_shotgun) else 0.0
	if is_instance_valid(_anim_tree):
		if has_revolver:
			_anim_tree.set(PARAM_WEAPON_POSE_REQ, WEAPON_TAG_REVOLVER)
		elif has_shotgun:
			_anim_tree.set(PARAM_WEAPON_POSE_REQ, WEAPON_TAG_SHOTGUN)
		if immediate:
			_weapon_blend = _target_weapon_blend
			_anim_tree.set(PARAM_WEAPON_BLEND, _weapon_blend)


## Applies subtle camera pitch follow onto spine, chest, and head after [AnimationTree] runs.
func _on_mixer_applied() -> void:
	if not visible or not is_instance_valid(_skeleton) or is_zero_approx(_look_pitch_rad):
		return

	_apply_bone_pitch(_spine_bone_idx, _look_pitch_rad * 0.12)
	_apply_bone_pitch(_chest_bone_idx, _look_pitch_rad * 0.22)
	_apply_bone_pitch(_head_bone_idx, _look_pitch_rad * 0.40)


## Adds local pitch rotation [param pitch_rad] onto [param bone_idx] pose rotation.
func _apply_bone_pitch(bone_idx: int, pitch_rad: float) -> void:
	if bone_idx < 0:
		return
	var base_rot: Quaternion = _skeleton.get_bone_pose_rotation(bone_idx)
	_skeleton.set_bone_pose_rotation(bone_idx, base_rot * Quaternion(Vector3.RIGHT, -pitch_rad))


## Callback reacting to [signal Events.active_weapon_changed].
func _on_active_weapon_changed(weapon_id: String) -> void:
	_apply_active_weapon(weapon_id, false)
