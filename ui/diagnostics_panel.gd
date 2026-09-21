## Manages runtime rendering diagnostics, bottleneck identification, and draw call breakdown.
class_name RenderDiagnosticsPanel
extends PanelContainer

@warning_ignore("unused_signal")
## Emitted when diagnostic metrics refresh. Passes snapshot data [Dictionary].
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

## RichTextLabel displaying real-time formatted diagnostics.
@onready var diagnostics_label: RichTextLabel = %DiagnosticsLabel

## Button switching view to viewport and canvas layer hierarchy.
@onready var subviewports_tab_button: Button = %SubViewportsTabButton

## Button switching view to performance monitors.
@onready var perf_tab_button: Button = %PerfTabButton

## Button triggering an explicit one-off scene geometry scan.
@onready var scan_geometry_button: Button = %ScanGeometryButton

## Dedicated RichTextLabel for static geometry snapshot.
@onready var survey_label: RichTextLabel = %SurveyLabel if has_node("%SurveyLabel") else null

## Button toggling live layer isolation.
@onready
var live_isolator_button: Button = %LiveIsolatorButton if has_node("%LiveIsolatorButton") else null

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


## Connects UI signals, sets constraints, and initializes measuring.
func _ready() -> void:
	print("RenderDiagnosticsPanel: Initializing diagnostic hooks.")
	visible = false
	_apply_layout_constraints()
	get_viewport().size_changed.connect(_apply_layout_constraints)

	subviewports_tab_button.pressed.connect(_on_pipeline_tab_pressed)
	perf_tab_button.pressed.connect(_on_perf_tab_pressed)
	scan_geometry_button.pressed.connect(_on_scan_geometry_pressed)

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

	_update_tab_button_visuals()

	if OS.has_feature("debug"):
		_init_csv_logging()

	var vp_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
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


## Initializes desktop CSV file handle only in debug builds.
func _init_csv_logging() -> void:
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
	_current_tab = DiagnosticTab.PIPELINE
	_update_tab_button_visuals()
	_refresh_diagnostics_display()


## Switches active tab to performance monitors.
func _on_perf_tab_pressed() -> void:
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
	var needs_process: bool = visible or (_csv_file != null and OS.has_feature("debug"))
	set_process(needs_process)


## Accumulates delta time, logs hitches, and flushes CSV buffer.
func _process(delta: float) -> void:
	var has_logger: bool = _csv_file != null and OS.has_feature("debug")

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
	print("RenderDiagnosticsPanel: Auditing branch geometry for ", root_node.name)
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
				if curr.visible and curr.is_inside_tree():
					branch_meshes += 1
			elif curr is MultiMeshInstance3D:
				if curr.visible and curr.is_inside_tree() and curr.multimesh:
					branch_multis += curr.multimesh.instance_count
			elif curr is Light3D:
				if curr.visible and curr.shadow_enabled:
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


## Updates the survey label with cached scene hierarchy text.
func _apply_survey_to_ui() -> void:
	if is_instance_valid(survey_label):
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

	var is_gpu: bool = gpu_ms > total_cpu_ms
	var max_time: float = gpu_ms if is_gpu else total_cpu_ms
	var budget_pct: float = (max_time / TARGET_FRAME_BUDGET_MS) * 100.0

	return (
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
			phys_islands
		]
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
	if vp is SubViewport and (vp as SubViewport).disable_3d:
		return PackedStringArray()

	var camera: Camera3D = vp.get_camera_3d()
	if is_instance_valid(camera) and camera.environment:
		return _get_active_environment_effects(camera.environment)

	if vp is SubViewport and not (vp as SubViewport).own_world_3d:
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


