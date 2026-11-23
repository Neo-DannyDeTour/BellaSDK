@tool
## Records 60 FPS Live Link Face [ARKitPacket] streams into Godot 4.7 [Animation] resources.
class_name ARKitRecorder
extends RefCounted

## Default output folder for recorded facial [Animation] clips.
const DEFAULT_SAVE_DIR: String = "res://assets/animations/bella_facial"
## Default head mesh path relative to the character root for 52 ARKit blendshape tracks.
const DEFAULT_HEAD_MESH_PATH: String = "BellaModel/Bella_Armature/Skeleton3D/Bella_Head"
## Default eyelash mesh path relative to the character root for 6 synced eyelid tracks.
const DEFAULT_LASH_MESH_PATH: String = "BellaModel/Bella_Armature/Skeleton3D/Bella_Eyelashes"
## Default [Skeleton3D] path relative to the character root for Head, Jaw, and Eye rotation tracks.
const DEFAULT_SKELETON_PATH: String = "BellaModel/Bella_Armature/Skeleton3D"
## Maximum downward jaw rotation in degrees at [code]jawOpen = 1.0[/code].
const DEFAULT_JAW_OPEN_MAX_DEG: float = 22.0

## Standard 52 camelCase ARKit blendshape track subnames matching [FaceRigController].
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

## Six eyelid ARKit blendshape keys mirrored onto [member lash_mesh_path].
const EYELASH_6_KEYS: Array[StringName] = [
	&"eyeBlinkLeft",
	&"eyeBlinkRight",
	&"eyeWideLeft",
	&"eyeWideRight",
	&"eyeSquintLeft",
	&"eyeSquintRight",
]

## Live Link Face index map for the 6 mirrored eyelash blendshapes.
const EYELASH_6_INDICES: Array[int] = [
	ARKitServer.BlendShape.EYE_BLINK_LEFT,
	ARKitServer.BlendShape.EYE_BLINK_RIGHT,
	ARKitServer.BlendShape.EYE_WIDE_LEFT,
	ARKitServer.BlendShape.EYE_WIDE_RIGHT,
	ARKitServer.BlendShape.EYE_SQUINT_LEFT,
	ARKitServer.BlendShape.EYE_SQUINT_RIGHT,
]
## Supported ARKit keys exposed by Humanizer [code]face_animation_tree.tscn[/code].
const HUMANIZER_ARKIT_KEYS: Array[StringName] = [
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
	&"jawRight",
	&"jawLeft",
	&"jawOpen",
	&"mouthFunnel",
	&"mouthPucker",
	&"mouthRight",
	&"mouthLeft",
	&"mouthSmileLeft",
	&"mouthSmileRight",
	&"mouthFrownLeft",
	&"mouthFrownRight",
	&"mouthRollLower",
	&"mouthRollUpper",
	&"mouthShrugUpper",
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
	&"noseSneerLeft",
	&"noseSneerRight",
	&"tongueOut",
]

## Target head [MeshInstance3D] path used when creating 52 [code]TYPE_BLEND_SHAPE[/code] tracks.
var head_mesh_path: String = DEFAULT_HEAD_MESH_PATH
## Target eyelash [MeshInstance3D] path used for 6 eyelid [code]TYPE_BLEND_SHAPE[/code] tracks.
var lash_mesh_path: String = DEFAULT_LASH_MESH_PATH
## Target [Skeleton3D] path used when creating Head, Jaw, LeftEye, and RightEye rotation tracks.
var skeleton_path: String = DEFAULT_SKELETON_PATH
## Target Humanizer [AnimationTree] path relative to character root for Add2 value tracks.
var anim_tree_path: String = ""
## When true and [member anim_tree_path] is set, emits Humanizer [AnimationTree] value tracks.
var record_humanizer_anim_tree: bool = false
## When true, adds [code]TYPE_ROTATION_3D[/code] tracks for Head, Jaw, LeftEye, and RightEye bones.
var record_bones: bool = true
## Maximum downward jaw rotation in degrees applied at [code]jawOpen = 1.0[/code].
var jaw_open_max_deg: float = DEFAULT_JAW_OPEN_MAX_DEG

