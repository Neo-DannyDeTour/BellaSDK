## GUT unit tests for [ARKitPacket], [ARKitServer] multi-packet UDP, and [ARKitRecorder].
extends GutTest

## Preloaded GodotARKit bottom panel scene under test.
const ARKIT_MENU_SCENE: PackedScene = preload("res://addons/godot_arkit/arkit_menu.tscn")
## Temporary test output path for saved facial animation clips.
const TEST_SAVE_DIR: String = "user://test_arkit_facial_clips"


## Removes any temporary `.res` test clips created inside [constant TEST_SAVE_DIR].
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


## Builds a 61-float array with customizable blink, jawOpen, smile, and head yaw values.
func _make_weights(
	blink_l: float, jaw_open: float, smile_l: float, head_yaw: float = 0.0
) -> PackedFloat32Array:
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(61)
	weights.fill(0.0)
	weights[ARKitServer.BlendShape.EYE_BLINK_LEFT] = blink_l
	weights[ARKitServer.BlendShape.EYE_WIDE_RIGHT] = 0.35
	weights[ARKitServer.BlendShape.JAW_OPEN] = jaw_open
	weights[ARKitServer.BlendShape.MOUTH_SMILE_LEFT] = smile_l
	weights[ARKitServer.BlendShape.HEAD_YAW] = head_yaw
	weights[ARKitServer.BlendShape.HEAD_PITCH] = 0.12
	weights[ARKitServer.BlendShape.LEFT_EYE_YAW] = -0.08
	weights[ARKitServer.BlendShape.RIGHT_EYE_YAW] = -0.08
	return weights


## Builds an in-memory character rig with 52 head shapes, 6 lash shapes, and [FaceRigController].
func _create_mock_bella_rig() -> Node3D:
	var actor_root: Node3D = Node3D.new()
	actor_root.name = "MockBella"

	var model_root: Node3D = Node3D.new()
	model_root.name = "BellaModel"
	actor_root.add_child(model_root)

	var armature: Node3D = Node3D.new()
	armature.name = "Bella_Armature"
	model_root.add_child(armature)

	var skel: Skeleton3D = Skeleton3D.new()
	skel.name = "Skeleton3D"
	for bone_name: String in ["Root", "Head", "Jaw", "LeftEye", "RightEye"]:
		var b_idx: int = skel.add_bone(bone_name)
		skel.set_bone_rest(b_idx, Transform3D.IDENTITY)
	armature.add_child(skel)

	var head_mesh_inst: MeshInstance3D = MeshInstance3D.new()
	head_mesh_inst.name = "Bella_Head"
	var head_array_mesh: ArrayMesh = ArrayMesh.new()
	for shape_key: StringName in FaceRigController.ARKIT_52_KEYS:
		head_array_mesh.add_blend_shape(shape_key)
	var head_arrays: Array = []
	head_arrays.resize(Mesh.ARRAY_MAX)
	head_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var head_blend_arrays: Array[Array] = []
	for _idx: int in range(FaceRigController.ARKIT_52_KEYS.size()):
		head_blend_arrays.append(head_arrays)
	head_array_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, head_arrays, head_blend_arrays
	)
	head_mesh_inst.mesh = head_array_mesh
	skel.add_child(head_mesh_inst)

	var lash_mesh_inst: MeshInstance3D = MeshInstance3D.new()
	lash_mesh_inst.name = "Bella_Eyelashes"
	var lash_array_mesh: ArrayMesh = ArrayMesh.new()
	var lash_blend_arrays: Array[Array] = []
	for lash_key: StringName in ARKitRecorder.EYELASH_6_KEYS:
		lash_array_mesh.add_blend_shape(lash_key)
		lash_blend_arrays.append(head_arrays)
	lash_array_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, head_arrays, lash_blend_arrays
	)
	lash_mesh_inst.mesh = lash_array_mesh
	skel.add_child(lash_mesh_inst)

	var face_ctrl: FaceRigController = FaceRigController.new()
	face_ctrl.name = "FaceRigController"
	face_ctrl.model_root = model_root
	actor_root.add_child(face_ctrl)

	return actor_root


