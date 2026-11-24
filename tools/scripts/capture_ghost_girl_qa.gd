## Automated Vulkan QA screenshot capture for GhostGirl studio preview views.
extends SceneTree

## Path to studio preview scene used for GhostGirl GLB and Humanizer captures.
const PREVIEW_SCENE_PATH: String = "res://scenes/ghost_girl_face_preview.tscn"
## Output directory where all 11 PNG captures are written.
const OUTPUT_DIR: String = "/tmp/ghost_girl_qa"
## Offscreen SubViewport resolution matching project viewport settings.
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 780)
## Studio camera field of view in degrees.
const CAMERA_FOV_DEG: float = 35.0
## Number of render frames to wait after switching camera, mode, or expression.
const SETTLE_FRAMES: int = 3
## Minimum luminance variance required to treat a captured frame as non-blank.
const MIN_LUMA_SPAN: float = 0.015
## Enum integer matching GhostGirlFacePreview.RigDisplayMode.HUMANIZER.
const MODE_HUMANIZER: int = 1


## Defers QA capture execution until autoloads and rendering server finish startup.
func _initialize() -> void:
	call_deferred("_run_capture")


## Instantiates the preview scene, verifies rendering, captures 11 shots, and quits.
func _run_capture() -> void:
	var dir_err: Error = DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	if dir_err != OK:
		printerr("GhostGirlQA: Failed creating output dir ", OUTPUT_DIR, " err=", dir_err)
		quit(1)
		return

	var preview: Node3D = _spawn_preview(root)
	if not is_instance_valid(preview):
		quit(1)
		return

	await _wait_frames(SETTLE_FRAMES + 1)
	var capture_vp: Viewport = root
	var probe_tex: ViewportTexture = capture_vp.get_texture()
	var probe_img: Image = probe_tex.get_image() if is_instance_valid(probe_tex) else null
	if _is_image_blank(probe_img):
		print("GhostGirlQA: Primary viewport returned blank; switching to SubViewport.")
		root.remove_child(preview)
		preview.queue_free()
		await _wait_frames(2)

		var sub_vp: SubViewport = SubViewport.new()
		sub_vp.name = "QACaptureSubViewport"
		sub_vp.size = CAPTURE_SIZE
		sub_vp.own_world_3d = true
		sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(sub_vp)

		preview = _spawn_preview(sub_vp)
		if not is_instance_valid(preview):
			quit(1)
			return
		capture_vp = sub_vp
		await _wait_frames(SETTLE_FRAMES + 1)

	var camera: Camera3D = preview.get_node_or_null(^"Camera3D") as Camera3D
	if not is_instance_valid(camera):
		printerr("GhostGirlQA: Missing Camera3D in preview scene.")
		quit(1)
		return
	camera.fov = CAMERA_FOV_DEG

	await _prepare_neutral_pose(preview)

	var ok: bool = true
	ok = (
		ok
		and await _capture_shot(
			capture_vp,
			camera,
			"01_front_neutral.png",
			Vector3(0.0, 1.45, -0.86),
			Vector3(0.0, 1.44, 0.0),
		)
	)
	ok = (
		ok
		and await _capture_shot(
			capture_vp,
			camera,
			"02_three_quarter.png",
			Vector3(0.49, 1.47, -0.71),
			Vector3(0.0, 1.44, 0.0),
		)
	)
	ok = (
		ok
		and await _capture_shot(
			capture_vp,
			camera,
			"03_side_profile.png",
			Vector3(0.88, 1.45, 0.0),
			Vector3(0.0, 1.44, 0.0),
		)
	)
	ok = (
		ok
		and await _capture_shot(
			capture_vp,
			camera,
			"04_back_view.png",
			Vector3(0.0, 1.46, 0.92),
			Vector3(0.0, 1.41, 0.0),
		)
	)

	_apply_expression(preview, KEY_2, &"happy")
	ok = (
		ok
		and await _capture_shot(
			capture_vp,
			camera,
			"05_happy.png",
			Vector3(0.0, 1.45, -0.84),
			Vector3(0.0, 1.43, 0.0),
		)
	)

	_apply_expression(preview, KEY_3, &"surprised")
	ok = (
		ok
		and await _capture_shot(
			capture_vp,
			camera,
			"06_surprised.png",
			Vector3(0.0, 1.45, -0.84),
			Vector3(0.0, 1.43, 0.0),
		)
	)

	_apply_expression(preview, KEY_4, &"angry")
	ok = (
		ok
		and await _capture_shot(
			capture_vp,
			camera,
			"07_angry.png",
			Vector3(0.0, 1.45, -0.84),
			Vector3(0.0, 1.43, 0.0),
		)
	)

	_apply_expression(preview, KEY_6, &"blink")
	ok = (
		ok
		and await _capture_shot(
			capture_vp,
			camera,
			"08_blink.png",
			Vector3(0.0, 1.45, -0.84),
			Vector3(0.0, 1.43, 0.0),
		)
	)

	_apply_expression(preview, KEY_1, &"neutral")
	ok = (
		ok
		and await _capture_shot(
			capture_vp,
			camera,
			"09_fullbody_front.png",
			Vector3(0.0, 0.92, -3.10),
			Vector3(0.0, 0.82, 0.0),
		)
	)
	ok = (
		ok
		and await _capture_shot(
			capture_vp,
			camera,
			"10_fullbody_side.png",
			Vector3(3.10, 0.92, 0.0),
			Vector3(0.0, 0.82, 0.0),
		)
	)

	var hum_body_var: Variant = preview.call(&"get_humanizer_body")
	var hum_body: Node = hum_body_var as Node if hum_body_var is Node else null
	if not is_instance_valid(hum_body):
		printerr("GhostGirlQA: HumanizerGhostGirl failed to build; cannot capture shot 11.")
		ok = false
	else:
		preview.call(&"_unhandled_input", _make_key_event(KEY_H))
		_apply_expression(preview, KEY_1, &"neutral")
		var mode_var: Variant = preview.call(&"get_display_mode")
		var mode_int: int = mode_var if mode_var is int else -1
		if mode_int != MODE_HUMANIZER:
			preview.call(&"set_display_mode", MODE_HUMANIZER)
		ok = (
			ok
			and await _capture_shot(
				capture_vp,
				camera,
				"11_humanizer_front.png",
				Vector3(0.0, 1.45, -0.86),
				Vector3(0.0, 1.44, 0.0),
			)
		)

	if not ok:
		printerr("GhostGirlQA: One or more captures failed or rendered blank.")
		quit(1)
		return

	print("GhostGirlQA: Successfully saved 11 QA PNGs to ", OUTPUT_DIR)
	quit(0)