## Whether the recorder is actively capturing incoming [ARKitPacket] frames.
var _recording: bool = false
## Optional device ID filter; when non-empty, only packets from this subject are recorded.
var _target_device_id: String = ""
## Recorded frame timestamps in seconds relative to recording start.
var _frame_times: PackedFloat32Array = PackedFloat32Array()
## Recorded 61-float blendshape and rotation arrays corresponding to [member _frame_times].
var _frame_weights: Array[PackedFloat32Array] = []
## Reference start timestamp in seconds captured on the first recorded frame.
var _start_time_sec: float = 0.0
## Timecode frame number of the first captured packet.
var _first_packet_frame: int = -1
## Most recent relative frame timestamp in seconds.
var _last_time_sec: float = 0.0
## Supported Humanizer ARKit keys discovered via [method configure_from_controller].
var _humanizer_keys: Array[StringName] = []


## Clears buffers and begins recording frames (optionally filtered to [param device_id]).
func start_recording(device_id: String = "") -> void:
	clear()
	_target_device_id = device_id
	_recording = true


## Stops recording and returns the built Godot 4.7 [Animation] resource.
func stop_recording() -> Animation:
	_recording = false
	return build_animation()


## Returns true while recording is active.
func is_recording() -> bool:
	return _recording


## Returns the number of captured facial frames in the current buffer.
func get_frame_count() -> int:
	return _frame_times.size()


## Returns the total duration in seconds of the currently buffered frames.
func get_recorded_duration() -> float:
	return _last_time_sec


## Clears all buffered frames and resets timing state.
func clear() -> void:
	_recording = false
	_target_device_id = ""
	_frame_times.clear()
	_frame_weights.clear()
	_start_time_sec = 0.0
	_first_packet_frame = -1
	_last_time_sec = 0.0


## Auto-configures track paths for Bella, GhostGirl, or Humanizer from [param ctrl].
func configure_from_controller(ctrl: FaceRigController, root_node: Node = null) -> void:
	if not is_instance_valid(ctrl):
		return

	var rel_root: Node = root_node
	if not is_instance_valid(rel_root):
		rel_root = ctrl.get_parent() if is_instance_valid(ctrl.get_parent()) else ctrl.model_root
	if not is_instance_valid(rel_root):
		return

	jaw_open_max_deg = ctrl.jaw_open_max_deg
	skeleton_path = _compute_relative_path(rel_root, ctrl.get_skeleton())

	if ctrl.get_rig_backend() == FaceRigController.RigBackend.HUMANIZER_ANIM_TREE:
		record_humanizer_anim_tree = true
		anim_tree_path = _compute_relative_path(rel_root, ctrl.get_face_animation_tree())
		head_mesh_path = ""
		lash_mesh_path = ""
		_humanizer_keys.clear()
		for shape_key: StringName in ctrl.get_available_blendshapes():
			if ARKIT_52_KEYS.has(shape_key):
				_humanizer_keys.append(shape_key)
	else:
		record_humanizer_anim_tree = false
		anim_tree_path = ""
		_humanizer_keys.clear()
		head_mesh_path = _compute_relative_path(rel_root, ctrl.get_head_mesh())
		lash_mesh_path = _compute_relative_path(rel_root, ctrl.get_eyelash_mesh())


## Appends a valid [param packet] to the active take at [param timestamp_sec] (or auto-timed).
func record_packet(packet: ARKitPacket, timestamp_sec: float = -1.0) -> void:
	if not _recording or not is_instance_valid(packet) or not packet.is_valid:
		return
	if not _target_device_id.is_empty() and packet.device_id != _target_device_id:
		return

	var rel_time: float = 0.0
	if _frame_times.is_empty():
		_start_time_sec = (
			timestamp_sec if timestamp_sec >= 0.0 else float(Time.get_ticks_usec()) / 1000000.0
		)
		_first_packet_frame = packet.frame
		rel_time = 0.0
	else:
		if timestamp_sec >= 0.0:
			rel_time = maxf(0.0, timestamp_sec - _start_time_sec)
		elif packet.fps > 0 and packet.frame > _first_packet_frame and _first_packet_frame >= 0:
			var fps_denom: float = float(maxi(1, packet.fps)) / float(maxi(1, packet.denominator))
			rel_time = float(packet.frame - _first_packet_frame) / maxf(1.0, fps_denom)
		else:
			var now_sec: float = float(Time.get_ticks_usec()) / 1000000.0
			rel_time = maxf(0.0, now_sec - _start_time_sec)

		if rel_time <= _last_time_sec:
			var step_fallback: float = 1.0 / float(maxi(1, packet.fps))
			rel_time = _last_time_sec + step_fallback

	_last_time_sec = rel_time
	_frame_times.append(rel_time)
	_frame_weights.append(packet.blendshapes_array.duplicate())


