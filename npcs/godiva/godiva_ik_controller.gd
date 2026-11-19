## Native Godot 4.7 [TwoBoneIK3D] controller for Godiva foot grounding and hand surface contact.
class_name GodivaIKController
extends Node

## Vertical offset above actor origin where foot grounding rays begin (meters).
const FOOT_RAY_UP_M: float = 0.45
## Vertical depth below actor origin where foot grounding rays terminate (meters).
const FOOT_RAY_DOWN_M: float = 0.35
## Minimum uneven foot height delta (meters) before applying gentle pelvis drop.
const PELVIS_DROP_THRESHOLD_M: float = 0.02

@export_group("IK Configuration")
## Maximum camera distance in meters for active foot grounding raycasts.
@export_range(2.0, 50.0, 0.5) var max_ik_distance: float = 22.0:
	set(value):
		max_ik_distance = maxf(2.0, value)
		_max_ik_distance_sq = max_ik_distance * max_ik_distance
## Exponential smoothing speed for foot targets and foot IK influence.
@export_range(1.0, 35.0, 0.5) var foot_smooth_speed: float = 16.0
## Exponential smoothing speed for hand targets and hand IK influence.
@export_range(1.0, 35.0, 0.5) var hand_smooth_speed: float = 14.0
## Vertical offset in meters from ground contact to the ankle bone rest origin.
@export_range(0.0, 0.25, 0.005) var foot_sole_offset: float = 0.097
## Maximum downward pelvis offset in meters when straddling uneven steps.
@export_range(0.0, 0.35, 0.01) var max_pelvis_offset: float = 0.22

## Owner [CharacterBody3D] providing grounded state, transform, and physics exclusion.
var _actor: CharacterBody3D = null
## Rigged [Skeleton3D] hosting the native [TwoBoneIK3D] modifiers.
var _skeleton: Skeleton3D = null
## Optional model root [Node3D] receiving gentle pelvis height offsets on uneven steps.
var _model_root: Node3D = null
## Container [Node3D] holding the 4 world-space IK [Marker3D] targets.
var _targets_root: Node3D = null
## Multi-setting [TwoBoneIK3D] modifier driving left and right leg grounding.
var _foot_ik: TwoBoneIK3D = null
## Multi-setting [TwoBoneIK3D] modifier driving left and right hand surface contact.
var _hand_ik: TwoBoneIK3D = null
## World-space [Marker3D] target for the left foot bone.
var _left_foot_target: Marker3D = null
## World-space [Marker3D] target for the right foot bone.
var _right_foot_target: Marker3D = null
## World-space [Marker3D] target for the left hand bone.
var _left_hand_target: Marker3D = null
## World-space [Marker3D] target for the right hand bone.
var _right_hand_target: Marker3D = null
## Cached bone index for LeftFoot inside [member _skeleton].
var _left_foot_bone: int = -1
## Cached bone index for RightFoot inside [member _skeleton].
var _right_foot_bone: int = -1
## Cached squared distance limit for zero-sqrt proximity gating.
var _max_ik_distance_sq: float = 484.0
## True when the actor is inside the active camera frustum.
var _is_on_screen: bool = true
## True when prone, climb, vault, or tween traversal suppresses foot grounding IK.
var _foot_ik_suppressed: bool = false
## True while hand surface contact IK has active world targets.
var _hand_ik_active: bool = false
## Target influence weight in [0.0, 1.0] for [member _hand_ik].
var _hand_target_weight: float = 0.0
## Desired world-space position for [member _left_hand_target].
var _desired_left_hand: Vector3 = Vector3.ZERO
## Desired world-space position for [member _right_hand_target].
var _desired_right_hand: Vector3 = Vector3.ZERO
## Rest local Y offset of [member _model_root] preserved across pelvis adjustments.
var _base_model_y: float = 0.0
## Current vertical pelvis offset applied to [member _model_root].
var _pelvis_offset: float = 0.0
## Cached [PhysicsRayQueryParameters3D] reused every physics tick with zero allocations.
var _foot_ray_query: PhysicsRayQueryParameters3D = null
## Reusable exclusion [RID] array for [member _foot_ray_query].
var _ray_exclude: Array[RID] = []
## True once [method initialize] has attached modifiers and target markers.
var _is_initialized: bool = false


