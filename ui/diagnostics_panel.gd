## Runtime rendering diagnostics, bottleneck tracking, and glitch triage panel.
class_name RenderDiagnosticsPanel
extends PanelContainer

@warning_ignore("unused_signal")
## Emitted when diagnostic metrics refresh. Passes snapshot [Dictionary].
signal metrics_updated(data: Dictionary)

## Tab mode selection for diagnostic inspection.
enum DiagnosticTab {
	PIPELINE,
	PERFORMANCE,
}

## Refresh interval in seconds (4 Hz) for engine scalar updates.
const UPDATE_INTERVAL: float = 0.25

## Strict 60 FPS frame budget limit in milliseconds (1000.0 / 60.0).
const TARGET_FRAME_BUDGET_MS: float = 16.666

## Minimum time threshold in ms for a subsystem to be listed under offenders.
const OFFENDER_THRESHOLD_MS: float = 0.5

## Maximum number of frame hitch records to retain in the display buffer.
const MAX_HITCH_RECORDS: int = 5

## Minimum interval in seconds between consecutive CSV disk flushes.
const CSV_FLUSH_INTERVAL: float = 2.0

## Hitch trigger threshold in milliseconds for drop detection.
const HITCH_STUTTER_THRESHOLD_MS: float = 33.333

## Maximum tail byte window read from log file during orphan inspection.
const LOG_READ_WINDOW_BYTES: int = 16384

## Lookup table mapping [enum SubViewport.UpdateMode] integers to BBCode labels.
const UPDATE_MODE_LABELS: Dictionary[int, String] = {
	0: "[color=gray]DISABLED[/color]",
	1: "[color=yellow]ONCE[/color]",
	2: "[color=green]WHEN_VISIBLE[/color]",
	3: "[color=green]PARENT_VISIBLE[/color]",
	4: "[color=red]ALWAYS[/color]",
}

## Enables continuous background CSV hitch logging even when panel is hidden.
@export var enable_background_hitch_logging: bool = false

## RichTextLabel displaying real-time formatted diagnostics.
@onready var diagnostics_label: RichTextLabel = %DiagnosticsLabel

## Button switching view to viewport and canvas layer hierarchy.
@onready var subviewports_tab_button: Button = %SubViewportsTabButton

## Button switching view to performance monitors.
@onready var perf_tab_button: Button = %PerfTabButton

## Button triggering an explicit one-off scene geometry scan.
@onready var scan_geometry_button: Button = %ScanGeometryButton

## Button triggering an explicit orphan node scan and console dump.
@onready
var scan_orphans_button: Button = %ScanOrphansButton if has_node("%ScanOrphansButton") else null

## Dedicated RichTextLabel for static geometry or orphan snapshot.
@onready var survey_label: RichTextLabel = %SurveyLabel if has_node("%SurveyLabel") else null

## Button toggling live layer isolation.
@onready var live_isolator_button: Button = (
	%LiveIsolatorButton
	if has_node("%LiveIsolatorButton")
	else (%LiveIsolatorTabButton if has_node("%LiveIsolatorTabButton") else null)
)

## Button dumping current geometry and render profile to disk.
@onready var dump_audit_button: Button = %DumpAuditButton if has_node("%DumpAuditButton") else null

## Toggle button for real-time directional and positional shadow casting.
@onready var shadows_toggle_button: Button = (
	%ToggleShadowsButton if has_node("%ToggleShadowsButton") else null
)

## Toggle button for real-time signed distance field global illumination.
@onready
var sdfgi_toggle_button: Button = %ToggleSdfgiButton if has_node("%ToggleSdfgiButton") else null

## Toggle button for real-time depth fog and volumetric fog.
@onready var fog_toggle_button: Button = %ToggleFogButton if has_node("%ToggleFogButton") else null

## Button toggling a minimal diorama inspection mode.
@onready
var diorama_button: Button = %ToggleDioramaButton if has_node("%ToggleDioramaButton") else null

## Button cycling through VRAM buffer flush and suspect isolation stages.
@onready
var triage_glitch_button: Button = %TriageGlitchButton if has_node("%TriageGlitchButton") else null

## Current active diagnostic tab.
var _current_tab: DiagnosticTab = DiagnosticTab.PERFORMANCE

## Frame accumulation timer to throttle GUI updates.
var _refresh_timer: float = 0.0

## Timestamp of the previous frame in microseconds for hitch detection.
var _last_tick_usec: int = 0

## Ring buffer storing recent hitch events exceeding threshold.
var _recent_hitches: Array[Dictionary] = []

## Pre-allocated CSV file path targeting the user desktop.
var _csv_path: String = ""

## Persistent FileAccess instance preventing disk open/close stalls.
var _csv_file: FileAccess

## Static snapshot text for scene geometry to eliminate tree recursion.
var _cached_branch_survey: String = "Press [Scan Scene Geometry] to inspect hierarchy.\n"

## In-memory write buffer for hitch lines preventing blocking file I/O.
var _csv_write_buffer: PackedStringArray = PackedStringArray()

## Accumulated time since the last CSV disk flush.
var _csv_flush_timer: float = 0.0

## Flag preventing hitch logger re-entry during deliberate scans.
var _is_performing_manual_scan: bool = false

## Tracks active isolation pass state for rendering layers.
var _is_isolating_layers: bool = false

## Tracks active diorama mode state for scene isolation.
var _is_diorama_active: bool = false

## Current step index (0-4) of the diagonal artifact triage state machine.
var _triage_step: int = 0

## Cached visibility states of water and particle nodes muted during triage.
var _triage_muted_nodes: Array[Node3D] = []