## Generates hierarchical breakdown of active SubViewports.
func _build_pipeline_report() -> String:
	var text: String = "[b][color=yellow]=== VIEWPORT & RENDER PIPELINE ===[/color][/b]\n"
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

			var vp_rid: RID = vp.get_viewport_rid()
			var sub_gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
			var vp_effects: PackedStringArray = _detect_viewport_environment_effects(vp)
			var vp_effects_str: String = _format_effects_bbcode(vp_effects)

			text += (
				"* %s (%dx%d) -> Mode: %s | GPU: %.2f ms\n  ├─ Path: [color=cyan]%s[/color]\n  └─ Effects: %s\n"
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

	return text


## Recursively collects all SubViewport instances inside a parent node.
func _collect_subviewports(current_node: Node, out_viewports: Array[SubViewport]) -> void:
	if current_node is SubViewport:
		out_viewports.append(current_node)

	for child: Node in current_node.get_children(true):
		_collect_subviewports(child, out_viewports)


## Triggers geometry scan when user clicks the audit button.
func _on_scan_geometry_pressed() -> void:
	print("RenderDiagnosticsPanel: Triggering scene hierarchy scan.")
	scan_scene_geometry()


## Toggles rendering cull mask to isolate base rendering layer.
func _on_live_isolator_pressed() -> void:
	_is_isolating_layers = not _is_isolating_layers
	var state_str: String = "on" if _is_isolating_layers else "off"
	print("live isolator %s" % state_str)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(cam):
		if _is_isolating_layers:
			cam.cull_mask = 1
		else:
			cam.cull_mask = 0xFFFFF


## Dumps scene tree and performance metrics to debugger console.
func _on_dump_audit_pressed() -> void:
	print("dump audit triggered")
	scan_scene_geometry()
	var report: String = _build_performance_report()
	print(report)
	if is_instance_valid(survey_label):
		print(_cached_branch_survey)


## Toggles diorama mode hiding background nodes outside player and world.
func _on_diorama_pressed() -> void:
	_is_diorama_active = not _is_diorama_active
	var state_str: String = "on" if _is_diorama_active else "off"
	print("diorama %s" % state_str)
	var current_scene: Node = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return
	for child: Node in current_scene.get_children():
		if child is Node3D and child.name != "Player" and child.name != "Environment":
			(child as Node3D).visible = not _is_diorama_active


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
		var world_env: WorldEnvironment = (
			current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
		)
		if is_instance_valid(world_env) and world_env.environment:
			return world_env.environment

	return null


## Checks if any child Light3D node currently casts shadows.
func _are_any_shadows_enabled(root_node: Node) -> bool:
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var curr: Node = stack.pop_back()
		if curr is Light3D and (curr as Light3D).shadow_enabled:
			return true
		for child: Node in curr.get_children():
			stack.append(child)
	return false


## Synchronizes button text states with active environment settings.
func sync_toggle_button_labels() -> void:
	print("RenderDiagnosticsPanel: Synchronizing toggle buttons.")
	var env: Environment = _get_active_environment()

	if is_instance_valid(sdfgi_toggle_button):
		var is_sdfgi: bool = env.sdfgi_enabled if is_instance_valid(env) else false
		sdfgi_toggle_button.text = "SDFGI %s" % ("on" if is_sdfgi else "off")

	if is_instance_valid(fog_toggle_button):
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
			(node as Light3D).shadow_enabled = target_state
		for child: Node in node.get_children():
			stack.append(child)

	var state_str: String = "on" if target_state else "off"
	print("shadows %s" % state_str)
	if is_instance_valid(shadows_toggle_button):
		shadows_toggle_button.text = "Shadows %s" % state_str
	_refresh_diagnostics_display()


## Toggles signed distance field global illumination on the environment.
func _on_sdfgi_toggled() -> void:
	var env: Environment = _get_active_environment()
	if not env:
		print("sdfgi off")
		if is_instance_valid(sdfgi_toggle_button):
			sdfgi_toggle_button.text = "SDFGI off"
		return

	env.sdfgi_enabled = not env.sdfgi_enabled
	var state_str: String = "on" if env.sdfgi_enabled else "off"
	print("SDFGI %s" % state_str)
	if is_instance_valid(sdfgi_toggle_button):
		sdfgi_toggle_button.text = "SDFGI %s" % state_str
	_refresh_diagnostics_display()


## Toggles distance fog and volumetric fog on the active environment.
func _on_fog_toggled() -> void:
	var env: Environment = _get_active_environment()
	if not env:
		print("fog off")
		if is_instance_valid(fog_toggle_button):
			fog_toggle_button.text = "Fog off"
		return

	var new_state: bool = not (env.fog_enabled or env.volumetric_fog_enabled)
	env.fog_enabled = new_state
	env.volumetric_fog_enabled = new_state
	var state_str: String = "on" if new_state else "off"
	print("fog %s" % state_str)
	if is_instance_valid(fog_toggle_button):
		fog_toggle_button.text = "Fog %s" % state_str
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