## Builds a Godot 4.7 [Animation] with blendshape or Humanizer [AnimationTree] tracks and bones.
func build_animation() -> Animation:
	var anim: Animation = Animation.new()
	var frame_count: int = _frame_times.size()
	anim.length = maxf(_last_time_sec, 0.016667) if frame_count > 0 else 0.0
	anim.step = 1.0 / 60.0

	var use_humanizer_tree: bool = record_humanizer_anim_tree and not anim_tree_path.is_empty()
	var head_tracks: Array[int] = []
	var lash_tracks: Array[int] = []
	var humanizer_tracks: Array[int] = []
	var humanizer_indices: Array[int] = []

	if use_humanizer_tree:
		var target_keys: Array[StringName] = (
			_humanizer_keys if not _humanizer_keys.is_empty() else HUMANIZER_ARKIT_KEYS
		)
		for shape_key: StringName in target_keys:
			var arkit_idx: int = ARKIT_52_KEYS.find(shape_key)
			if arkit_idx < 0:
				continue
			var track_idx: int = anim.add_track(Animation.TYPE_VALUE)
			var track_path: String = (
				anim_tree_path + ":parameters/" + String(shape_key) + "/add_amount"
			)
			anim.track_set_path(track_idx, NodePath(track_path))
			anim.value_track_set_update_mode(track_idx, Animation.UPDATE_CONTINUOUS)
			anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)
			humanizer_tracks.append(track_idx)
			humanizer_indices.append(arkit_idx)
	else:
		for shape_idx: int in range(ARKIT_52_KEYS.size()):
			var shape_key: StringName = ARKIT_52_KEYS[shape_idx]
			var track_idx: int = anim.add_track(Animation.TYPE_BLEND_SHAPE)
			anim.track_set_path(track_idx, NodePath(head_mesh_path + ":" + String(shape_key)))
			anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)
			head_tracks.append(track_idx)

		if not lash_mesh_path.is_empty():
			for lash_idx: int in range(EYELASH_6_KEYS.size()):
				var lash_key: StringName = EYELASH_6_KEYS[lash_idx]
				var track_idx: int = anim.add_track(Animation.TYPE_BLEND_SHAPE)
				anim.track_set_path(track_idx, NodePath(lash_mesh_path + ":" + String(lash_key)))
				anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)
				lash_tracks.append(track_idx)

	var head_rot_track: int = -1
	var jaw_rot_track: int = -1
	var left_eye_rot_track: int = -1
	var right_eye_rot_track: int = -1
	if record_bones and not skeleton_path.is_empty():
		head_rot_track = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(head_rot_track, NodePath(skeleton_path + ":Head"))
		anim.track_set_interpolation_type(head_rot_track, Animation.INTERPOLATION_LINEAR)

		jaw_rot_track = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(jaw_rot_track, NodePath(skeleton_path + ":Jaw"))
		anim.track_set_interpolation_type(jaw_rot_track, Animation.INTERPOLATION_LINEAR)

		left_eye_rot_track = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(left_eye_rot_track, NodePath(skeleton_path + ":LeftEye"))
		anim.track_set_interpolation_type(left_eye_rot_track, Animation.INTERPOLATION_LINEAR)

		right_eye_rot_track = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(right_eye_rot_track, NodePath(skeleton_path + ":RightEye"))
		anim.track_set_interpolation_type(right_eye_rot_track, Animation.INTERPOLATION_LINEAR)

	for f_idx: int in range(frame_count):
		var t: float = _frame_times[f_idx]
		var weights: PackedFloat32Array = _frame_weights[f_idx]
		var w_size: int = weights.size()

		if use_humanizer_tree:
			for h_idx: int in range(humanizer_tracks.size()):
				var src_idx: int = humanizer_indices[h_idx]
				var h_val: float = clampf(weights[src_idx], 0.0, 1.0) if src_idx < w_size else 0.0
				anim.track_insert_key(humanizer_tracks[h_idx], t, h_val)
		else:
			for shape_idx: int in range(ARKIT_52_KEYS.size()):
				var w: float = clampf(weights[shape_idx], 0.0, 1.0) if shape_idx < w_size else 0.0
				anim.blend_shape_track_insert_key(head_tracks[shape_idx], t, w)

			for lash_i: int in range(lash_tracks.size()):
				var src_idx: int = EYELASH_6_INDICES[lash_i]
				var lash_w: float = clampf(weights[src_idx], 0.0, 1.0) if src_idx < w_size else 0.0
				anim.blend_shape_track_insert_key(lash_tracks[lash_i], t, lash_w)

		if head_rot_track >= 0:
			var head_quat: Quaternion = _compute_euler_quat(
				weights,
				ARKitServer.BlendShape.HEAD_YAW,
				ARKitServer.BlendShape.HEAD_PITCH,
				ARKitServer.BlendShape.HEAD_ROLL
			)
			anim.rotation_track_insert_key(head_rot_track, t, head_quat)

		if jaw_rot_track >= 0:
			var jaw_open: float = (
				clampf(weights[ARKitServer.BlendShape.JAW_OPEN], 0.0, 1.0)
				if ARKitServer.BlendShape.JAW_OPEN < w_size
				else 0.0
			)
			var jaw_angle: float = deg_to_rad(jaw_open * jaw_open_max_deg)
			var jaw_quat: Quaternion = Quaternion(Vector3.LEFT, jaw_angle).normalized()
			anim.rotation_track_insert_key(jaw_rot_track, t, jaw_quat)

		if left_eye_rot_track >= 0:
			var left_eye_quat: Quaternion = _compute_euler_quat(
				weights,
				ARKitServer.BlendShape.LEFT_EYE_YAW,
				ARKitServer.BlendShape.LEFT_EYE_PITCH,
				ARKitServer.BlendShape.LEFT_EYE_ROLL
			)
			anim.rotation_track_insert_key(left_eye_rot_track, t, left_eye_quat)

		if right_eye_rot_track >= 0:
			var right_eye_quat: Quaternion = _compute_euler_quat(
				weights,
				ARKitServer.BlendShape.RIGHT_EYE_YAW,
				ARKitServer.BlendShape.RIGHT_EYE_PITCH,
				ARKitServer.BlendShape.RIGHT_EYE_ROLL
			)
			anim.rotation_track_insert_key(right_eye_rot_track, t, right_eye_quat)

	return anim


