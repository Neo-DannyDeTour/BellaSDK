## Factorio-style 3D visual test grid running mechanic cells and reporting live status.
class_name VisualTestGrid
extends Node3D

## Emitted when all registered [MechanicTestCell] instances finish running.
signal all_tests_completed(summary: Dictionary)

## Grid spacing between adjacent test cell centers in meters.
const CELL_SPACING: float = 16.0

## Number of columns in the 3D test grid layout.
const GRID_COLUMNS: int = 3

## Registered Phase 1 mechanic test cell scripts.
var _cell_scripts: Array[GDScript] = [
	preload("res://test/visual_grid/cells/cell_door_button.gd"),
	preload("res://test/visual_grid/cells/cell_crate_barrel.gd"),
	preload("res://test/visual_grid/cells/cell_trigger_zone.gd"),
	preload("res://test/visual_grid/cells/cell_health_enemy.gd"),
	preload("res://test/visual_grid/cells/cell_player_locomotion.gd"),
	preload("res://test/visual_grid/cells/cell_weapon_drop.gd"),
]

## All instantiated [MechanicTestCell] nodes in grid order.
var _cells: Array[MechanicTestCell] = []

## Per-cell result records keyed by cell title.
var _results: Dictionary[String, Dictionary] = {}

## Overview [Camera3D] framing the entire test grid.
var _overview_camera: Camera3D = null

## HUD summary label showing pass, fail, and running counts.
var _summary_label: Label = null

## Container holding quick-jump buttons for failed cells.
var _fail_buttons_box: VBoxContainer = null

## Guard preventing overlapping grid runs.
var _is_running: bool = false


## Builds environment, spawns cells in a 3D grid, creates HUD, and starts tests.
func _ready() -> void:
	_build_environment()
	_build_hud()
	_spawn_cells()
	run_all_cells()


## Handles 'R' key to re-run failed cells or reset overview camera with 'O'.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_ev: InputEventKey = event
		if key_ev.pressed and not key_ev.echo:
			if key_ev.keycode == KEY_R and not _is_running:
				run_failed_cells()
			elif key_ev.keycode == KEY_O and is_instance_valid(_overview_camera):
				_overview_camera.current = true


## Executes all cells sequentially and emits [signal all_tests_completed].
func run_all_cells() -> void:
	if _is_running:
		return
	_is_running = true
	_results.clear()
	_clear_fail_buttons()
	_update_hud_summary()

	for cell: MechanicTestCell in _cells:
		await cell.start_test()

	_finish_run()


## Re-runs only cells that failed in the previous pass.
func run_failed_cells() -> void:
	if _is_running:
		return
	_is_running = true
	_clear_fail_buttons()
	_update_hud_summary()

	for cell: MechanicTestCell in _cells:
		if cell.state == MechanicTestCell.CellState.FAILED:
			await cell.start_test()

	_finish_run()


## Finalizes run, restores overview camera, and emits summary dictionary.
func _finish_run() -> void:
	_is_running = false
	if is_instance_valid(_overview_camera):
		_overview_camera.current = true

	var passed_count: int = 0
	var failed_count: int = 0
	for cell: MechanicTestCell in _cells:
		if cell.state == MechanicTestCell.CellState.PASSED:
			passed_count += 1
		elif cell.state == MechanicTestCell.CellState.FAILED:
			failed_count += 1

	var summary: Dictionary = {
		"total": _cells.size(),
		"passed": passed_count,
		"failed": failed_count,
		"results": _results.duplicate(true),
	}
	_update_hud_summary()
	print("VisualTestGrid: Completed -> PASS=%d FAIL=%d" % [passed_count, failed_count])
	all_tests_completed.emit(summary)


## Instantiates all registered [member _cell_scripts] in an X/Z grid.
func _spawn_cells() -> void:
	var idx: int = 0
	for cell_script: GDScript in _cell_scripts:
		var raw: Object = cell_script.new()
		if not (raw is MechanicTestCell):
			continue
		var cell: MechanicTestCell = raw
		var col: int = idx % GRID_COLUMNS
		var row: int = floori(float(idx) / float(GRID_COLUMNS))
		cell.position = Vector3(float(col) * CELL_SPACING, 0.0, float(row) * CELL_SPACING)
		cell.cell_completed.connect(_on_cell_completed)
		add_child(cell)
		_cells.append(cell)
		idx += 1


## Records cell completion, updates HUD, and adds a jump button on failure.
func _on_cell_completed(
	cell_name: String, passed: bool, reason: String, screenshot_path: String
) -> void:
	_results[cell_name] = {
		"passed": passed,
		"reason": reason,
		"screenshot": screenshot_path,
	}
	if not passed:
		_add_fail_button(cell_name)
	_update_hud_summary()


## Updates the top-left HUD summary label with live pass/fail/running counts.
func _update_hud_summary() -> void:
	if not is_instance_valid(_summary_label):
		return
	var passed_count: int = 0
	var failed_count: int = 0
	var running_count: int = 0
	for cell: MechanicTestCell in _cells:
		if cell.state == MechanicTestCell.CellState.PASSED:
			passed_count += 1
		elif cell.state == MechanicTestCell.CellState.FAILED:
			failed_count += 1
		elif cell.state == MechanicTestCell.CellState.RUNNING:
			running_count += 1
	_summary_label.text = (
		"BELLA VISUAL TEST GRID\nPASS: %d  |  FAIL: %d  |  RUNNING: %d\n[R] Re-run Failed  [O] Overview"
		% [passed_count, failed_count, running_count]
	)


## Adds a clickable button to snap the camera to a failed [MechanicTestCell].
func _add_fail_button(cell_name: String) -> void:
	if not is_instance_valid(_fail_buttons_box):
		return
	var btn: Button = Button.new()
	btn.text = "Inspect FAIL: " + cell_name
	btn.pressed.connect(_on_fail_button_pressed.bind(cell_name))
	_fail_buttons_box.add_child(btn)


## Clears all failure jump buttons from the HUD.
func _clear_fail_buttons() -> void:
	if is_instance_valid(_fail_buttons_box):
		Utilities.clear_children(_fail_buttons_box)


## Snaps active camera to the [MechanicTestCell] matching [param cell_name].
func _on_fail_button_pressed(cell_name: String) -> void:
	for cell: MechanicTestCell in _cells:
		if cell.cell_title == cell_name:
			var cam: Camera3D = cell.get_cell_camera()
			if is_instance_valid(cam):
				cam.current = true
			return


## Creates sun light, world environment, and overview [Camera3D].
func _build_environment() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.11, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.42, 1.0)
	env_node.environment = env
	add_child(env_node)

	_overview_camera = Camera3D.new()
	_overview_camera.position = Vector3(16.0, 22.0, 32.0)
	add_child(_overview_camera)
	_overview_camera.look_at(Vector3(16.0, 0.0, 8.0), Vector3.UP)
	_overview_camera.current = true


## Builds minimal HUD overlay for live status and failure inspection.
func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	layer.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	panel.add_child(vbox)

	_summary_label = Label.new()
	_summary_label.text = "BELLA VISUAL TEST GRID"
	vbox.add_child(_summary_label)

	_fail_buttons_box = VBoxContainer.new()
	vbox.add_child(_fail_buttons_box)