## Initializes defaults and keeps physics updates disabled until [method initialize] runs.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_max_ik_distance_sq = max_ik_distance * max_ik_distance


## Updates foot grounding raycasts, pelvis step offset, and hand surface contact blending.
func _physics_process(delta: float) -> void:
	if not _is_initialized or not is_instance_valid(_actor) or not is_instance_valid(_skeleton):
		return

	_update_foot_grounding(delta)
	_update_hand_contact(delta)


## Attaches [TwoBoneIK3D] FootIK and HandIK modifiers under [param skeleton] and creates targets.
func initialize(
	skeleton: Skeleton3D, owner_actor: CharacterBody3D, model_root: Node3D = null
) -> void:
	if not is_instance_valid(skeleton) or not is_instance_valid(owner_actor):
		return

	_skeleton = skeleton
	_actor = owner_actor
	_model_root = model_root
	if is_instance_valid(_model_root):
		_base_model_y = _model_root.position.y

	_left_foot_bone = _skeleton.find_bone("LeftFoot")
	_right_foot_bone = _skeleton.find_bone("RightFoot")

	_targets_root = _actor.get_node_or_null(^"IKTargets") as Node3D
	if not is_instance_valid(_targets_root):
		_targets_root = Node3D.new()
		_targets_root.name = "IKTargets"
		_actor.add_child(_targets_root)

	_left_foot_target = _ensure_target_marker("LeftFootTarget")
	_right_foot_target = _ensure_target_marker("RightFootTarget")
	_left_hand_target = _ensure_target_marker("LeftHandTarget")
	_right_hand_target = _ensure_target_marker("RightHandTarget")

	_foot_ik = _setup_two_bone_modifier(
		"FootIK",
		"LeftUpperLeg",
		"LeftLowerLeg",
		"LeftFoot",
		_left_foot_target,
		"RightUpperLeg",
		"RightLowerLeg",
		"RightFoot",
		_right_foot_target,
		SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z,
	)
	_hand_ik = _setup_two_bone_modifier(
		"HandIK",
		"LeftUpperArm",
		"LeftLowerArm",
		"LeftHand",
		_left_hand_target,
		"RightUpperArm",
		"RightLowerArm",
		"RightHand",
		_right_hand_target,
		SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_Z,
	)

	_foot_ray_query = PhysicsRayQueryParameters3D.new()
	_foot_ray_query.collision_mask = CollisionLayers.MASK_SOLID_WORLD
	_foot_ray_query.collide_with_bodies = true
	_foot_ray_query.collide_with_areas = false
	_ray_exclude.clear()
	_ray_exclude.append(_actor.get_rid())
	_foot_ray_query.exclude = _ray_exclude

	_is_initialized = true
	_refresh_tick_state()


## Pins left and right hand IK targets to world positions with [param weight] influence.
func set_hand_targets(left_world: Vector3, right_world: Vector3, weight: float = 0.85) -> void:
	_desired_left_hand = left_world
	_desired_right_hand = right_world
	_hand_target_weight = clampf(weight, 0.0, 1.0)
	if not _hand_ik_active:
		if is_instance_valid(_left_hand_target):
			_left_hand_target.global_position = left_world
		if is_instance_valid(_right_hand_target):
			_right_hand_target.global_position = right_world
	_hand_ik_active = _hand_target_weight > 0.001
	_refresh_tick_state()


## Releases hand surface contact IK so hands smoothly blend back to authored animations.
func clear_hand_targets() -> void:
	_hand_ik_active = false
	_hand_target_weight = 0.0