## Dynamically loads [constant PREVIEW_SCENE_PATH] after autoloads and attaches under parent.
func _spawn_preview(parent_node: Node) -> Node3D:
	var preview_res: Resource = ResourceLoader.load(PREVIEW_SCENE_PATH)
	if not (preview_res is PackedScene):
		printerr("GhostGirlQA: Failed loading PackedScene ", PREVIEW_SCENE_PATH)
		return null
	var preview_scene: PackedScene = preview_res as PackedScene
	var inst: Node = preview_scene.instantiate()
	if not (inst is Node3D) or not inst.has_method(&"get_ghost_girl"):
		printerr("GhostGirlQA: Preview root missing GhostGirlFacePreview API.")
		if is_instance_valid(inst):
			inst.queue_free()
		return null
	var preview: Node3D = inst as Node3D
	parent_node.add_child(preview)
	return preview


## Disables random blink and dynamic head/eye tracking so turnaround views stay true to pose.
func _prepare_neutral_pose(preview: Node3D) -> void:
	var front_marker: Marker3D = Marker3D.new()
	front_marker.name = "QAFrontLookTarget"
	front_marker.position = Vector3(0.0, 1.44, -3.0)
	preview.add_child(front_marker)

	var ghost_girl_var: Variant = preview.call(&"get_ghost_girl")
	var ghost_girl: Node3D = ghost_girl_var as Node3D if ghost_girl_var is Node3D else null
	if is_instance_valid(ghost_girl):
		ghost_girl.set(&"turn_body_when_behind", false)
		ghost_girl.call(&"set_look_target", front_marker)
		ghost_girl.call(&"set_look_at_enabled", false)

	var glb_rig_var: Variant = preview.call(&"get_glb_face_rig")
	var glb_rig: Node = glb_rig_var as Node if glb_rig_var is Node else null
	if is_instance_valid(glb_rig):
		glb_rig.set(&"auto_blink_enabled", false)
		glb_rig.set(&"look_target", front_marker)
		glb_rig.call(&"set_eye_look_enabled", false)

	var hum_rig_var: Variant = preview.call(&"get_humanizer_face_rig")
	var hum_rig: Node = hum_rig_var as Node if hum_rig_var is Node else null
	if is_instance_valid(hum_rig):
		hum_rig.set(&"auto_blink_enabled", false)
		hum_rig.set(&"look_target", front_marker)
		hum_rig.call(&"set_eye_look_enabled", false)

	_apply_expression(preview, KEY_1, &"neutral")
	await create_timer(0.6).timeout
	await _wait_frames(SETTLE_FRAMES)