## Saves [param anim] to [code]<save_dir>/<clip_name>.res[/code] and returns the saved path.
func save_animation(
	anim: Animation, save_dir: String = DEFAULT_SAVE_DIR, clip_name: String = "take_01"
) -> String:
	if not is_instance_valid(anim):
		return ""

	var clean_dir: String = save_dir.strip_edges()
	if clean_dir.is_empty():
		clean_dir = DEFAULT_SAVE_DIR
	if clean_dir.ends_with("/"):
		clean_dir = clean_dir.left(clean_dir.length() - 1)

	var abs_dir: String = ProjectSettings.globalize_path(clean_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		var dir_err: Error = DirAccess.make_dir_recursive_absolute(abs_dir)
		if dir_err != OK:
			push_error("ARKitRecorder failed to create directory: %s" % clean_dir)
			return ""

	var clean_name: String = clip_name.strip_edges()
	if clean_name.ends_with(".res"):
		clean_name = clean_name.left(clean_name.length() - 4)
	elif clean_name.ends_with(".tres"):
		clean_name = clean_name.left(clean_name.length() - 5)
	if clean_name.is_empty():
		clean_name = "take_01"

	anim.resource_name = clean_name
	var full_path: String = clean_dir + "/" + clean_name + ".res"
	var save_err: Error = ResourceSaver.save(anim, full_path)
	if save_err != OK:
		push_error("ARKitRecorder failed to save Animation to %s (err=%d)" % [full_path, save_err])
		return ""
	return full_path


## Converts Live Link Face yaw, pitch, and roll radians from [param weights] to a [Quaternion].
func _compute_euler_quat(
	weights: PackedFloat32Array, yaw_idx: int, pitch_idx: int, roll_idx: int
) -> Quaternion:
	var w_size: int = weights.size()
	var yaw: float = weights[yaw_idx] if yaw_idx < w_size else 0.0
	var pitch: float = weights[pitch_idx] if pitch_idx < w_size else 0.0
	var roll: float = weights[roll_idx] if roll_idx < w_size else 0.0
	return Basis.from_euler(Vector3(-pitch, -yaw, -roll)).get_rotation_quaternion().normalized()


## Computes a relative [NodePath] string from [param from_root] to [param target].
func _compute_relative_path(from_root: Node, target: Node) -> String:
	if not is_instance_valid(from_root) or not is_instance_valid(target):
		return ""
	if from_root == target:
		return "."
	if from_root.is_inside_tree() and target.is_inside_tree():
		return String(from_root.get_path_to(target))
	var parts: Array[String] = []
	var cursor: Node = target
	while is_instance_valid(cursor) and cursor != from_root:
		parts.append(String(cursor.name))
		cursor = cursor.get_parent()
	if cursor != from_root:
		return ""
	parts.reverse()
	return "/".join(parts)
