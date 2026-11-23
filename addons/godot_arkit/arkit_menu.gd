@tool
## Editor bottom panel UI for Live Link Face UDP streaming, live preview, and facial recording.
extends HBoxContainer

## Autoload singleton node name under [code]/root[/code].
const ARKIT_AUTOLOAD: String = "ARKitSingleton"

## Display labels for all 61 Live Link Face blendshape and head/eye rotation channels.
const BLENDSHAPE_NAMES: Array[String] = [
	"EyeBlinkLeft",
	"EyeLookDownLeft",
	"EyeLookInLeft",
	"EyeLookOutLeft",
	"EyeLookUpLeft",
	"EyeSquintLeft",
	"EyeWideLeft",
	"EyeBlinkRight",
	"EyeLookDownRight",
	"EyeLookInRight",
	"EyeLookOutRight",
	"EyeLookUpRight",
	"EyeSquintRight",
	"EyeWideRight",
	"JawForward",
	"JawRight",
	"JawLeft",
	"JawOpen",
	"MouthClose",
	"MouthFunnel",
	"MouthPucker",
	"MouthRight",
	"MouthLeft",
	"MouthSmileLeft",
	"MouthSmileRight",
	"MouthFrownLeft",
	"MouthFrownRight",
	"MouthDimpleLeft",
	"MouthDimpleRight",
	"MouthStretchLeft",
	"MouthStretchRight",
	"MouthRollLower",
	"MouthRollUpper",
	"MouthShrugLower",
	"MouthShrugUpper",
	"MouthPressLeft",
	"MouthPressRight",
	"MouthLowerDownLeft",
	"MouthLowerDownRight",
	"MouthUpperUpLeft",
	"MouthUpperUpRight",
	"BrowDownLeft",
	"BrowDownRight",
	"BrowInnerUp",
	"BrowOuterUpLeft",
	"BrowOuterUpRight",
	"CheekPuff",
	"CheekSquintLeft",
	"CheekSquintRight",
	"NoseSneerLeft",
	"NoseSneerRight",
	"TongueOut",
	"HeadYaw",
	"HeadPitch",
	"HeadRoll",
	"LeftEyeYaw",
	"LeftEyePitch",
	"LeftEyeRoll",
	"RightEyeYaw",
	"RightEyePitch",
	"RightEyeRoll",
]

## Map of active subject device IDs to their row indices in [member _subjects_list].
var _shown_subjects: Dictionary[String, int] = {}
## Map of subject names to their device IDs.
var _subject_name_to_id: Dictionary[String, String] = {}
## Currently selected subject device ID in the UI.
var _selected_subject_id: String = ""
## Active 60 FPS [ARKitRecorder] instance used to capture and save facial animation clips.
var _recorder: ARKitRecorder = ARKitRecorder.new()
## Explicit or discovered [FaceRigController] target for live blendshape preview.
var _preview_controller: FaceRigController = null
## Path of the most recently saved [Animation] `.res` file.
var _last_saved_path: String = ""

@onready var _subject_infos: VBoxContainer = %SubjectInfos
@onready var _device_id_value: Label = %DeviceIDValue
@onready var _subject_name_value: Label = %SubjectNameValue
@onready var _frame_value: Label = %FrameValue
@onready var _sub_frame_value: Label = %SubFrameValue
@onready var _fps_value: Label = %FPSValue
@onready var _denominator_value: Label = %DenominatorValue
@onready var _blendshapes_menu: VBoxContainer = %BlendshapesMenu
@onready var _blendshape_container: VFlowContainer = %BlendshapeContainer
@onready var _blendshape_info: HBoxContainer = %BlendshapeInfo
@onready var _error_display: Label = %ErrorDisplay
@onready var _subjects_list: ItemList = %SubjectsList
@onready var _start_server: CheckBox = $VBoxContainer/ServerMenu/StartServer
@onready var _live_preview_check: CheckBox = %LivePreviewCheck
@onready var _record_bones_check: CheckBox = %RecordBonesCheck
@onready var _clip_name_edit: LineEdit = %ClipNameEdit
@onready var _save_path_edit: LineEdit = %SavePathEdit
@onready var _record_button: Button = %RecordButton
@onready var _recording_status_label: Label = %RecordingStatusLabel