## Verifies [ARKitPacket] safely rejects malformed payloads and decodes valid v6 frames.
func test_arkit_packet_validation_and_binary_parsing() -> void:
	var empty_pkt: ARKitPacket = ARKitPacket.new(PackedByteArray())
	assert_false(empty_pkt.is_valid, "Empty byte payload must mark ARKitPacket invalid.")

	var bad_magic: PackedByteArray = PackedByteArray()
	bad_magic.resize(40)
	bad_magic.fill(0)
	bad_magic[0] = 99
	var invalid_magic_pkt: ARKitPacket = ARKitPacket.new(bad_magic)
	assert_false(invalid_magic_pkt.is_valid, "Wrong magic version byte must be rejected.")

	var weights: PackedFloat32Array = _make_weights(0.65, 0.42, 0.88, 0.25)
	var raw_bytes: PackedByteArray = ARKitPacket.build_packet_bytes(
		"DEV-UUID-001", "BellaLive", 120, 60, weights
	)
	var truncated: PackedByteArray = raw_bytes.slice(0, raw_bytes.size() - 8)
	var truncated_pkt: ARKitPacket = ARKitPacket.new(truncated)
	assert_false(truncated_pkt.is_valid, "Truncated float buffer must be rejected safely.")

	var valid_pkt: ARKitPacket = ARKitPacket.new(raw_bytes)
	assert_true(valid_pkt.is_valid, "Valid Live Link Face v6 packet must parse cleanly.")
	assert_eq(valid_pkt.device_id, "DEV-UUID-001")
	assert_eq(valid_pkt.subject_name, "BellaLive")
	assert_eq(valid_pkt.frame, 120)
	assert_eq(valid_pkt.fps, 60)
	assert_eq(valid_pkt.number_of_blendshapes, 61)
	assert_almost_eq(
		valid_pkt.blendshapes_array[ARKitServer.BlendShape.EYE_BLINK_LEFT], 0.65, 0.001
	)
	assert_almost_eq(valid_pkt.blendshapes_array[ARKitServer.BlendShape.JAW_OPEN], 0.42, 0.001)
	assert_almost_eq(
		valid_pkt.blendshapes_array[ARKitServer.BlendShape.MOUTH_SMILE_LEFT], 0.88, 0.001
	)


## Verifies [ARKitServer] keeps accepted [PacketPeerUDP] connections alive across multiple packets.
func test_arkit_server_multi_packet_persistent_udp_stream() -> void:
	var test_port: int = 23457
	var server: ARKitServer = ARKitServer.new(test_port)
	var start_err: Error = server.start()
	if start_err != OK:
		test_port = 23458
		server.change_port(test_port)
		start_err = server.start()
	assert_eq(start_err, OK, "ARKitServer must bind to local test UDP port.")

	var received_frames: Array[ARKitPacket] = []
	server.frame_received.connect(
		func(_subj: ARKitSubject, pkt: ARKitPacket) -> void: received_frames.append(pkt)
	)

	var client: PacketPeerUDP = PacketPeerUDP.new()
	var conn_err: Error = client.connect_to_host("127.0.0.1", test_port)
	assert_eq(conn_err, OK, "PacketPeerUDP client must connect to local ARKitServer.")

	for frame_idx: int in range(3):
		var w: PackedFloat32Array = _make_weights(
			0.1 * float(frame_idx + 1), 0.2 * float(frame_idx + 1), 0.3 * float(frame_idx + 1)
		)
		var payload: PackedByteArray = ARKitPacket.build_packet_bytes(
			"UDP-PEER-1", "BellaStream", 100 + frame_idx, 60, w
		)
		var put_err: Error = client.put_packet(payload)
		assert_eq(put_err, OK, "Client put_packet must succeed for packet %d." % frame_idx)
		OS.delay_msec(5)
		server.poll()

	client.close()
	server.stop()

	assert_eq(
		received_frames.size(),
		3,
		"ARKitServer must receive all 3 sequential packets from the same PacketPeerUDP client.",
	)
	if received_frames.size() == 3:
		assert_eq(received_frames[0].frame, 100)
		assert_eq(received_frames[1].frame, 101)
		assert_eq(received_frames[2].frame, 102)
		assert_almost_eq(
			received_frames[2].blendshapes_array[ARKitServer.BlendShape.JAW_OPEN], 0.6, 0.001
		)