## Suppresses or enables foot grounding IK (disabled during prone, climb, vault, and tweens).
func set_foot_ik_suppressed(suppressed: bool) -> void:
	_foot_ik_suppressed = suppressed
	if suppressed and is_instance_valid(_foot_ik) and not is_physics_processing():
		_foot_ik.influence = 0.0


## Gates IK updates based on [VisibleOnScreenNotifier3D] visibility callbacks.
func set_visible_on_screen(is_visible: bool) -> void:
	_is_on_screen = is_visible
	_refresh_tick_state()


## Returns the native [TwoBoneIK3D] modifier driving leg grounding.
func get_foot_ik() -> TwoBoneIK3D:
	return _foot_ik


## Returns the native [TwoBoneIK3D] modifier driving hand surface contact.
func get_hand_ik() -> TwoBoneIK3D:
	return _hand_ik


## Returns true while hand surface contact IK targets are active.
func is_hand_ik_active() -> bool:
	return _hand_ik_active


## Returns true while foot grounding IK is suppressed by prone or traversal state.
func is_foot_ik_suppressed() -> bool:
	return _foot_ik_suppressed


## Creates or retrieves a named [Marker3D] child inside [member _targets_root].
func _ensure_target_marker(marker_name: String) -> Marker3D:
	var marker: Marker3D = _targets_root.get_node_or_null(NodePath(marker_name)) as Marker3D
	if not is_instance_valid(marker):
		marker = Marker3D.new()
		marker.name = marker_name
		_targets_root.add_child(marker)
	return marker


## Builds a 2-chain [TwoBoneIK3D] modifier under [member _skeleton] for symmetric limbs.
func _setup_two_bone_modifier(
	mod_name: String,
	left_root: String,
	left_mid: String,
	left_end: String,
	left_target: Marker3D,
	right_root: String,
	right_mid: String,
	right_end: String,
	right_target: Marker3D,
	pole_dir: SkeletonModifier3D.SecondaryDirection,
) -> TwoBoneIK3D:
	var ik: TwoBoneIK3D = _skeleton.get_node_or_null(NodePath(mod_name)) as TwoBoneIK3D
	if not is_instance_valid(ik):
		ik = TwoBoneIK3D.new()
		ik.name = mod_name
		_skeleton.add_child(ik)

	ik.set_setting_count(2)
	ik.set_root_bone_name(0, left_root)
	ik.set_middle_bone_name(0, left_mid)
	ik.set_end_bone_name(0, left_end)
	ik.set_pole_direction(0, pole_dir)
	ik.set_target_node(0, ik.get_path_to(left_target))

	ik.set_root_bone_name(1, right_root)
	ik.set_middle_bone_name(1, right_mid)
	ik.set_end_bone_name(1, right_end)
	ik.set_pole_direction(1, pole_dir)
	ik.set_target_node(1, ik.get_path_to(right_target))

	ik.influence = 0.0
	ik.active = true
	return ik


## Casts downward foot rays and smoothly updates [member _foot_ik] targets and pelvis offset.
func _update_foot_grounding(delta: float) -> void:
	if not is_instance_valid(_foot_ik):
		return

	var foot_alpha: float = 1.0 - exp(-foot_smooth_speed * delta)
	var can_ground: bool = (
		not _foot_ik_suppressed and _actor.is_on_floor() and _is_within_ik_distance()
	)
	if not can_ground:
		_foot_ik.influence = lerpf(_foot_ik.influence, 0.0, foot_alpha)
		_apply_pelvis_offset(0.0, foot_alpha)
		return

	var world_3d: World3D = _actor.get_world_3d()
	if not is_instance_valid(world_3d):
		_foot_ik.influence = lerpf(_foot_ik.influence, 0.0, foot_alpha)
		return
	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if not is_instance_valid(space):
		_foot_ik.influence = lerpf(_foot_ik.influence, 0.0, foot_alpha)
		return

	var actor_y: float = _actor.global_position.y
	var left_delta: float = 0.0
	var right_delta: float = 0.0
	var left_hit: bool = _probe_foot_target(
		space, _left_foot_bone, _left_foot_target, actor_y, foot_alpha
	)
	var right_hit: bool = _probe_foot_target(
		space, _right_foot_bone, _right_foot_target, actor_y, foot_alpha
	)

	if left_hit:
		left_delta = (_left_foot_target.global_position.y - foot_sole_offset) - actor_y
	if right_hit:
		right_delta = (_right_foot_target.global_position.y - foot_sole_offset) - actor_y

	var desired_influence: float = 1.0 if (left_hit or right_hit) else 0.0
	_foot_ik.influence = lerpf(_foot_ik.influence, desired_influence, foot_alpha)

	var desired_pelvis: float = 0.0
	if left_hit and right_hit:
		var lowest: float = minf(left_delta, right_delta)
		if lowest < -PELVIS_DROP_THRESHOLD_M:
			desired_pelvis = clampf(lowest, -max_pelvis_offset, 0.0)
	_apply_pelvis_offset(desired_pelvis, foot_alpha)