## Initializes subject lists, connects [code]ARKitSingleton[/code] signals, and builds meters.
func _ready() -> void:
	_subjects_list.clear()
	_hide_subject()

	var autoload: Node = _get_autoload()
	if is_instance_valid(autoload):
		if autoload.has_signal("show_error"):
			autoload.connect("show_error", _on_error_shown)
		if autoload.has_signal("add_subject"):
			autoload.connect("add_subject", _on_add_subject)
		if autoload.has_signal("remove_subject"):
			autoload.connect("remove_subject", _on_remove_subject)
		if autoload.has_signal("frame_received"):
			autoload.connect("frame_received", _on_frame_received)

	for idx: int in range(BLENDSHAPE_NAMES.size()):
		var dup_node: Node = _blendshape_info.duplicate()
		if dup_node is HBoxContainer:
			var row: HBoxContainer = dup_node as HBoxContainer
			var label_node: Label = row.get_child(1) as Label
			if is_instance_valid(label_node):
				label_node.text = BLENDSHAPE_NAMES[idx]
			_blendshape_container.add_child(row)
			row.show()


## Disconnects [code]ARKitSingleton[/code] signals when leaving the scene tree.
func _exit_tree() -> void:
	var autoload: Node = _get_autoload()
	if is_instance_valid(autoload):
		if (
			autoload.has_signal("show_error")
			and autoload.is_connected("show_error", _on_error_shown)
		):
			autoload.disconnect("show_error", _on_error_shown)
		if (
			autoload.has_signal("add_subject")
			and autoload.is_connected("add_subject", _on_add_subject)
		):
			autoload.disconnect("add_subject", _on_add_subject)
		if (
			autoload.has_signal("remove_subject")
			and autoload.is_connected("remove_subject", _on_remove_subject)
		):
			autoload.disconnect("remove_subject", _on_remove_subject)
		if (
			autoload.has_signal("frame_received")
			and autoload.is_connected("frame_received", _on_frame_received)
		):
			autoload.disconnect("frame_received", _on_frame_received)


## Updates the blendshape progress bars for the currently selected subject.
func _process(_delta: float) -> void:
	if _selected_subject_id.is_empty():
		return

	var autoload: Node = _get_autoload()
	if not is_instance_valid(autoload) or not autoload.has_method("has_subject"):
		return
	var has_subj_raw: Variant = autoload.call("has_subject", _selected_subject_id)
	var has_subj: bool = has_subj_raw if has_subj_raw is bool else false
	if not has_subj:
		return

	var subj_raw: Variant = autoload.call("get_subject", _selected_subject_id)
	var subject: ARKitSubject = subj_raw as ARKitSubject if subj_raw is ARKitSubject else null
	if is_instance_valid(subject) and is_instance_valid(subject.packet):
		_set_subject_infos(subject)
		var packet: ARKitPacket = subject.packet
		var bar_count: int = mini(
			packet.number_of_blendshapes, _blendshape_container.get_child_count()
		)
		for idx: int in range(bar_count):
			var blendshape_value: float = packet.blendshapes_array[idx]
			var row_node: Node = _blendshape_container.get_child(idx)
			if row_node.get_child_count() > 0:
				var bar: ProgressBar = row_node.get_child(0) as ProgressBar
				if is_instance_valid(bar):
					bar.value = blendshape_value


## Explicitly assigns the [FaceRigController] used for live blendshape preview.
func set_preview_controller(controller: FaceRigController) -> void:
	_preview_controller = controller


## Returns the active [ARKitRecorder] instance owned by this menu.
func get_recorder() -> ARKitRecorder:
	return _recorder


## Returns the resource path of the last saved facial animation clip.
func get_last_saved_path() -> String:
	return _last_saved_path