## Connects UI signals, sets constraints, and initializes measuring.
func _ready() -> void:
	print("RenderDiagnosticsPanel: Initializing diagnostic hooks.")
	visible = false
	_apply_layout_constraints()
	get_viewport().size_changed.connect(_apply_layout_constraints)

	subviewports_tab_button.pressed.connect(_on_pipeline_tab_pressed)
	perf_tab_button.pressed.connect(_on_perf_tab_pressed)
	scan_geometry_button.pressed.connect(_on_scan_geometry_pressed)

	if is_instance_valid(scan_orphans_button):
		scan_orphans_button.pressed.connect(_on_scan_orphans_pressed)
	if is_instance_valid(live_isolator_button):
		live_isolator_button.pressed.connect(_on_live_isolator_pressed)
	if is_instance_valid(dump_audit_button):
		dump_audit_button.pressed.connect(_on_dump_audit_pressed)
	if is_instance_valid(diorama_button):
		diorama_button.pressed.connect(_on_diorama_pressed)
	if is_instance_valid(shadows_toggle_button):
		shadows_toggle_button.pressed.connect(_on_shadows_toggled)
	if is_instance_valid(sdfgi_toggle_button):
		sdfgi_toggle_button.pressed.connect(_on_sdfgi_toggled)
	if is_instance_valid(fog_toggle_button):
		fog_toggle_button.pressed.connect(_on_fog_toggled)

	_ensure_triage_button()
	if is_instance_valid(triage_glitch_button):
		triage_glitch_button.pressed.connect(_on_triage_glitch_pressed)

	_update_tab_button_visuals()

	if OS.get_cmdline_args().has("--log-hitches"):
		enable_background_hitch_logging = true

	if OS.has_feature("debug") and enable_background_hitch_logging:
		_init_csv_logging()

	_last_tick_usec = Time.get_ticks_usec()

	sync_toggle_button_labels()
	_update_processing_state()


## Flushes remaining records and closes file handle on tree exit.
func _exit_tree() -> void:
	print("RenderDiagnosticsPanel: Releasing handles.")
	_flush_csv_to_disk()
	if _csv_file:
		_csv_file.close()
		_csv_file = null


## Creates the Triage Glitch button dynamically if missing from the scene.
func _ensure_triage_button() -> void:
	if is_instance_valid(triage_glitch_button):
		return
	if is_instance_valid(diorama_button) and diorama_button.get_parent():
		print("RenderDiagnosticsPanel: Creating fallback TriageGlitchButton.")
		triage_glitch_button = Button.new()
		triage_glitch_button.name = "TriageGlitchButton"
		triage_glitch_button.text = "Triage Glitch"
		diorama_button.get_parent().add_child(triage_glitch_button)


## Initializes desktop CSV file handle only in debug builds.
func _init_csv_logging() -> void:
	if _csv_file != null:
		return
	print("RenderDiagnosticsPanel: Creating debug hitch logger.")
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
	print("RenderDiagnosticsPanel: Switched to Pipeline tab.")
	_current_tab = DiagnosticTab.PIPELINE
	_update_tab_button_visuals()
	_refresh_diagnostics_display()


## Switches active tab to performance monitors.
func _on_perf_tab_pressed() -> void:
	print("RenderDiagnosticsPanel: Switched to Performance tab.")
	_current_tab = DiagnosticTab.PERFORMANCE
	_update_tab_button_visuals()
	_refresh_diagnostics_display()


## Updates visual button states to reflect the active tab.
func _update_tab_button_visuals() -> void:
	subviewports_tab_button.disabled = (_current_tab == DiagnosticTab.PIPELINE)
	perf_tab_button.disabled = (_current_tab == DiagnosticTab.PERFORMANCE)


## Aligns panel horizontally centered with full vertical height.
func _apply_layout_constraints() -> void:
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


## Gates processing active state based on visibility and debug logging.
func _update_processing_state() -> void:
	var bg_logging: bool = (
		enable_background_hitch_logging and _csv_file != null and OS.has_feature("debug")
	)
	var needs_process: bool = visible or bg_logging
	var vp: Viewport = get_viewport()
	if is_instance_valid(vp):
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), needs_process)
	if needs_process:
		_last_tick_usec = Time.get_ticks_usec()
	set_process(needs_process)


## Accumulates delta time, logs hitches, and flushes CSV buffer.
func _process(delta: float) -> void:
	var has_logger: bool = (
		enable_background_hitch_logging and _csv_file != null and OS.has_feature("debug")
	)

	if has_logger:
		var now_usec: int = Time.get_ticks_usec()
		var frame_time_ms: float = (now_usec - _last_tick_usec) * 0.001
		_last_tick_usec = now_usec

		if not _is_performing_manual_scan and frame_time_ms > HITCH_STUTTER_THRESHOLD_MS:
			_record_hitch_event(frame_time_ms)

		_csv_flush_timer += delta
		if _csv_flush_timer >= CSV_FLUSH_INTERVAL and not _csv_write_buffer.is_empty():
			_csv_flush_timer = 0.0
			_flush_csv_to_disk()

	if not visible:
		return

	_refresh_timer += delta
	if _refresh_timer >= UPDATE_INTERVAL:
		_refresh_timer = 0.0
		_refresh_diagnostics_display()


## Toggles panel visibility and manages active process state.
func toggle_window() -> bool:
	visible = not visible
	print("RenderDiagnosticsPanel: Toggled visibility to ", visible)
	_update_processing_state()

	if visible:
		_apply_layout_constraints()
		sync_toggle_button_labels()
		_refresh_diagnostics_display()
	return visible


## Records hitch telemetry in memory and queues CSV buffer line.
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

	_csv_write_buffer.append(
		"%s,%.2f,%s,%.2f,%d" % [timestamp, frame_time_ms, culprit, culprit_ms, draw_calls]
	)


## Writes buffered hitch records to disk to avoid frame stutter loops.
func _flush_csv_to_disk() -> void:
	if not _csv_file or _csv_write_buffer.is_empty():
		return
	for line: String in _csv_write_buffer:
		_csv_file.store_line(line)
	_csv_write_buffer.clear()
	_csv_file.flush()


## Refreshes panel display matching currently selected diagnostic tab.
func _refresh_diagnostics_display() -> void:
	if not diagnostics_label:
		return

	match _current_tab:
		DiagnosticTab.PIPELINE:
			diagnostics_label.text = _build_pipeline_report()
		DiagnosticTab.PERFORMANCE:
			diagnostics_label.text = _build_performance_report()


