## Autonomous CLI runner executing [VisualTestGrid] and writing JSON test report.
class_name RunVisualTests
extends SceneTree

## Output path for the generated visual test JSON report.
const REPORT_PATH: String = "user://test_reports/report.json"

## Maximum global timeout in seconds before aborting hung tests.
const GLOBAL_TIMEOUT_SEC: float = 45.0

## Instantiated [VisualTestGrid] scene root.
var _grid: Node3D = null

## Accumulated elapsed seconds for timeout enforcement.
var _elapsed_sec: float = 0.0

## Guard ensuring exit happens once.
var _finished: bool = false


## Loads [VisualTestGrid] after autoloads initialize and connects completion signal.
func _initialize() -> void:
	print("RunVisualTests: Starting visual mechanic test suite...")
	var packed: PackedScene = load("res://test/visual_grid/visual_test_grid.tscn") as PackedScene
	if not is_instance_valid(packed):
		push_error("RunVisualTests: Failed to load visual_test_grid.tscn.")
		quit(1)
		return

	var inst: Node = packed.instantiate()
	if not (inst is Node3D) or not inst.has_signal("all_tests_completed"):
		push_error("RunVisualTests: Root node is not VisualTestGrid.")
		quit(1)
		return

	_grid = inst as Node3D
	_grid.connect("all_tests_completed", _on_all_tests_completed)
	root.add_child(_grid)


## Enforces global timeout in case a mechanic cell hangs indefinitely.
func _process(delta: float) -> bool:
	if _finished:
		return false
	_elapsed_sec += delta
	if _elapsed_sec >= GLOBAL_TIMEOUT_SEC:
		_finished = true
		push_error("RunVisualTests: Global timeout reached after %.1fs." % GLOBAL_TIMEOUT_SEC)
		quit(1)
		return true
	return false


## Writes JSON report and exits with status 0 on full pass or 1 on failure.
func _on_all_tests_completed(summary: Dictionary) -> void:
	if _finished:
		return
	_finished = true

	DirAccess.make_dir_recursive_absolute("user://test_reports")
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(summary, "\t"))
		file.close()

	var failed: int = summary.get("failed", 1)
	var passed: int = summary.get("passed", 0)
	var total: int = summary.get("total", 0)
	print(
		(
			"RunVisualTests: Report written to %s | PASS=%d/%d FAIL=%d"
			% [ProjectSettings.globalize_path(REPORT_PATH), passed, total, failed]
		)
	)
	quit(0 if failed == 0 else 1)