## Handles an incoming [param subject] and [param packet] for live preview and recording.
func _on_frame_received(_subject: ARKitSubject, packet: ARKitPacket) -> void:
	if not is_instance_valid(packet) or not packet.is_valid:
		return
	if not _selected_subject_id.is_empty() and packet.device_id != _selected_subject_id:
		return

	if is_instance_valid(_live_preview_check) and _live_preview_check.button_pressed:
		var ctrl: FaceRigController = _resolve_face_rig_controller()
		if is_instance_valid(ctrl):
			ctrl.apply_arkit_weights(packet.blendshapes_array)

	if _recorder.is_recording():
		_recorder.record_bones = (
			_record_bones_check.button_pressed if is_instance_valid(_record_bones_check) else true
		)
		_recorder.record_packet(packet)
		if is_instance_valid(_recording_status_label):
			_recording_status_label.text = (
				"Recording: %d frames (%.2fs)"
				% [_recorder.get_frame_count(), _recorder.get_recorded_duration()]
			)


## Starts or stops facial animation recording and saves the `.res` clip on stop.
func _on_record_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		var ctrl: FaceRigController = _resolve_face_rig_controller()
		if is_instance_valid(ctrl):
			var head_mesh: MeshInstance3D = ctrl.get_head_mesh()
			var is_default_bella: bool = (
				ctrl.get_rig_backend() == FaceRigController.RigBackend.BLENDSHAPE
				and is_instance_valid(head_mesh)
				and String(head_mesh.name) == "Bella_Head"
			)
			if (
				not is_default_bella
				or _recorder.record_humanizer_anim_tree
				or _recorder.head_mesh_path != ARKitRecorder.DEFAULT_HEAD_MESH_PATH
			):
				_recorder.configure_from_controller(ctrl)
		_recorder.record_bones = (
			_record_bones_check.button_pressed if is_instance_valid(_record_bones_check) else true
		)
		_recorder.start_recording(_selected_subject_id)
		if is_instance_valid(_record_button):
			_record_button.text = "Stop & Save"
		if is_instance_valid(_recording_status_label):
			_recording_status_label.text = "Recording: 0 frames (0.00s)"
	else:
		var anim: Animation = _recorder.stop_recording()
		if is_instance_valid(_record_button):
			_record_button.text = "Record"
		var save_dir: String = (
			_save_path_edit.text
			if is_instance_valid(_save_path_edit)
			else ARKitRecorder.DEFAULT_SAVE_DIR
		)
		var clip_name: String = (
			_clip_name_edit.text if is_instance_valid(_clip_name_edit) else "take_01"
		)
		_last_saved_path = _recorder.save_animation(anim, save_dir, clip_name)
		if is_instance_valid(_recording_status_label):
			if not _last_saved_path.is_empty():
				_recording_status_label.text = (
					"Saved %d frames -> %s" % [_recorder.get_frame_count(), _last_saved_path]
				)
			else:
				_recording_status_label.text = "Failed to save animation"


## Starts or stops the UDP server via [code]ARKitSingleton[/code].
func _on_start_server_toggled(toggled_on: bool) -> void:
	var autoload: Node = _get_autoload()
	if toggled_on:
		if is_instance_valid(autoload) and autoload.has_signal("start_server"):
			autoload.emit_signal("start_server")
	else:
		if is_instance_valid(autoload) and autoload.has_signal("stop_server"):
			autoload.emit_signal("stop_server")
		_shown_subjects.clear()
		_subject_name_to_id.clear()
		_subjects_list.clear()
		_selected_subject_id = ""
		_hide_subject()
		_error_display.text = ""


## Validates and applies a new UDP listener port from [param new_text].
func _on_server_port_text_submitted(new_text: String) -> void:
	if new_text.is_valid_int():
		var port_num: int = new_text.to_int()
		if port_num >= 65535:
			_error_display.text = "Max port is 65534"
			return
		if port_num <= 1023:
			_error_display.text = "Min port is 1024"
			return
		_hide_subject()
		_start_server.button_pressed = false
		var autoload: Node = _get_autoload()
		if is_instance_valid(autoload) and autoload.has_signal("change_port"):
			autoload.emit_signal("change_port", port_num)
	else:
		_error_display.text = "Enter a valid port number"


## Displays [param error] in the error label.
func _on_error_shown(error: String) -> void:
	_error_display.text = error


