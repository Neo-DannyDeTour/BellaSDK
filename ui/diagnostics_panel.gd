## Manages runtime rendering diagnostics, bottleneck identification, and draw call breakdown.
##
## [RenderDiagnosticsPanel] analyzes CPU vs GPU frame budgets, ranks top resource offenders,
## aggregates draw call/shadow sources via explicit snapshot,
## and logs hitches safely in debug builds.
class_name RenderDiagnosticsPanel
extends PanelContainer

## Tab mode selection for diagnostic inspection.
enum DiagnosticTab {
	PIPELINE,
	PERFORMANCE,
}

## Refresh interval in seconds (4 Hz) for cheap engine scalar updates.
const UPDATE_INTERVAL: float = 0.25

## Strict 60 FPS frame budget limit in milliseconds (1000.0 / 60.0).
const TARGET_FRAME_BUDGET_MS: float = 16.666

## Minimum time threshold in ms for a subsystem to be listed under Top Offenders.
const OFFENDER_THRESHOLD_MS: float = 0.5

## Maximum number of frame hitch records to retain in the display buffer.
const MAX_HITCH_RECORDS: int = 5

## Minimum interval in seconds between consecutive CSV disk flushes.
const CSV_FLUSH_INTERVAL: float = 2.0

## Hitch trigger threshold in milliseconds (target 33.33ms = 30 FPS drop threshold).
const HITCH_STUTTER_THRESHOLD_MS: float = 33.333

## RichTextLabel displaying real-time formatted performance and pipeline diagnostics.
@onready var diagnostics_label: RichTextLabel = %DiagnosticsLabel

## Button switching view to viewport and canvas layer hierarchy.
@onready var subviewports_tab_button: Button = %SubViewportsTabButton

## Button switching view to CPU, GPU, and rendering performance monitors.
@onready var perf_tab_button: Button = %PerfTabButton

## Button triggering an explicit one-off scene geometry scan.
@onready var scan_geometry_button: Button = %ScanGeometryButton

## Dedicated RichTextLabel for static geometry snapshot to avoid text repainting stalls.
@onready var survey_label: RichTextLabel = %SurveyLabel if has_node("%SurveyLabel") else null

## Current active diagnostic tab.
var _current_tab: DiagnosticTab = DiagnosticTab.PERFORMANCE

## Frame accumulation timer to throttle GUI updates.
var _refresh_timer: float = 0.0

## Timestamp of the previous frame in microseconds for hitch detection.
var _last_tick_usec: int = 0

## Ring buffer storing recent hitch events exceeding 33.33 ms.
var _recent_hitches: Array[Dictionary] = []

## Pre-allocated CSV file path targeting the user's desktop.
var _csv_path: String = ""

## Persistent FileAccess instance to prevent disk open/close stalls.
var _csv_file: FileAccess

## Static snapshot text for scene geometry to eliminate tree recursion lag.
var _cached_branch_survey: String = "Press [Scan Scene Geometry] to inspect hierarchy.\n"

## In-memory write buffer for hitch lines to prevent blocking file I/O during frames.
var _csv_write_buffer: PackedStringArray = PackedStringArray()

## Accumulated time since the last CSV disk flush.
var _csv_flush_timer: float = 0.0

## Flag preventing hitch logger re-entry while executing deliberate manual scans.
var _is_performing_manual_scan: bool = false


## Lifecycle method called when the node enters the scene tree.
## Connects tab signals, layout constraints, and initializes rendering measurement.
func _ready() -> void:
	print("RenderDiagnosticsPanel: _ready() called.")
	visible = false
	_apply_layout_constraints()
	get_viewport().size_changed.connect(_apply_layout_constraints)

	subviewports_tab_button.pressed.connect(_on_pipeline_tab_pressed)
	perf_tab_button.pressed.connect(_on_perf_tab_pressed)
	scan_geometry_button.pressed.connect(_on_scan_geometry_pressed)
	_update_tab_button_visuals()

	if OS.has_feature("debug"):
		_init_csv_logging()

	var vp_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	_last_tick_usec = Time.get_ticks_usec()


## Closes persistent file handles and flushes remaining records on node exit.
func _exit_tree() -> void:
	print("RenderDiagnosticsPanel: _exit_tree() cleaning up file handles.")
	_flush_csv_to_disk()
	if _csv_file:
		_csv_file.close()
		_csv_file = null


## Initializes the desktop CSV file handle only in debug builds.
func _init_csv_logging() -> void:
	print("RenderDiagnosticsPanel: Initializing hitch CSV log handle.")
	var desktop_dir: String = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	_csv_path = desktop_dir.path_join("godot_hitches.csv")
	var file_exists: bool = FileAccess.file_exists(_csv_path)
	_csv_file = FileAccess.open(
		_csv_path, FileAccess.READ_WRITE if file_exists else FileAccess.WRITE
	)
	if _csv_file:
		if not file_exists:
			_csv_file.store_line("Timestamp,FrameTime_ms,Culprit,CulpritTime_ms,DrawCalls")
		else:
			_csv_file.seek_end()