## Casts a single downward ray for [param bone_idx] and smoothly moves [param target] to hit point.
func _probe_foot_target(
	space: PhysicsDirectSpaceState3D,
	bone_idx: int,
	target: Marker3D,
	actor_y: float,
	alpha: float,
) -> bool:
	if bone_idx < 0 or not is_instance_valid(target):
		return false

	var foot_world: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(bone_idx).origin)
	_foot_ray_query.from = Vector3(foot_world.x, actor_y + FOOT_RAY_UP_M, foot_world.z)
	_foot_ray_query.to = Vector3(foot_world.x, actor_y - FOOT_RAY_DOWN_M, foot_world.z)
	var hit: Dictionary = space.intersect_ray(_foot_ray_query)
	if hit.is_empty():
		return false

	var raw_pos: Variant = hit.get("position", foot_world)
	if not (raw_pos is Vector3):
		return false
	var hit_pos: Vector3 = raw_pos
	var desired: Vector3 = Vector3(foot_world.x, hit_pos.y + foot_sole_offset, foot_world.z)
	target.global_position = target.global_position.lerp(desired, alpha)
	return true


## Smoothly interpolates [member _hand_ik] targets and influence toward active surface anchors.
func _update_hand_contact(delta: float) -> void:
	if not is_instance_valid(_hand_ik):
		return

	var hand_alpha: float = 1.0 - exp(-hand_smooth_speed * delta)
	_hand_ik.influence = lerpf(_hand_ik.influence, _hand_target_weight, hand_alpha)
	if _hand_ik_active:
		if is_instance_valid(_left_hand_target):
			_left_hand_target.global_position = _left_hand_target.global_position.lerp(
				_desired_left_hand, hand_alpha
			)
		if is_instance_valid(_right_hand_target):
			_right_hand_target.global_position = _right_hand_target.global_position.lerp(
				_desired_right_hand, hand_alpha
			)
	elif _hand_ik.influence < 0.005:
		_hand_ik.influence = 0.0


## Applies a smoothed vertical pelvis offset to [member _model_root] on uneven stairs or slopes.
func _apply_pelvis_offset(target_offset: float, alpha: float) -> void:
	_pelvis_offset = lerpf(_pelvis_offset, target_offset, alpha)
	if absf(_pelvis_offset) < 0.001:
		_pelvis_offset = 0.0
	if is_instance_valid(_model_root):
		_model_root.position.y = _base_model_y + _pelvis_offset


## Returns true if the actor is within [member max_ik_distance] of the active camera.
func _is_within_ik_distance() -> bool:
	var vp: Viewport = _actor.get_viewport()
	if not is_instance_valid(vp):
		return true
	var cam: Camera3D = vp.get_camera_3d()
	if not is_instance_valid(cam):
		return true
	return _actor.global_position.distance_squared_to(cam.global_position) <= _max_ik_distance_sq


## Enables or disables [method _physics_process] based on initialization and screen visibility.
func _refresh_tick_state() -> void:
	set_physics_process(_is_initialized and _is_on_screen)