## Audits geometry branches and active shadow lights for a root node.
func _audit_branch_geometry(root_node: Node) -> PackedStringArray:
	print("RenderDiagnosticsPanel: Auditing branch for ", root_node.name)
	var lines: PackedStringArray = PackedStringArray()
	var total_meshes: int = 0
	var total_multimeshes: int = 0
	var total_shadow_lights: int = 0

	for child: Node in root_node.get_children():
		if child is CanvasLayer or child is Control or child is SubViewport:
			continue

		var branch_meshes: int = 0
		var branch_multis: int = 0
		var branch_shadows: int = 0
		var stack: Array[Node] = [child]

		while not stack.is_empty():
			var curr: Node = stack.pop_back()
			if curr is MeshInstance3D:
				var mesh_node: MeshInstance3D = curr
				if mesh_node.visible and mesh_node.is_inside_tree():
					branch_meshes += 1
			elif curr is MultiMeshInstance3D:
				var multi_node: MultiMeshInstance3D = curr
				if multi_node.visible and multi_node.is_inside_tree() and multi_node.multimesh:
					branch_multis += multi_node.multimesh.instance_count
			elif curr is Light3D:
				var light_node: Light3D = curr
				if light_node.visible and light_node.shadow_enabled:
					branch_shadows += 1

			for grandchild: Node in curr.get_children():
				if not (grandchild is SubViewport):
					stack.append(grandchild)

		total_meshes += branch_meshes
		total_multimeshes += branch_multis
		total_shadow_lights += branch_shadows

		if branch_meshes > 0 or branch_multis > 0 or branch_shadows > 0:
			var multi_info: String = " (+%d instanced)" % branch_multis if branch_multis > 0 else ""
			var light_info: String = " | %d Shadows" % branch_shadows if branch_shadows > 0 else ""
			lines.append(
				(
					"  |- %-20s: %d meshes%s%s"
					% [str(child.name).left(20), branch_meshes, multi_info, light_info]
				)
			)

	var header: String = (
		"  Total: %d meshes, %d multi-instances, %d shadow lights\n"
		% [total_meshes, total_multimeshes, total_shadow_lights]
	)
	lines.insert(0, header)
	return lines


## Traverses window hierarchy and compiles geometry statistics.
func scan_scene_geometry() -> void:
	print("RenderDiagnosticsPanel: Initiating full-tree geometry audit.")
	_is_performing_manual_scan = true

	var output_lines: PackedStringArray = PackedStringArray()
	var root_vp: Window = get_tree().root

	output_lines.append("[b][color=yellow]=== ROOT WINDOW GEOMETRY ===[/color][/b]")
	var current_scene: Node = get_tree().current_scene
	if is_instance_valid(current_scene):
		output_lines.append_array(_audit_branch_geometry(current_scene))
	else:
		output_lines.append("  No current scene found.")

	var sub_viewports: Array[SubViewport] = []
	_collect_subviewports(root_vp, sub_viewports)

	if not sub_viewports.is_empty():
		output_lines.append("\n[b][color=yellow]=== SUBVIEWPORT GEOMETRY ===[/color][/b]")
		for vp: SubViewport in sub_viewports:
			output_lines.append("* SubViewport: %s" % str(vp.name))
			output_lines.append_array(_audit_branch_geometry(vp))

	_cached_branch_survey = "\n".join(output_lines) + "\n"
	_apply_survey_to_ui()

	_is_performing_manual_scan = false
	_last_tick_usec = Time.get_ticks_usec()


## Dumps orphan nodes via [method Node.print_orphan_nodes] and parses log.
func scan_orphan_nodes() -> void:
	print("RenderDiagnosticsPanel: Scanning for orphan nodes.")
	_is_performing_manual_scan = true

	var orphan_count: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var total_nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	var output_lines: PackedStringArray = PackedStringArray()
	output_lines.append("[b][color=yellow]=== ORPHAN NODE AUDIT ===[/color][/b]")

	var count_color: String = "green" if orphan_count == 0 else "red"
	output_lines.append(
		(
			"Total Nodes: %d | Active Orphans: [b][color=%s]%d[/color][/b]"
			% [total_nodes, count_color, orphan_count]
		)
	)

	if orphan_count == 0:
		output_lines.append("[color=green]No orphan nodes detected. Memory is clean![/color]")
	else:
		var log_path: String = "user://logs/godot.log"
		var pre_len: int = 0
		if FileAccess.file_exists(log_path):
			var pre_file: FileAccess = FileAccess.open(log_path, FileAccess.READ)
			if pre_file:
				pre_len = pre_file.get_length()
				pre_file.close()

		print("=== BEGIN ORPHAN NODE DUMP ===")
		Node.print_orphan_nodes()
		print("=== END ORPHAN NODE DUMP ===")

		var extracted_list: String = _extract_orphan_dump_from_log(log_path, pre_len)
		if not extracted_list.is_empty():
			output_lines.append("\n[b][color=orange]Orphan Node List (from godot.log):[/color][/b]")
			output_lines.append(extracted_list)
		else:
			output_lines.append(
				"\n[color=cyan]-> Sent Node.print_orphan_nodes() to Console![/color]"
			)
			output_lines.append(
				(
					"[color=gray](Enable 'debug/file_logging/enable_file_logging' "
					+ "to display the live node list inside this panel.)[/color]"
				)
			)

	_cached_branch_survey = "\n".join(output_lines) + "\n"
	_apply_survey_to_ui()

	_is_performing_manual_scan = false
	_last_tick_usec = Time.get_ticks_usec()


## Extracts the latest orphan node dump block from the engine log file.
func _extract_orphan_dump_from_log(log_path: String, start_offset: int) -> String:
	if not FileAccess.file_exists(log_path):
		return ""

	var file: FileAccess = FileAccess.open(log_path, FileAccess.READ)
	if not file:
		return ""

	var file_len: int = file.get_length()
	var seek_pos: int = maxi(0, start_offset - 256)
	if file_len - seek_pos > LOG_READ_WINDOW_BYTES:
		seek_pos = maxi(0, file_len - LOG_READ_WINDOW_BYTES)

	file.seek(seek_pos)
	var raw_chunk: String = file.get_as_text()
	file.close()

	var begin_marker: String = "=== BEGIN ORPHAN NODE DUMP ==="
	var end_marker: String = "=== END ORPHAN NODE DUMP ==="
	var start_idx: int = raw_chunk.rfind(begin_marker)
	var end_idx: int = raw_chunk.rfind(end_marker)

	if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
		var body_start: int = start_idx + begin_marker.length()
		var content: String = raw_chunk.substr(body_start, end_idx - body_start).strip_edges()
		if not content.is_empty():
			return "[code]" + content + "[/code]"

	return ""