## Switches active tab to Viewports & Layers pipeline.
func _on_pipeline_tab_pressed() -> void:
	print("RenderDiagnosticsPanel: Switching to Pipeline tab.")
	_current_tab = DiagnosticTab.PIPELINE
	_update_tab_button_visuals()
	_refresh_diagnostics_display()


## Switches active tab to CPU/GPU and Rendering performance monitors.
func _on_perf_tab_pressed() -> void:
	print("RenderDiagnosticsPanel: Switching to Performance tab.")
	_current_tab = DiagnosticTab.PERFORMANCE
	_update_tab_button_visuals()
	_refresh_diagnostics_display()


## Updates visual button toggles to reflect the active tab.
func _update_tab_button_visuals() -> void:
	subviewports_tab_button.disabled = (_current_tab == DiagnosticTab.PIPELINE)
	perf_tab_button.disabled = (_current_tab == DiagnosticTab.PERFORMANCE)


## Sets horizontal centering and full vertical screen spanning anchors.
func _apply_layout_constraints() -> void:
	print("RenderDiagnosticsPanel: Updating panel layout anchors.")
	var panel_width: float = 640.0
	var half_width: float = panel_width / 2.0

	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -half_width
	offset_right = half_width

	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_top = 20.0
	offset_bottom = -20.0

	custom_minimum_size = Vector2(panel_width, 0.0)


## Accumulates delta time, buffers hitch events, and periodically updates diagnostics.
## [param delta] The elapsed time since the previous frame in seconds.
func _process(delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var frame_time_ms: float = (now_usec - _last_tick_usec) * 0.001
	_last_tick_usec = now_usec

	if not _is_performing_manual_scan and frame_time_ms > HITCH_STUTTER_THRESHOLD_MS:
		_record_hitch_event(frame_time_ms)

	if _csv_file and OS.has_feature("debug"):
		_csv_flush_timer += delta
		if _csv_flush_timer >= CSV_FLUSH_INTERVAL:
			_csv_flush_timer = 0.0
			_flush_csv_to_disk()

	if not visible:
		return

	_refresh_timer += delta
	if _refresh_timer >= UPDATE_INTERVAL:
		_refresh_timer = 0.0
		_refresh_diagnostics_display()


## Toggles panel visibility state.
## [return] The new visibility state after toggling.
func toggle_window() -> bool:
	visible = not visible
	print("RenderDiagnosticsPanel: Visibility toggled -> ", visible)
	if visible:
		_apply_layout_constraints()
		_refresh_diagnostics_display()
	return visible


## Records hitch data into memory and queues CSV row without synchronous disk writes.
## [param frame_time_ms] The total elapsed duration of the spiked frame.
func _record_hitch_event(frame_time_ms: float) -> void:
	var vp_rid: RID = get_viewport().get_viewport_rid()
	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var culprit: String = "GPU"
	var culprit_ms: float = gpu_ms
	if proc_ms > culprit_ms:
		culprit = "CPU Process"
		culprit_ms = proc_ms
	if physics_ms > culprit_ms:
		culprit = "Physics"
		culprit_ms = physics_ms

	var timestamp: String = Time.get_time_string_from_system()
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

	var record: Dictionary = {
		"culprit": culprit,
		"culprit_ms": culprit_ms,
		"duration_ms": frame_time_ms,
		"time": timestamp,
	}
	_recent_hitches.push_back(record)
	if _recent_hitches.size() > MAX_HITCH_RECORDS:
		_recent_hitches.pop_front()

	if _csv_file and OS.has_feature("debug"):
		_csv_write_buffer.append(
			"%s,%.2f,%s,%.2f,%d" % [timestamp, frame_time_ms, culprit, culprit_ms, draw_calls]
		)


## Flushes in-memory hitch entries to disk in batch to prevent frame stutter loops.
func _flush_csv_to_disk() -> void:
	if not _csv_file or _csv_write_buffer.is_empty():
		return
	for line: String in _csv_write_buffer:
		_csv_file.store_line(line)
	_csv_write_buffer.clear()
	_csv_file.flush()


## Dispatches view refresh depending on the currently selected tab.
func _refresh_diagnostics_display() -> void:
	if not diagnostics_label:
		return

	match _current_tab:
		DiagnosticTab.PIPELINE:
			diagnostics_label.text = _build_pipeline_report()
		DiagnosticTab.PERFORMANCE:
			diagnostics_label.text = _build_performance_report()


## Performs a single, one-off scan of scene branches on demand.
func scan_scene_geometry() -> void:
	print("RenderDiagnosticsPanel: Executing manual geometry scan.")
	_is_performing_manual_scan = true

	var current_scene: Node = get_tree().current_scene
	if not is_instance_valid(current_scene):
		_cached_branch_survey = "  No active scene available to inspect.\n"
		_apply_survey_to_ui()
		_is_performing_manual_scan = false
		_last_tick_usec = Time.get_ticks_usec()
		return

	var lines: PackedStringArray = PackedStringArray()

	for child: Node in current_scene.get_children():
		if child is CanvasLayer or child is Control:
			continue

		var mesh_count: int = 0
		var shadow_light_count: int = 0
		var stack: Array[Node] = [child]

		while not stack.is_empty():
			var curr: Node = stack.pop_back()
			if curr is MeshInstance3D:
				if curr.visible and curr.is_inside_tree():
					mesh_count += 1
			elif curr is Light3D:
				if curr.visible and curr.shadow_enabled:
					shadow_light_count += 1

			for grandchild: Node in curr.get_children():
				stack.append(grandchild)

		if mesh_count > 5 or shadow_light_count > 0:
			var light_warn: String = (
				" | %d Shadows" % shadow_light_count if shadow_light_count > 0 else ""
			)
			lines.append(
				"  |- %-20s: %d meshes%s" % [str(child.name).left(20), mesh_count, light_warn]
			)

	_cached_branch_survey = (
		"  No dense branches found.\n" if lines.is_empty() else "\n".join(lines) + "\n"
	)
	_apply_survey_to_ui()

	_is_performing_manual_scan = false
	_last_tick_usec = Time.get_ticks_usec()


## Applies the survey text directly to the dedicated UI element.
func _apply_survey_to_ui() -> void:
	if is_instance_valid(survey_label):
		survey_label.text = _cached_branch_survey


## Constructs a fixed-size, plain-text performance report using engine counters.
## [return] Pre-aligned diagnostic string with zero dynamic tree recursion.
func _build_performance_report() -> String:
	var vp_rid: RID = get_viewport().get_viewport_rid()
	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	var cpu_prep_ms: float = (
		RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		+ RenderingServer.get_frame_setup_time_cpu()
	)
	var cpu_script_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var cpu_phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var total_cpu_ms: float = cpu_script_ms + cpu_phys_ms + cpu_prep_ms
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects_drawn: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))

	var is_gpu: bool = gpu_ms > total_cpu_ms
	var max_time: float = gpu_ms if is_gpu else total_cpu_ms
	var budget_pct: float = (max_time / TARGET_FRAME_BUDGET_MS) * 100.0

	return (
		"""=== PRIMARY BOTTLENECK ===
Status: [%s] (%.2f ms | %.1f%% budget)

=== TOP OFFENDERS ===
* GPU Passes          : %.2f ms
* CPU Process/Scripts : %.2f ms
* CPU Render Prep     : %.2f ms
* CPU Physics         : %.2f ms

=== DRAW METRICS ===
* Total Draw Calls    : %d (Target: < 600)
* Objects Drawn       : %d
"""
		% [
			"GPU BOUND" if is_gpu else "CPU BOUND",
			max_time,
			budget_pct,
			gpu_ms,
			cpu_script_ms,
			cpu_prep_ms,
			cpu_phys_ms,
			draw_calls,
			objects_drawn
		]
	)