## Verifies [ARKitRecorder] builds 52 head + 6 lash + 4 bone tracks and saves a valid `.res` clip.
func test_arkit_recorder_builds_and_saves_animation_tracks() -> void:
	var recorder: ARKitRecorder = ARKitRecorder.new()
	recorder.record_bones = true
	recorder.start_recording("REC-DEV-1")
	assert_true(recorder.is_recording(), "Recorder must be active after start_recording().")

	for frame_idx: int in range(4):
		var alpha: float = float(frame_idx) / 3.0
		var w: PackedFloat32Array = _make_weights(alpha, alpha * 0.5, alpha * 0.8, 0.2 * alpha)
		var raw: PackedByteArray = ARKitPacket.build_packet_bytes(
			"REC-DEV-1", "BellaTake", frame_idx, 60, w
		)
		var pkt: ARKitPacket = ARKitPacket.new(raw)
		recorder.record_packet(pkt, float(frame_idx) / 60.0)

	assert_eq(recorder.get_frame_count(), 4, "Recorder must capture 4 timestamped frames.")
	var anim: Animation = recorder.stop_recording()
	assert_false(recorder.is_recording(), "Recorder must stop after stop_recording().")
	assert_not_null(anim, "stop_recording() must return a valid Animation resource.")

	# 52 head blendshape tracks + 6 eyelash blendshape tracks + 4 bone rotation tracks = 62 tracks
	assert_eq(anim.get_track_count(), 62, "Animation must contain 52 + 6 + 4 = 62 tracks.")

	var blink_track: int = (
		anim
		. find_track(
			NodePath(ARKitRecorder.DEFAULT_HEAD_MESH_PATH + ":eyeBlinkLeft"),
			Animation.TYPE_BLEND_SHAPE,
		)
	)
	assert_gte(blink_track, 0, "Animation must contain Bella_Head:eyeBlinkLeft track.")
	assert_eq(anim.track_get_key_count(blink_track), 4)
	assert_almost_eq(float(anim.track_get_key_value(blink_track, 3)), 1.0, 0.001)

	var lash_wide_track: int = (
		anim
		. find_track(
			NodePath(ARKitRecorder.DEFAULT_LASH_MESH_PATH + ":eyeWideRight"),
			Animation.TYPE_BLEND_SHAPE,
		)
	)
	assert_gte(lash_wide_track, 0, "Animation must contain mirrored Bella_Eyelashes:eyeWideRight.")
	assert_almost_eq(float(anim.track_get_key_value(lash_wide_track, 0)), 0.35, 0.001)

	for bone_subname: String in [":Head", ":Jaw", ":LeftEye", ":RightEye"]:
		var bone_track: int = (
			anim
			. find_track(
				NodePath(ARKitRecorder.DEFAULT_SKELETON_PATH + bone_subname),
				Animation.TYPE_ROTATION_3D,
			)
		)
		assert_gte(bone_track, 0, "Animation missing bone rotation track " + bone_subname)
		assert_eq(anim.track_get_key_count(bone_track), 4)

	var saved_path: String = recorder.save_animation(anim, TEST_SAVE_DIR, "unit_test_clip")
	assert_eq(saved_path, TEST_SAVE_DIR + "/unit_test_clip.res")
	assert_true(FileAccess.file_exists(saved_path), "Saved .res file must exist on disk.")

	var loaded_res: Resource = ResourceLoader.load(saved_path)
	assert_true(loaded_res is Animation, "Saved .res clip must load back as an Animation.")


## Verifies live [FaceRigController] preview and UI recording button inside `arkit_menu.tscn`.
func test_live_preview_and_menu_recording_workflow() -> void:
	var rig: Node3D = _create_mock_bella_rig()
	add_child_autofree(rig)
	var face_ctrl: FaceRigController = rig.get_node(^"FaceRigController") as FaceRigController
	assert_not_null(face_ctrl, "Mock rig must provide FaceRigController.")

	var menu_inst: Node = ARKIT_MENU_SCENE.instantiate()
	assert_true(menu_inst is HBoxContainer, "arkit_menu.tscn root must instantiate cleanly.")
	var menu: HBoxContainer = menu_inst as HBoxContainer
	add_child_autofree(menu)
	menu.call("set_preview_controller", face_ctrl)

	var save_path_edit: LineEdit = menu.get_node(^"%SavePathEdit") as LineEdit
	var clip_name_edit: LineEdit = menu.get_node(^"%ClipNameEdit") as LineEdit
	var record_btn: Button = menu.get_node(^"%RecordButton") as Button
	assert_not_null(save_path_edit)
	assert_not_null(clip_name_edit)
	assert_not_null(record_btn)

	save_path_edit.text = TEST_SAVE_DIR
	clip_name_edit.text = "menu_take_01"

	record_btn.button_pressed = true
	var w1: PackedFloat32Array = _make_weights(0.55, 0.45, 0.70, 0.15)
	var pkt1: ARKitPacket = ARKitPacket.new(
		ARKitPacket.build_packet_bytes("MENU-DEV", "BellaMenu", 1, 60, w1)
	)
	var subj: ARKitSubject = ARKitSubject.new(pkt1)
	menu.call("_on_frame_received", subj, pkt1)

	assert_almost_eq(
		face_ctrl.get_blendshape_weight(&"eyeBlinkLeft"),
		0.55,
		0.005,
		"Live preview must apply incoming ARKit eyeBlinkLeft weight to FaceRigController.",
	)
	assert_almost_eq(
		face_ctrl.get_blendshape_weight(&"jawOpen"),
		0.45,
		0.005,
		"Live preview must apply incoming ARKit jawOpen weight to FaceRigController.",
	)

	record_btn.button_pressed = false
	var last_saved: Variant = menu.call("get_last_saved_path")
	var saved_str: String = last_saved if last_saved is String else ""
	assert_eq(saved_str, TEST_SAVE_DIR + "/menu_take_01.res")
	assert_true(FileAccess.file_exists(saved_str), "Menu Stop & Save must write .res file.")