## Triggers preview HUD hotkey [param keycode] and snaps [param expr_name] weights immediately.
func _apply_expression(preview: Node3D, keycode: Key, expr_name: StringName) -> void:
	preview.call(&"_unhandled_input", _make_key_event(keycode))
	var glb_rig_var: Variant = preview.call(&"get_glb_face_rig")
	var glb_rig: Node = glb_rig_var as Node if glb_rig_var is Node else null
	if is_instance_valid(glb_rig):
		glb_rig.call(&"set_expression", expr_name, 0.0)
	var hum_rig_var: Variant = preview.call(&"get_humanizer_face_rig")
	var hum_rig: Node = hum_rig_var as Node if hum_rig_var is Node else null
	if is_instance_valid(hum_rig):
		hum_rig.call(&"set_expression", expr_name, 0.0)


## Moves [param camera], waits [constant SETTLE_FRAMES], validates image, and writes PNG.
func _capture_shot(
	vp: Viewport,
	camera: Camera3D,
	file_name: String,
	cam_pos: Vector3,
	look_at_pos: Vector3,
) -> bool:
	camera.position = cam_pos
	camera.look_at(look_at_pos, Vector3.UP)
	await _wait_frames(SETTLE_FRAMES)

	var tex: ViewportTexture = vp.get_texture()
	if not is_instance_valid(tex):
		printerr("GhostGirlQA: Null ViewportTexture for ", file_name)
		return false
	var img: Image = tex.get_image()
	if _is_image_blank(img):
		printerr("GhostGirlQA: Captured blank image for ", file_name)
		return false

	var out_path: String = OUTPUT_DIR.path_join(file_name)
	var save_err: Error = img.save_png(out_path)
	if save_err != OK:
		printerr("GhostGirlQA: Failed saving ", out_path, " err=", save_err)
		return false
	print("GhostGirlQA: Saved ", out_path, " (", img.get_width(), "x", img.get_height(), ")")
	return true


## Waits [param frame_count] rendered frames on the main loop.
func _wait_frames(frame_count: int) -> void:
	for idx: int in range(frame_count):
		await process_frame


## Returns true if [param img] is null, empty, or contains uniform/near-black pixels.
func _is_image_blank(img: Image) -> bool:
	if not is_instance_valid(img) or img.is_empty():
		return true
	var width: int = img.get_width()
	var height: int = img.get_height()
	if width <= 0 or height <= 0:
		return true

	var min_luma: float = 1.0
	var max_luma: float = 0.0
	var step_x: int = maxi(1, width / 16)
	var step_y: int = maxi(1, height / 16)
	for py: int in range(0, height, step_y):
		for px: int in range(0, width, step_x):
			var col: Color = img.get_pixel(px, py)
			var luma: float = col.get_luminance()
			min_luma = minf(min_luma, luma)
			max_luma = maxf(max_luma, luma)

	return max_luma < MIN_LUMA_SPAN or (max_luma - min_luma) < MIN_LUMA_SPAN


## Builds a synthetic pressed [InputEventKey] matching [param keycode].
func _make_key_event(keycode: Key) -> InputEventKey:
	var key_ev: InputEventKey = InputEventKey.new()
	key_ev.keycode = keycode
	key_ev.pressed = true
	key_ev.echo = false
	return key_ev