## Constructs the BBCode string report for SubViewports.
## [return] Formatted BBCode viewport breakdown.
func _build_pipeline_report() -> String:
	var text: String = "[b][color=yellow]=== VIEWPORT & RENDER PIPELINE ===[/color][/b]\n"
	var root_vp: Window = get_tree().root
	text += "* %s (Root Window: %dx%d)\n\n" % [str(root_vp.name), root_vp.size.x, root_vp.size.y]

	text += "[b][color=yellow]=== ACTIVE SUBVIEWPORTS ===[/color][/b]\n"
	var sub_viewports: Array[SubViewport] = []
	_collect_subviewports(root_vp, sub_viewports)

	if sub_viewports.is_empty():
		text += "[color=gray]  No active SubViewports found in tree.[/color]\n"
	else:
		for vp: SubViewport in sub_viewports:
			var mode_str: String = "ALWAYS"
			match vp.render_target_update_mode:
				SubViewport.UPDATE_DISABLED:
					mode_str = "[color=gray]DISABLED[/color]"
				SubViewport.UPDATE_ONCE:
					mode_str = "[color=yellow]ONCE[/color]"
				SubViewport.UPDATE_WHEN_VISIBLE:
					mode_str = "[color=green]WHEN_VISIBLE[/color]"
				SubViewport.UPDATE_WHEN_PARENT_VISIBLE:
					mode_str = "[color=green]PARENT_VISIBLE[/color]"
				SubViewport.UPDATE_ALWAYS:
					mode_str = "[color=red]ALWAYS[/color]"

			text += "* %s (%dx%d) -> Mode: %s\n" % [str(vp.name), vp.size.x, vp.size.y, mode_str]

	return text


## Recursively collects all SubViewport nodes including internal children.
## [param current_node] The current node being inspected.
## [param out_viewports] The destination array to populate with found SubViewports.
func _collect_subviewports(current_node: Node, out_viewports: Array[SubViewport]) -> void:
	if current_node is SubViewport:
		out_viewports.append(current_node)

	for child: Node in current_node.get_children(true):
		_collect_subviewports(child, out_viewports)


## Handles the scan button press to trigger an on-demand geometry audit.
func _on_scan_geometry_pressed() -> void:
	print("RenderDiagnosticsPanel: Scan Geometry button clicked.")
	scan_scene_geometry()
