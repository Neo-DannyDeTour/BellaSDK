## Base 3D test cell for Factorio-style visual mechanic verification.
class_name MechanicTestCell
extends Node3D

## Emitted when the cell finishes running with pass/fail status and optional screenshot path.
signal cell_completed(cell_name: String, passed: bool, reason: String, screenshot_path: String)

## Execution state of a [MechanicTestCell].
enum CellState {
	IDLE,
	RUNNING,
	PASSED,
	FAILED,
}

## Width and depth of each isolated test pad in meters.
const PAD_SIZE: float = 12.0

## Thickness of the test pad floor slab in meters.
const PAD_THICKNESS: float = 0.4

## Default directory where failure screenshots are saved.
const FAILURE_DIR: String = "user://test_reports/failures"

## Shared indicator material for running state.
static var _mat_running: StandardMaterial3D = null

## Shared indicator material for passing state.
static var _mat_pass: StandardMaterial3D = null

## Shared indicator material for failing state.
static var _mat_fail: StandardMaterial3D = null

## Shared floor material for test pads.
static var _mat_floor: StandardMaterial3D = null

## Human-readable test title displayed on the floating 3D status banner.
@export var cell_title: String = "Mechanic Cell"

## Maximum seconds allowed before the cell times out and fails.
@export var timeout_seconds: float = 8.0

## Current execution state of this cell.
var state: CellState = CellState.IDLE

## Failure reason recorded when [member state] is [enum CellState.FAILED].
var failure_reason: String = ""

## File path to the captured failure PNG, or empty if passed.
var failure_screenshot_path: String = ""

## Floating 3D text banner displaying test title, state, and failure reason.
var _status_label: Label3D = null

## Colored 3D status bar mesh beneath [member _status_label].
var _status_bar: MeshInstance3D = null

## Dedicated [Camera3D] aimed at the center of this test cell.
var _cell_camera: Camera3D = null

## Guard flag ensuring [signal cell_completed] is emitted at most once per run.
var _has_failed: bool = false


## Builds shared pad geometry, collision, camera, and status banner if not present.
func _ready() -> void:
	_ensure_shared_materials()
	_build_pad_if_needed()
	_set_visual_state(CellState.IDLE, "READY")


## Executes the full cell lifecycle: setup, scripted steps, verification, and teardown.
func start_test() -> void:
	_has_failed = false
	failure_reason = ""
	failure_screenshot_path = ""
	_set_visual_state(CellState.RUNNING, "RUNNING...")

	await _setup_cell()
	if not _has_failed:
		await _run_test()

	if not _has_failed:
		_set_visual_state(CellState.PASSED, "PASS")
		cell_completed.emit(cell_title, true, "", "")

	await _teardown_cell()


## Returns the dedicated [Camera3D] for snapping the overview camera to this cell.
func get_cell_camera() -> Camera3D:
	return _cell_camera