## Adds a newly discovered [param subject] to [member _subjects_list] and selects it.
func _on_add_subject(subject: ARKitSubject) -> void:
	var item_idx: int = _subjects_list.add_item(subject.subject_name)
	_shown_subjects[subject.device_id] = item_idx
	_subject_name_to_id[subject.subject_name] = subject.device_id

	_subjects_list.select(item_idx)
	_show_subject()
	_selected_subject_id = subject.device_id


## Removes [param subject] from [member _subjects_list] and updates selection state.
func _on_remove_subject(subject: ARKitSubject) -> void:
	if _shown_subjects.has(subject.device_id):
		var removed_idx: int = _shown_subjects[subject.device_id]
		_subjects_list.remove_item(removed_idx)
		_shown_subjects.erase(subject.device_id)
		_subject_name_to_id.erase(subject.subject_name)

		for device_id: String in _shown_subjects.keys():
			if _shown_subjects[device_id] > removed_idx:
				_shown_subjects[device_id] -= 1

		if _subjects_list.item_count == 0:
			_selected_subject_id = ""
			_hide_subject()
		else:
			_subjects_list.select(0)
			var remaining_keys: Array[String] = _shown_subjects.keys()
			_selected_subject_id = remaining_keys[0]


## Hides the subject metadata and blendshape meter containers.
func _hide_subject() -> void:
	_subject_infos.hide()
	_blendshapes_menu.hide()


## Shows the subject metadata and blendshape meter containers.
func _show_subject() -> void:
	_subject_infos.show()
	_blendshapes_menu.show()


## Populates the subject metadata labels from [param subject].
func _set_subject_infos(subject: ARKitSubject) -> void:
	_device_id_value.text = str(subject.device_id)
	_subject_name_value.text = str(subject.subject_name)
	_frame_value.text = str(subject.packet.frame)
	_sub_frame_value.text = str(subject.packet.subframe)
	_fps_value.text = str(subject.packet.fps)
	_denominator_value.text = str(subject.packet.denominator)


## Selects the subject matching [param index] in [member _subjects_list].
func _on_subjects_list_item_selected(index: int) -> void:
	for device_id: String in _shown_subjects.keys():
		if _shown_subjects[device_id] == index:
			_selected_subject_id = device_id
			_show_subject()
			return


## Looks up the [code]ARKitSingleton[/code] autoload node on the active [SceneTree] root.
func _get_autoload() -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.root):
		return null
	return tree.root.get_node_or_null(NodePath(ARKIT_AUTOLOAD))


## Resolves the active [FaceRigController] from explicit assignment, edited scene, or active tree.
func _resolve_face_rig_controller() -> FaceRigController:
	if is_instance_valid(_preview_controller):
		return _preview_controller

	if Engine.is_editor_hint():
		var edited_root: Node = EditorInterface.get_edited_scene_root()
		var found_in_editor: FaceRigController = _find_face_rig_in_subtree(edited_root)
		if is_instance_valid(found_in_editor):
			_preview_controller = found_in_editor
			return _preview_controller

	if is_inside_tree():
		var tree: SceneTree = get_tree()
		if is_instance_valid(tree):
			var found_in_current: FaceRigController = _find_face_rig_in_subtree(tree.current_scene)
			if is_instance_valid(found_in_current):
				_preview_controller = found_in_current
				return _preview_controller
			var found_in_root: FaceRigController = _find_face_rig_in_subtree(tree.root)
			if is_instance_valid(found_in_root):
				_preview_controller = found_in_root
				return _preview_controller
	return null


## Searches [param root_node] and its descendants for a [FaceRigController] instance.
func _find_face_rig_in_subtree(root_node: Node) -> FaceRigController:
	if not is_instance_valid(root_node):
		return null
	if root_node is FaceRigController:
		return root_node as FaceRigController
	var named_child: Node = root_node.find_child("FaceRigController", true, false)
	if named_child is FaceRigController:
		return named_child as FaceRigController
	for child: Node in root_node.find_children("*", "FaceRigController", true, false):
		if child is FaceRigController:
			return child as FaceRigController
	return null
