## Interactive warehouse shelf supporting kinematic push-aside and topple manipulation.
class_name InteractiveShelf
extends AnimatableBody3D

## Emitted after a push-aside or topple manipulation tween completes.
signal shelf_manipulated(action: StringName)

## Action identifier emitted when the shelf is pushed sideways.
const ACTION_PUSH_ASIDE: StringName = &"shelf_push_aside"
## Action identifier emitted when the shelf is toppled onto the floor.
const ACTION_TOPPLE: StringName = &"shelf_topple"
## Lateral slide distance in meters when pushed aside.
const PUSH_SLIDE_DISTANCE_M: float = 1.6
## Yaw angle in radians added when pushed aside.
const PUSH_YAW_RAD: float = deg_to_rad(18.0)
## Tip angle in radians (90 degrees) when toppled onto the floor.
const TOPPLE_ANGLE_RAD: float = PI * 0.5
## Forward translation in meters applied while toppling onto the floor.
const TOPPLE_FORWARD_OFFSET_M: float = 0.55
## Half-depth vertical lift in meters so toppled shelf rests flush on the floor.
const TOPPLE_FLOOR_LIFT_M: float = 0.45
## Minimum squared planar vector length to treat a push direction as valid.
const MIN_DIR_LEN_SQ: float = 0.0004

## Enables NPC push-aside and topple manipulation when true.
@export var pushable: bool = false
## Optional [NavigationLink3D] disabled automatically once this shelf is cleared.
@export var linked_nav_link: NodePath = NodePath()

## True once the shelf has been pushed aside or toppled clear.
var _is_cleared: bool = false
## True while a push-aside or topple [Tween] is actively running.
var _is_manipulating: bool = false
## Active [Tween] driving kinematic shelf motion.
var _manip_tween: Tween = null


## Disables physics sync so kinematic [Tween] motion runs cleanly without jitter.
func _ready() -> void:
	sync_to_physics = false


## Kills any active manipulation [Tween] when leaving the scene tree.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_manip_tween)


## Returns true once this shelf has been moved or toppled out of the path.
func is_cleared() -> bool:
	return _is_cleared


## Returns true when [member pushable] is enabled and the shelf has not been manipulated yet.
func can_manipulate() -> bool:
	return pushable and not _is_cleared and not _is_manipulating


## Tweens the shelf sideways ~1.6m with ~18 deg yaw, then marks cleared and disables nav link.
func push_aside(push_dir: Vector3, duration: float = 0.85) -> void:
	if not can_manipulate():
		return
	_is_manipulating = true

	var side_axis: Vector3 = global_transform.basis.x
	side_axis.y = 0.0
	if side_axis.length_squared() < MIN_DIR_LEN_SQ:
		side_axis = Vector3.RIGHT
	else:
		side_axis = side_axis.normalized()

	var planar_push: Vector3 = Vector3(push_dir.x, 0.0, push_dir.z)
	if planar_push.length_squared() >= MIN_DIR_LEN_SQ and planar_push.dot(side_axis) < 0.0:
		side_axis = -side_axis

	var yaw_sign: float = 1.0 if side_axis.dot(global_transform.basis.x) >= 0.0 else -1.0
	var target_pos: Vector3 = global_position + side_axis * PUSH_SLIDE_DISTANCE_M
	var target_basis: Basis = (
		(Basis(Vector3.UP, PUSH_YAW_RAD * yaw_sign) * global_transform.basis).orthonormalized()
	)
	var target_quat: Quaternion = _global_basis_to_local_quat(target_basis)

	if duration <= 0.0 or not is_inside_tree():
		global_position = target_pos
		quaternion = target_quat
		_complete_manipulation(ACTION_PUSH_ASIDE)
		return

	var tw: Tween = Utilities.reset_tween(self, _manip_tween)
	_manip_tween = tw
	if not is_instance_valid(tw):
		global_position = target_pos
		quaternion = target_quat
		_complete_manipulation(ACTION_PUSH_ASIDE)
		return

	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", target_pos, duration)
	tw.tween_property(self, "quaternion", target_quat, duration)
	tw.finished.connect(_complete_manipulation.bind(ACTION_PUSH_ASIDE), Object.CONNECT_ONE_SHOT)


## Tweens the shelf 90 deg onto the floor along [param push_dir], then marks cleared.
func topple(push_dir: Vector3, duration: float = 0.85) -> void:
	if not can_manipulate():
		return
	_is_manipulating = true

	var tip_dir: Vector3 = Vector3(push_dir.x, 0.0, push_dir.z)
	if tip_dir.length_squared() < MIN_DIR_LEN_SQ:
		tip_dir = -global_transform.basis.z
		tip_dir.y = 0.0
	if tip_dir.length_squared() < MIN_DIR_LEN_SQ:
		tip_dir = Vector3.FORWARD
	else:
		tip_dir = tip_dir.normalized()

	var tip_axis: Vector3 = Vector3.UP.cross(tip_dir)
	if tip_axis.length_squared() < MIN_DIR_LEN_SQ:
		tip_axis = Vector3.RIGHT
	else:
		tip_axis = tip_axis.normalized()

	var target_pos: Vector3 = (
		global_position + tip_dir * TOPPLE_FORWARD_OFFSET_M + Vector3(0.0, TOPPLE_FLOOR_LIFT_M, 0.0)
	)
	var target_basis: Basis = (
		(Basis(tip_axis, TOPPLE_ANGLE_RAD) * global_transform.basis).orthonormalized()
	)
	var target_quat: Quaternion = _global_basis_to_local_quat(target_basis)

	if duration <= 0.0 or not is_inside_tree():
		global_position = target_pos
		quaternion = target_quat
		_complete_manipulation(ACTION_TOPPLE)
		return

	var tw: Tween = Utilities.reset_tween(self, _manip_tween)
	_manip_tween = tw
	if not is_instance_valid(tw):
		global_position = target_pos
		quaternion = target_quat
		_complete_manipulation(ACTION_TOPPLE)
		return

	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "global_position", target_pos, duration)
	tw.tween_property(self, "quaternion", target_quat, duration)
	tw.finished.connect(_complete_manipulation.bind(ACTION_TOPPLE), Object.CONNECT_ONE_SHOT)


## Converts a world-space [Basis] into a local [Quaternion] relative to the parent [Node3D].
func _global_basis_to_local_quat(world_basis: Basis) -> Quaternion:
	var parent_3d: Node3D = get_parent() as Node3D
	if is_instance_valid(parent_3d):
		var local_basis: Basis = (
			(parent_3d.global_transform.basis.inverse() * world_basis).orthonormalized()
		)
		return local_basis.get_rotation_quaternion()
	return world_basis.orthonormalized().get_rotation_quaternion()


## Marks the shelf cleared, disables [member linked_nav_link], and emits [signal shelf_manipulated].
func _complete_manipulation(action: StringName) -> void:
	_is_manipulating = false
	_is_cleared = true
	if not linked_nav_link.is_empty():
		var link_node: Node = get_node_or_null(linked_nav_link)
		if link_node is NavigationLink3D:
			(link_node as NavigationLink3D).enabled = false
	shelf_manipulated.emit(action)
	print("InteractiveShelf: ", name, " manipulated -> ", action)