## Asserts [param condition] is true; fails the cell with [param message] otherwise.
func assert_true(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail_cell(message)
	return false


## Asserts [param actual] equals [param expected]; fails the cell otherwise.
func assert_eq(actual: Variant, expected: Variant, message: String) -> bool:
	if actual == expected:
		return true
	_fail_cell("%s (got=%s, expected=%s)" % [message, str(actual), str(expected)])
	return false


## Asserts [param actual] is within [param tolerance] of [param expected].
func assert_near(actual: float, expected: float, tolerance: float, message: String) -> bool:
	if absf(actual - expected) <= tolerance:
		return true
	_fail_cell("%s (got=%.3f, expected=%.3f)" % [message, actual, expected])
	return false


## Polls [param predicate] until it returns true or [param max_wait_sec] elapses.
func wait_until(predicate: Callable, max_wait_sec: float = 3.0, step_sec: float = 0.05) -> bool:
	var elapsed: float = 0.0
	while elapsed < max_wait_sec:
		if _has_failed:
			return false
		var res: Variant = predicate.call()
		var ok: bool = res if res is bool else false
		if ok:
			return true
		await get_tree().create_timer(step_sec).timeout
		elapsed += step_sec
	return false


## Awaits [param frame_count] process frames inside the scene tree.
func wait_frames(frame_count: int = 2) -> void:
	for idx: int in range(frame_count):
		if not is_inside_tree():
			return
		await get_tree().process_frame


## Virtual setup hook overridden by concrete mechanic test cells.
func _setup_cell() -> void:
	await wait_frames(1)


## Virtual test execution hook overridden by concrete mechanic test cells.
func _run_test() -> void:
	await wait_frames(1)


## Virtual teardown hook overridden by concrete mechanic test cells.
func _teardown_cell() -> void:
	await wait_frames(1)


## Marks the cell as failed, captures a failure screenshot, and emits completion.
func _fail_cell(reason: String) -> void:
	if _has_failed:
		return
	_has_failed = true
	failure_reason = reason
	_set_visual_state(CellState.FAILED, "FAIL: " + reason)
	failure_screenshot_path = await _capture_failure_screenshot()
	print("MechanicTestCell [FAIL] %s -> %s" % [cell_title, reason])
	cell_completed.emit(cell_title, false, reason, failure_screenshot_path)


## Captures a PNG snapshot from [member _cell_camera] when a failure occurs.
func _capture_failure_screenshot() -> String:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return ""
	DirAccess.make_dir_recursive_absolute(FAILURE_DIR)
	var safe_name: String = cell_title.to_lower().replace(" ", "_").replace("/", "_")
	var out_path: String = FAILURE_DIR.path_join(safe_name + ".png")

	var vp: Viewport = get_viewport()
	if not is_instance_valid(vp):
		return ""
	var prev_cam: Camera3D = vp.get_camera_3d()
	if is_instance_valid(_cell_camera):
		_cell_camera.current = true
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	if is_instance_valid(prev_cam):
		prev_cam.current = true
	if is_instance_valid(img):
		img.save_png(out_path)
		return out_path
	return ""


## Updates the 3D banner text, color, and status bar material.
func _set_visual_state(new_state: CellState, detail: String) -> void:
	state = new_state
	if is_instance_valid(_status_label):
		_status_label.text = "%s\n[%s]" % [cell_title, detail]
		if new_state == CellState.PASSED:
			_status_label.modulate = Color(0.3, 1.0, 0.4, 1.0)
		elif new_state == CellState.FAILED:
			_status_label.modulate = Color(1.0, 0.3, 0.3, 1.0)
		elif new_state == CellState.RUNNING:
			_status_label.modulate = Color(1.0, 0.9, 0.3, 1.0)
		else:
			_status_label.modulate = Color(0.8, 0.8, 0.8, 1.0)

	if is_instance_valid(_status_bar):
		if new_state == CellState.PASSED:
			_status_bar.material_override = _mat_pass
		elif new_state == CellState.FAILED:
			_status_bar.material_override = _mat_fail
		else:
			_status_bar.material_override = _mat_running


## Initializes shared static materials once to prevent runtime material duplication.
func _ensure_shared_materials() -> void:
	if _mat_running == null:
		_mat_running = StandardMaterial3D.new()
		_mat_running.albedo_color = Color(1.0, 0.85, 0.2, 1.0)
		_mat_running.emission_enabled = true
		_mat_running.emission = Color(1.0, 0.85, 0.2, 1.0)

	if _mat_pass == null:
		_mat_pass = StandardMaterial3D.new()
		_mat_pass.albedo_color = Color(0.2, 0.95, 0.35, 1.0)
		_mat_pass.emission_enabled = true
		_mat_pass.emission = Color(0.2, 0.95, 0.35, 1.0)

	if _mat_fail == null:
		_mat_fail = StandardMaterial3D.new()
		_mat_fail.albedo_color = Color(1.0, 0.2, 0.2, 1.0)
		_mat_fail.emission_enabled = true
		_mat_fail.emission = Color(1.0, 0.2, 0.2, 1.0)

	if _mat_floor == null:
		_mat_floor = StandardMaterial3D.new()
		_mat_floor.albedo_color = Color(0.16, 0.17, 0.2, 1.0)


## Constructs the 12x12m floor pad, status banner, and cell camera.
func _build_pad_if_needed() -> void:
	if not has_node("PadFloor"):
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "PadFloor"
		body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
		body.collision_mask = 0
		body.position = Vector3(0.0, -PAD_THICKNESS * 0.5, 0.0)

		var col: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = Vector3(PAD_SIZE, PAD_THICKNESS, PAD_SIZE)
		col.shape = box_shape
		body.add_child(col)

		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = Vector3(PAD_SIZE, PAD_THICKNESS, PAD_SIZE)
		mesh_inst.mesh = box_mesh
		mesh_inst.material_override = _mat_floor
		mesh_inst.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
		body.add_child(mesh_inst)
		add_child(body)

	if not has_node("StatusLabel"):
		_status_label = Label3D.new()
		_status_label.name = "StatusLabel"
		_status_label.position = Vector3(0.0, 4.4, 0.0)
		_status_label.pixel_size = 0.015
		_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_status_label.no_depth_test = true
		add_child(_status_label)
	else:
		_status_label = get_node("StatusLabel") as Label3D

	if not has_node("StatusBar"):
		_status_bar = MeshInstance3D.new()
		_status_bar.name = "StatusBar"
		var bar_mesh: BoxMesh = BoxMesh.new()
		bar_mesh.size = Vector3(4.0, 0.2, 0.2)
		_status_bar.mesh = bar_mesh
		_status_bar.position = Vector3(0.0, 3.6, -4.5)
		add_child(_status_bar)
	else:
		_status_bar = get_node("StatusBar") as MeshInstance3D

	if not has_node("CellCamera"):
		_cell_camera = Camera3D.new()
		_cell_camera.name = "CellCamera"
		_cell_camera.position = Vector3(0.0, 4.5, 8.5)
		add_child(_cell_camera)
		_cell_camera.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
	else:
		_cell_camera = get_node("CellCamera") as Camera3D