## Updates the survey label with cached scene hierarchy text.
func _apply_survey_to_ui() -> void:
	if is_instance_valid(survey_label):
		survey_label.bbcode_enabled = true
		survey_label.text = _cached_branch_survey


## Formats performance monitors into a detailed multi-channel breakdown.
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
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	var pipe_mesh: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH
	)
	var pipe_canvas: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS
	)

	var phys_pairs: int = int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	var phys_islands: int = int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))
	var total_nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphan_nodes: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	var is_gpu: bool = gpu_ms > total_cpu_ms
	var max_time: float = gpu_ms if is_gpu else total_cpu_ms
	var budget_pct: float = (max_time / TARGET_FRAME_BUDGET_MS) * 100.0

	var sdfgi_records: Array[Dictionary] = _audit_sdfgi_instances()
	var sdfgi_banner: String = _format_sdfgi_summary_banner(sdfgi_records)
	var fog_records: Array[Dictionary] = _audit_volumetric_fog_instances()
	var fog_banner: String = _format_volumetric_fog_summary_banner(fog_records)

	return (
		sdfgi_banner
		+ fog_banner
		+ "\n"
		+ (
			"""=== PRIMARY BOTTLENECK ===
Status: [%s] (%.2f ms | %.1f%% budget)

=== TIME BREAKDOWN ===
* GPU Passes          : %.2f ms
* CPU Process/Scripts : %.2f ms
* CPU Render Prep     : %.2f ms
* CPU Physics         : %.2f ms

=== DRAW CALL DISTRIBUTION ===
* Total Draw Calls    : %d (Target: < 600)
* Objects Drawn       : %d
* Primitives          : %d

=== PIPELINES & SHADER SPIKES ===
* Mesh Pipeline Comp  : %d
* Canvas Pipeline Comp: %d

=== 3D PHYSICS BROADPHASE ===
* Active Pairs        : %d
* Physics Islands     : %d

=== SCENE TREE HEALTH ===
* Active Nodes        : %d
* Orphan Nodes        : %d (Press [Scan Orphans] to dump)
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
				objects_drawn,
				primitives,
				pipe_mesh,
				pipe_canvas,
				phys_pairs,
				phys_islands,
				total_nodes,
				orphan_nodes,
			]
		)
	)


## Extracts active post-processing features on an [Environment] resource.
func _get_active_environment_effects(env: Environment) -> PackedStringArray:
	var active_effects: PackedStringArray = PackedStringArray()
	if not env:
		return active_effects

	if env.glow_enabled:
		active_effects.append("Glow")
	if env.sdfgi_enabled:
		active_effects.append("SDFGI")
	if env.ssao_enabled:
		active_effects.append("SSAO")
	if env.ssil_enabled:
		active_effects.append("SSIL")
	if env.ssr_enabled:
		active_effects.append("SSR")
	if env.volumetric_fog_enabled:
		active_effects.append("VolumetricFog")
	if env.fog_enabled:
		active_effects.append("Fog")
	if env.adjustment_enabled:
		active_effects.append("Adjustments")

	return active_effects


## Resolves active post-processing environment resource for a viewport.
func _detect_viewport_environment_effects(vp: Viewport) -> PackedStringArray:
	if vp is SubViewport:
		var sub_vp: SubViewport = vp
		if sub_vp.disable_3d:
			return PackedStringArray()

	var camera: Camera3D = vp.get_camera_3d()
	if is_instance_valid(camera) and camera.environment:
		return _get_active_environment_effects(camera.environment)

	if vp is SubViewport:
		var sub_vp_world: SubViewport = vp
		if not sub_vp_world.own_world_3d:
			return PackedStringArray()

	var world_3d: World3D = vp.find_world_3d()
	if is_instance_valid(world_3d) and world_3d.environment:
		return _get_active_environment_effects(world_3d.environment)

	return PackedStringArray()


## Formats detected environment effects with warning colors for BBCode.
func _format_effects_bbcode(effects: PackedStringArray) -> String:
	if effects.is_empty():
		return "[color=gray]None (Clean)[/color]"

	var colored_tokens: PackedStringArray = PackedStringArray()
	for eff: String in effects:
		colored_tokens.append("[color=red]%s[/color]" % eff)
	return ", ".join(colored_tokens)


## Formats a high-level SDFGI status summary banner for diagnostics reports.
func _format_sdfgi_summary_banner(records: Array[Dictionary]) -> String:
	var active_count: int = 0
	var dormant_count: int = 0
	for rec: Dictionary in records:
		var is_active_val: Variant = rec.get("is_active", false)
		if is_active_val is bool and is_active_val:
			active_count += 1
		else:
			dormant_count += 1

	if active_count > 1:
		return (
			"[color=red][b]SDFGI STATUS: [CRITICAL: %d ACTIVE COMPUTE CASCADES] (%d dormant)[/b][/color]\n"
			% [active_count, dormant_count]
		)
	if active_count == 1:
		var dormant_suffix: String = (" (%d dormant)" % dormant_count) if dormant_count > 0 else ""
		return "[color=green][b]SDFGI STATUS: 1 Active Compute%s[/b][/color]\n" % dormant_suffix
	if dormant_count > 0:
		return "[color=yellow]SDFGI STATUS: 0 Active (%d dormant in tree)[/color]\n" % dormant_count
	return "[color=gray]SDFGI STATUS: Off (0 active)[/color]\n"


## Audits scene tree and viewports for genuine active SDFGI compute cascades.
func _audit_sdfgi_instances() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.root):
		return results

	var root_vp: Window = tree.root
	var sub_viewports: Array[SubViewport] = []
	_collect_subviewports(root_vp, sub_viewports)

	var all_viewports: Array[Viewport] = [root_vp]
	for sub_vp: SubViewport in sub_viewports:
		all_viewports.append(sub_vp)

	var current_scene: Node = tree.current_scene

	for vp: Viewport in all_viewports:
		if not is_instance_valid(vp):
			continue

		var is_sub: bool = vp is SubViewport
		var sub_vp: SubViewport = vp as SubViewport if is_sub else null

		var is_active: bool = true
		var reason: String = "active"

		if is_sub:
			if sub_vp.disable_3d:
				is_active = false
				reason = "viewport disable_3d=true"
			elif sub_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
				is_active = false
				reason = "update_mode=DISABLED"
		else:
			var win_vp: Window = vp as Window
			if win_vp.disable_3d:
				is_active = false
				reason = "window disable_3d=true"

		var active_env: Environment = null
		var cam: Camera3D = vp.get_camera_3d()
		if is_instance_valid(cam) and is_instance_valid(cam.environment):
			active_env = cam.environment
		else:
			var w3d: World3D = vp.find_world_3d()
			if is_instance_valid(w3d) and is_instance_valid(w3d.environment):
				active_env = w3d.environment

		if not is_instance_valid(active_env) or not active_env.sdfgi_enabled:
			continue

		var display_name: String = ""
		if vp == root_vp:
			var scene_title: String = (
				current_scene.name if is_instance_valid(current_scene) else "root"
			)
			display_name = "Main Window [%s]" % scene_title
		else:
			display_name = "SubViewport [%s]" % str(vp.name)

		(
			results
			. append(
				{
					"name": display_name,
					"path": str(vp.get_path()),
					"cascades": active_env.sdfgi_cascades,
					"is_active": is_active,
					"reason": reason,
				}
			)
		)

	return results


## Formats a high-level Volumetric Fog status summary banner for diagnostics reports.
func _format_volumetric_fog_summary_banner(records: Array[Dictionary]) -> String:
	var active_count: int = 0
	var dormant_count: int = 0
	for rec: Dictionary in records:
		var is_active_val: Variant = rec.get("is_active", false)
		if is_active_val is bool and is_active_val:
			active_count += 1
		else:
			dormant_count += 1

	if active_count > 1:
		return (
			"[color=red][b]V-FOG STATUS: [CRITICAL: %d ACTIVE COMPUTE FROXELS] (%d dormant)[/b][/color]\n"
			% [active_count, dormant_count]
		)
	if active_count == 1:
		var dormant_suffix: String = (" (%d dormant)" % dormant_count) if dormant_count > 0 else ""
		return "[color=green][b]V-FOG STATUS: 1 Active Compute%s[/b][/color]\n" % dormant_suffix
	if dormant_count > 0:
		return "[color=yellow]V-FOG STATUS: 0 Active (%d dormant in tree)[/color]\n" % dormant_count
	return "[color=gray]V-FOG STATUS: Off (0 active)[/color]\n"


## Audits scene tree and viewports for genuine active volumetric fog froxel grids.
func _audit_volumetric_fog_instances() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.root):
		return results

	var root_vp: Window = tree.root
	var sub_viewports: Array[SubViewport] = []
	_collect_subviewports(root_vp, sub_viewports)

	var all_viewports: Array[Viewport] = [root_vp]
	for sub_vp: SubViewport in sub_viewports:
		all_viewports.append(sub_vp)

	var current_scene: Node = tree.current_scene

	for vp: Viewport in all_viewports:
		if not is_instance_valid(vp):
			continue

		var is_sub: bool = vp is SubViewport
		var sub_vp: SubViewport = vp as SubViewport if is_sub else null

		var is_active: bool = true
		var reason: String = "active"

		if is_sub:
			if sub_vp.disable_3d:
				is_active = false
				reason = "viewport disable_3d=true"
			elif sub_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
				is_active = false
				reason = "update_mode=DISABLED"
		else:
			var win_vp: Window = vp as Window
			if win_vp.disable_3d:
				is_active = false
				reason = "window disable_3d=true"

		var active_env: Environment = null
		var cam: Camera3D = vp.get_camera_3d()
		if is_instance_valid(cam) and is_instance_valid(cam.environment):
			active_env = cam.environment
		else:
			var w3d: World3D = vp.find_world_3d()
			if is_instance_valid(w3d) and is_instance_valid(w3d.environment):
				active_env = w3d.environment

		if not is_instance_valid(active_env) or not active_env.volumetric_fog_enabled:
			continue

		var display_name: String = ""
		if vp == root_vp:
			var scene_title: String = (
				current_scene.name if is_instance_valid(current_scene) else "root"
			)
			display_name = "Main Window [%s]" % scene_title
		else:
			display_name = "SubViewport [%s]" % str(vp.name)

		(
			results
			. append(
				{
					"name": display_name,
					"path": str(vp.get_path()),
					"density": active_env.volumetric_fog_density,
					"is_active": is_active,
					"reason": reason,
				}
			)
		)

	return results


## Generates hierarchical breakdown of active [SubViewport] nodes.
func _build_pipeline_report() -> String:
	var sdfgi_records: Array[Dictionary] = _audit_sdfgi_instances()
	var sdfgi_banner: String = _format_sdfgi_summary_banner(sdfgi_records)
	var fog_records: Array[Dictionary] = _audit_volumetric_fog_instances()
	var fog_banner: String = _format_volumetric_fog_summary_banner(fog_records)

	var text: String = (
		sdfgi_banner
		+ fog_banner
		+ "\n[b][color=yellow]=== VIEWPORT & RENDER PIPELINE ===[/color][/b]\n"
	)
	var root_vp: Window = get_tree().root
	var root_effects: PackedStringArray = _detect_viewport_environment_effects(root_vp)
	var root_effects_str: String = _format_effects_bbcode(root_effects)
	text += (
		"* %s (Root Window: %dx%d)\n  └─ Effects: %s\n\n"
		% [str(root_vp.name), root_vp.size.x, root_vp.size.y, root_effects_str]
	)

	text += "[b][color=yellow]=== ACTIVE SUBVIEWPORTS ===[/color][/b]\n"
	var sub_viewports: Array[SubViewport] = []
	_collect_subviewports(root_vp, sub_viewports)

	if sub_viewports.is_empty():
		text += "[color=gray]  No active SubViewports found in tree.[/color]\n"
	else:
		for vp: SubViewport in sub_viewports:
			var mode_idx: int = int(vp.render_target_update_mode)
			var mode_str: String = UPDATE_MODE_LABELS.get(mode_idx, "[color=red]ALWAYS[/color]")

			var vp_rid: RID = vp.get_viewport_rid()
			var sub_gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
			var vp_effects: PackedStringArray = _detect_viewport_environment_effects(vp)
			var vp_effects_str: String = _format_effects_bbcode(vp_effects)

			var fmt: String = (
				"* %s (%dx%d) -> Mode: %s | GPU: %.2f ms\n"
				+ "  ├─ Path: [color=cyan]%s[/color]\n  └─ Effects: %s\n"
			)
			text += (
				fmt
				% [
					str(vp.name),
					vp.size.x,
					vp.size.y,
					mode_str,
					sub_gpu_ms,
					str(vp.get_path()),
					vp_effects_str,
				]
			)

	text += "\n[b][color=yellow]=== SDFGI INSTANCE AUDIT ===[/color][/b]\n"
	if sdfgi_records.is_empty():
		text += "[color=gray]  No SDFGI-enabled environments detected in tree.[/color]\n"
	else:
		for rec: Dictionary in sdfgi_records:
			var name_str: String = str(rec.get("name", "Unknown"))
			var is_act_val: Variant = rec.get("is_active", false)
			var is_act: bool = is_act_val is bool and is_act_val
			var status_badge: String = (
				"[color=green][ACTIVE COMPUTE][/color]"
				if is_act
				else ("[color=yellow][DORMANT: %s][/color]" % str(rec.get("reason", "asleep")))
			)
			var cascades_val: Variant = rec.get("cascades", 0)
			var cascades: int = cascades_val if cascades_val is int else 0
			var path_str: String = str(rec.get("path", ""))
			text += (
				"* %s -> %s | %d Cascades\n  └─ Path: [color=cyan]%s[/color]\n"
				% [name_str, status_badge, cascades, path_str]
			)

	text += "\n[b][color=yellow]=== VOLUMETRIC FOG INSTANCE AUDIT ===[/color][/b]\n"
	if fog_records.is_empty():
		text += "[color=gray]  No Volumetric Fog environments detected in tree.[/color]\n"
	else:
		for rec: Dictionary in fog_records:
			var name_str: String = str(rec.get("name", "Unknown"))
			var is_act_val: Variant = rec.get("is_active", false)
			var is_act: bool = is_act_val is bool and is_act_val
			var status_badge: String = (
				"[color=green][ACTIVE COMPUTE][/color]"
				if is_act
				else ("[color=yellow][DORMANT: %s][/color]" % str(rec.get("reason", "asleep")))
			)
			var density_val: Variant = rec.get("density", 0.0)
			var density: float = density_val if density_val is float else 0.0
			var path_str: String = str(rec.get("path", ""))
			text += (
				"* %s -> %s | Density: %.4f\n  └─ Path: [color=cyan]%s[/color]\n"
				% [name_str, status_badge, density, path_str]
			)

	return text


## Recursively collects all [SubViewport] instances inside a parent node.
func _collect_subviewports(current_node: Node, out_viewports: Array[SubViewport]) -> void:
	if current_node is SubViewport:
		out_viewports.append(current_node)

	for child: Node in current_node.get_children(true):
		_collect_subviewports(child, out_viewports)


## Triggers geometry scan when user clicks the audit button.
func _on_scan_geometry_pressed() -> void:
	print("RenderDiagnosticsPanel: Triggering scene hierarchy scan.")
	scan_scene_geometry()


## Triggers orphan node scan when user clicks the scan orphans button.
func _on_scan_orphans_pressed() -> void:
	print("RenderDiagnosticsPanel: Triggering orphan node scan.")
	scan_orphan_nodes()


## Toggles rendering cull mask to isolate base rendering layer.
func _on_live_isolator_pressed() -> void:
	_is_isolating_layers = not _is_isolating_layers
	var state_str: String = "on" if _is_isolating_layers else "off"
	print("RenderDiagnosticsPanel: Live isolator %s" % state_str)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(cam):
		if _is_isolating_layers:
			cam.cull_mask = 1
		else:
			cam.cull_mask = 0xFFFFF


func _on_dump_audit_pressed() -> void:
	print("RenderDiagnosticsPanel: Dump audit triggered.")
	scan_scene_geometry()
	var report: String = _build_performance_report()
	print(report)
	print(_build_pipeline_report())
	if is_instance_valid(survey_label):
		print(_cached_branch_survey)
	Node.print_orphan_nodes()


## Toggles diorama mode hiding background nodes outside player and world.
func _on_diorama_pressed() -> void:
	_is_diorama_active = not _is_diorama_active
	var state_str: String = "on" if _is_diorama_active else "off"
	print("RenderDiagnosticsPanel: Diorama %s" % state_str)
	var current_scene: Node = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return
	for child: Node in current_scene.get_children():
		if child is Node3D and child.name != &"Player" and child.name != &"Environment":
			var node_3d: Node3D = child
			node_3d.visible = not _is_diorama_active


## Cycles through the 5-step glitch triage and buffer flush state machine.
func _on_triage_glitch_pressed() -> void:
	_triage_step = (_triage_step + 1) % 5
	print("RenderDiagnosticsPanel: Triage Glitch step -> ", _triage_step)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b][color=yellow]=== DIAGONAL GLITCH TRIAGE ===[/color][/b]")

	match _triage_step:
		1:
			if is_instance_valid(triage_glitch_button):
				triage_glitch_button.text = "Triage: 1.Flushed"
			_flush_render_and_cloud_buffers(lines)
		2:
			if is_instance_valid(triage_glitch_button):
				triage_glitch_button.text = "Triage: 2.NoClouds"
			_set_clouds_compositor_state(false, lines)
		3:
			if is_instance_valid(triage_glitch_button):
				triage_glitch_button.text = "Triage: 3.NoOcean"
			_set_clouds_compositor_state(true, lines)
			_set_water_and_particles_state(false, lines)
		4:
			if is_instance_valid(triage_glitch_button):
				triage_glitch_button.text = "Triage: 4.NoOverlay"
			_set_water_and_particles_state(true, lines)
			_set_screen_effects_state(false, lines)
		_:
			if is_instance_valid(triage_glitch_button):
				triage_glitch_button.text = "Triage Glitch"
			_set_clouds_compositor_state(true, lines)
			_set_water_and_particles_state(true, lines)
			_set_screen_effects_state(true, lines)
			lines.append("[color=green]Step 0: All visual subsystems restored.[/color]")

	_cached_branch_survey = "\n".join(lines) + "\n"
	_apply_survey_to_ui()


## Forces reallocation of viewport history buffers and cloud compute textures.
func _flush_render_and_cloud_buffers(lines: PackedStringArray) -> void:
	print("RenderDiagnosticsPanel: Flushing VRAM history and cloud buffers.")
	lines.append("[color=cyan]Step 1: Flushing VRAM History & Cloud Buffers[/color]")

	var clouds_fx: CompositorEffect = _find_clouds_compositor_effect()
	if is_instance_valid(clouds_fx):
		clouds_fx.set(&"ignore_accumilation", true)
		if clouds_fx.has_method(&"refresh_compute"):
			clouds_fx.call(&"refresh_compute")
		lines.append("  |- SunshineCloudsGD: Reallocated compute storage RIDs.")
	else:
		lines.append("  |- SunshineCloudsGD: No active compositor found.")

	var vp: Viewport = get_viewport()
	var orig_taa: bool = vp.use_taa
	var orig_scale: float = vp.scaling_3d_scale
	vp.use_taa = false
	vp.scaling_3d_scale = clampf(orig_scale - 0.01, 0.5, 1.0)
	lines.append("  |- Viewport Buffers: Triggered 1-frame scale jitter & TAA reset.")
	lines.append(
		"  [i]If the diagonal lines vanished, history buffer NaN poisoning was the cause![/i]"
	)

	await get_tree().process_frame
	if is_instance_valid(vp):
		vp.scaling_3d_scale = orig_scale
		vp.use_taa = orig_taa


## Enables or disables the SunshineCloudsGD [CompositorEffect] at runtime.
func _set_clouds_compositor_state(is_active: bool, lines: PackedStringArray) -> void:
	print("RenderDiagnosticsPanel: Setting clouds compositor -> ", is_active)
	var clouds_fx: CompositorEffect = _find_clouds_compositor_effect()
	if is_instance_valid(clouds_fx):
		clouds_fx.enabled = is_active
		if is_active and clouds_fx.has_method(&"refresh_compute"):
			clouds_fx.call(&"refresh_compute")
		var status: String = "ENABLED" if is_active else "DISABLED"
		lines.append("  |- SunshineCloudsGD Compositor: [b]%s[/b]" % status)
	else:
		lines.append("  |- SunshineCloudsGD Compositor: Not present in scene.")


## Hides or restores ocean meshes, water bodies, and GPU splash particles.
func _set_water_and_particles_state(is_active: bool, lines: PackedStringArray) -> void:
	print("RenderDiagnosticsPanel: Setting water/particles -> ", is_active)
	if is_active:
		var restored_count: int = 0
		for node: Node3D in _triage_muted_nodes:
			if is_instance_valid(node):
				node.visible = true
				restored_count += 1
		_triage_muted_nodes.clear()
		lines.append("  |- Ocean / Water / Particles: Restored %d nodes." % restored_count)
		return

	_triage_muted_nodes.clear()
	var current_scene: Node = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return

	var stack: Array[Node] = [current_scene]
	while not stack.is_empty():
		var curr: Node = stack.pop_back()
		if curr is Node3D:
			var n3d: Node3D = curr
			var n_low: String = str(n3d.name).to_lower()
			var is_suspect: bool = "ocean" in n_low or "water" in n_low or n3d is GPUParticles3D
			if is_suspect and n3d.visible:
				n3d.visible = false
				_triage_muted_nodes.append(n3d)
		for child: Node in curr.get_children():
			stack.append(child)

	lines.append(
		(
			"  |- Ocean / Water / GPUParticles3D: Muted [b]%d[/b] visible nodes."
			% _triage_muted_nodes.size()
		)
	)


## Toggles visibility on the [ScreenEffectsManager] fullscreen overlay node.
func _set_screen_effects_state(is_active: bool, lines: PackedStringArray) -> void:
	print("RenderDiagnosticsPanel: Setting ScreenEffectsManager -> ", is_active)
	var root_vp: Window = get_tree().root
	var fx_mgr: Control = null
	var group_fx: Node = get_tree().get_first_node_in_group(&"screen_effects_manager")
	if group_fx is Control:
		fx_mgr = group_fx as Control
	else:
		var direct_fx: Node = root_vp.get_node_or_null("ScreenEffectsManager")
		if direct_fx is Control:
			fx_mgr = direct_fx as Control

	if is_instance_valid(fx_mgr):
		fx_mgr.visible = is_active
		var status: String = "VISIBLE" if is_active else "MUTED"
		lines.append("  |- ScreenEffectsManager Overlays: [b]%s[/b]" % status)
	else:
		lines.append("  |- ScreenEffectsManager: Node not found.")


## Locates the active SunshineCloudsGD [CompositorEffect] in the scene.
func _find_clouds_compositor_effect() -> CompositorEffect:
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d()
	if is_instance_valid(cam) and is_instance_valid(cam.compositor):
		for fx: CompositorEffect in cam.compositor.compositor_effects:
			if is_instance_valid(fx):
				return fx

	var current_scene: Node = get_tree().current_scene
	if is_instance_valid(current_scene):
		var world_env: WorldEnvironment = _resolve_world_environment(current_scene)
		if is_instance_valid(world_env) and is_instance_valid(world_env.compositor):
			for fx: CompositorEffect in world_env.compositor.compositor_effects:
				if is_instance_valid(fx):
					return fx

	return null


## Resolves [WorldEnvironment] from scene root without recursive searches.
func _resolve_world_environment(scene_root: Node) -> WorldEnvironment:
	if scene_root is WorldEnvironment:
		return scene_root as WorldEnvironment

	var direct_env: Node = scene_root.get_node_or_null("WorldEnvironment")
	if direct_env is WorldEnvironment:
		return direct_env as WorldEnvironment

	for child: Node in scene_root.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment

	return null


## Finds the active [Environment] on camera, world, or WorldEnvironment node.
func _get_active_environment() -> Environment:
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d()
	if is_instance_valid(cam) and cam.environment:
		return cam.environment

	var world_3d: World3D = vp.find_world_3d()
	if is_instance_valid(world_3d) and world_3d.environment:
		return world_3d.environment

	var current_scene: Node = get_tree().current_scene
	if is_instance_valid(current_scene):
		var world_env: WorldEnvironment = _resolve_world_environment(current_scene)
		if is_instance_valid(world_env) and world_env.environment:
			return world_env.environment

	return null


## Checks if any child [Light3D] node currently casts shadows.
func _are_any_shadows_enabled(root_node: Node) -> bool:
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var curr: Node = stack.pop_back()
		if curr is Light3D:
			var light_node: Light3D = curr
			if light_node.shadow_enabled:
				return true
		for child: Node in curr.get_children():
			stack.append(child)
	return false


## Synchronizes button text states with active environment settings.
func sync_toggle_button_labels() -> void:
	print("RenderDiagnosticsPanel: Synchronizing toggle buttons.")
	var env: Environment = _get_active_environment()

	if is_instance_valid(sdfgi_toggle_button):
		var records: Array[Dictionary] = _audit_sdfgi_instances()
		var active_count: int = 0
		for rec: Dictionary in records:
			var is_active_val: Variant = rec.get("is_active", false)
			if is_active_val is bool and is_active_val:
				active_count += 1

		if active_count > 1:
			sdfgi_toggle_button.text = "SDFGI (%d ACTIVE!)" % active_count
		elif active_count == 1:
			sdfgi_toggle_button.text = "SDFGI on"
		else:
			var is_sdfgi: bool = env.sdfgi_enabled if is_instance_valid(env) else false
			sdfgi_toggle_button.text = "SDFGI %s" % ("on" if is_sdfgi else "off")

	if is_instance_valid(fog_toggle_button):
		var fog_records: Array[Dictionary] = _audit_volumetric_fog_instances()
		var fog_active_count: int = 0
		for rec: Dictionary in fog_records:
			var is_active_val: Variant = rec.get("is_active", false)
			if is_active_val is bool and is_active_val:
				fog_active_count += 1

		if fog_active_count > 1:
			fog_toggle_button.text = "Fog (%d ACTIVE!)" % fog_active_count
		elif fog_active_count == 1:
			fog_toggle_button.text = "Fog on"
		else:
			var is_fog: bool = false
			if is_instance_valid(env):
				is_fog = env.fog_enabled or env.volumetric_fog_enabled
			fog_toggle_button.text = "Fog %s" % ("on" if is_fog else "off")

	if is_instance_valid(shadows_toggle_button):
		var curr_scene: Node = get_tree().current_scene
		var has_shadows: bool = _are_any_shadows_enabled(curr_scene) if curr_scene else false
		shadows_toggle_button.text = ("Shadows %s" % ("on" if has_shadows else "off"))


## Toggles shadow casting across all scene lights.
func _on_shadows_toggled() -> void:
	var current_scene: Node = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return

	var any_shadows_active: bool = _are_any_shadows_enabled(current_scene)
	var target_state: bool = not any_shadows_active
	var stack: Array[Node] = [current_scene]

	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Light3D:
			var light_node: Light3D = node
			light_node.shadow_enabled = target_state
		for child: Node in node.get_children():
			stack.append(child)

	var state_str: String = "on" if target_state else "off"
	print("RenderDiagnosticsPanel: Shadows %s" % state_str)
	if is_instance_valid(shadows_toggle_button):
		shadows_toggle_button.text = "Shadows %s" % state_str
	_refresh_diagnostics_display()


## Toggles signed distance field global illumination on the environment.
func _on_sdfgi_toggled() -> void:
	var env: Environment = _get_active_environment()
	if not env:
		print("RenderDiagnosticsPanel: SDFGI off (no active environment)")
		if is_instance_valid(sdfgi_toggle_button):
			sdfgi_toggle_button.text = "SDFGI off"
		return

	env.sdfgi_enabled = not env.sdfgi_enabled
	var state_str: String = "on" if env.sdfgi_enabled else "off"
	print("RenderDiagnosticsPanel: SDFGI %s" % state_str)
	sync_toggle_button_labels()
	_refresh_diagnostics_display()


## Toggles distance fog and volumetric fog on the active environment.
func _on_fog_toggled() -> void:
	var env: Environment = _get_active_environment()
	if not env:
		print("RenderDiagnosticsPanel: Fog off (no active environment)")
		if is_instance_valid(fog_toggle_button):
			fog_toggle_button.text = "Fog off"
		return

	var new_state: bool = not (env.fog_enabled or env.volumetric_fog_enabled)
	env.fog_enabled = new_state
	env.volumetric_fog_enabled = new_state
	var state_str: String = "on" if new_state else "off"
	print("RenderDiagnosticsPanel: Fog %s" % state_str)
	sync_toggle_button_labels()
	_refresh_diagnostics_display()


## Cycles viewport debug modes between wireframe, overdraw, and unshaded.
func cycle_debug_draw_mode() -> void:
	var vp: Viewport = get_viewport()
	match vp.debug_draw:
		Viewport.DEBUG_DRAW_DISABLED:
			vp.debug_draw = Viewport.DEBUG_DRAW_OVERDRAW
			print("RenderDiagnosticsPanel: Debug draw -> OVERDRAW")
		Viewport.DEBUG_DRAW_OVERDRAW:
			vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
			print("RenderDiagnosticsPanel: Debug draw -> UNSHADED")
		Viewport.DEBUG_DRAW_UNSHADED:
			vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
			print("RenderDiagnosticsPanel: Debug draw -> WIREFRAME")
		_:
			vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
			print("RenderDiagnosticsPanel: Debug draw -> DISABLED")
