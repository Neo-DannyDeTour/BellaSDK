## An on-screen developer metrics overlay used for diagnosing performance bottlenecks.
##
## [DevMetricsPanel] captures hardware specifications, tracks CPU/GPU frame times,
## and pulls player state data into a real-time HUD.
class_name DevMetricsPanel
extends PanelContainer

## The number of frames to store for rolling average calculations.
const HISTORY_NUM_FRAMES: int = 150

@export_category("Dev Metrics")
## Toggles whether the metrics system actively calculates values.
@export var is_enabled: bool = true

## Reference to the main [CharacterBody3D] player for state tracking.
var player: CharacterBody3D = null

## Timestamp of the previous frame in microseconds.
var _last_tick: int = 0
## Rolling history array of total frame delta times.
var _total_history: Array[float] = []
## Rolling history array of CPU frame times.
var _cpu_history: Array[float] = []
## Rolling history array of GPU frame times.
var _gpu_history: Array[float] = []

## Rolling sum of total frame delta times.
var _total_sum: float = 0.0
## Rolling sum of CPU frame times.
var _cpu_sum: float = 0.0
## Rolling sum of GPU frame times.
var _gpu_sum: float = 0.0

## Cached hardware strings to prevent recreating strings every frame.
var _hardware_info_str: String = ""
## Cached static graphics settings strings.
var _settings_info_static_str: String = ""

@onready var metrics_label: RichTextLabel = $MetricsLabel


## Called when the node enters the scene tree for the first time.
## Caches hardware info and enables rendering measurement overrides.
func _ready() -> void:
	print("DebugPanel: Initializing and caching hardware info.")
	visible = false

	player = get_tree().get_first_node_in_group("player") as CharacterBody3D

	metrics_label.bbcode_enabled = true
	metrics_label.add_theme_color_override("font_outline_color", Color.BLACK)
	metrics_label.add_theme_constant_override("outline_size", 4)

	# Enable hardware rendering time measurements
	var vp_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)

	_cache_hardware_info()
	_cache_static_settings_info()


## Called every frame to sample performance data and update the label UI.
## [param _delta] The time elapsed since the previous frame in seconds.
func _process(_delta: float) -> void:
	if not visible or not player:
		return

	_update_frametime_history()

	var fps: float = Engine.get_frames_per_second()
	var vel: Vector3 = player.velocity
	var speed: float = vel.length()

	var fps_color: String = "green"
	if fps >= 60.0:
		fps_color = "green"
	elif fps >= 30.0:
		fps_color = "yellow"
	else:
		fps_color = "red"

	var current_input: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	var is_pressing_keys: bool = current_input.length() > 0.1

	var state: String = "UNKNOWN"
	var sys_menu: Variant = player.get("system_menu")
	var fsm: Variant = player.get("state_machine")

	if sys_menu and sys_menu.get("flying"):
		state = "NOCLIP"
	elif fsm and fsm.get("state"):
		state = String(fsm.state.name).to_upper()
		if state == "GROUND":
			var loco: Variant = player.get("locomotion_component")
			if is_instance_valid(loco):
				if loco.get("crouching"):
					state = "CROUCH WALKING" if is_pressing_keys else "CROUCH IDLE"
				elif loco.get("sprint_active"):
					state = "SPRINTING"
				elif is_pressing_keys:
					state = "WALKING"
				else:
					state = "IDLE"

	var static_mem: int = OS.get_static_memory_usage()
	var vram_usage: int = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	var flashlight_str: String = "OFF"
	if is_instance_valid(player):
		var f_ctrl: Variant = player.get("flashlight_controller")
		if is_instance_valid(f_ctrl):
			if is_instance_valid(f_ctrl.flashlight):
				flashlight_str = "ON" if f_ctrl.flashlight.visible else "OFF"

	var weapon_str: String = "NONE"
	var weapon_holder: Node = player.get_node_or_null("%WeaponHolder")
	if weapon_holder and weapon_holder.get_child_count() > 0:
		weapon_str = weapon_holder.get_child(0).name

	# --- TEXT ASSEMBLY ---
	var text: String = ""
	text += "[color=%s][b]%d FPS[/b][/color]\n\n" % [fps_color, int(fps)]

	# Use a BBCode table to align the frametime data perfectly
	text += "[table=5]\n"
	text += "[cell][/cell][cell] [color=gray]Average[/color] [/cell]"
	text += "[cell] [color=gray]Best[/color] [/cell]"
	text += "[cell] [color=gray]Worst[/color] [/cell][cell] [color=gray]Last[/color] [/cell]\n"

	text += _format_metric_row("Total:", _total_sum, _total_history)
	text += _format_metric_row("CPU:", _cpu_sum, _cpu_history)
	text += _format_metric_row("GPU:", _gpu_sum, _gpu_history)
	text += "[/table]\n"

	# Append the cached hardware + dynamic settings
	text += "[color=gray]" + _hardware_info_str + _settings_info_static_str
	text += _get_dynamic_settings_string() + "[/color]\n"

	text += "\n[color=gray]--- MEMORY & RENDERING ---[/color]\n"
	text += "RAM: %s\n" % String.humanize_size(static_mem)
	text += "VRAM: %s\n" % String.humanize_size(vram_usage)
	text += "Draw Calls: %d\n" % draw_calls
	text += "Objects: %d\n" % objects
	text += "Primitives: %d\n" % primitives

	text += "\n[color=gray]--- PLAYER STATE ---[/color]\n"
	text += "STATE: %s\n" % state
	text += "WEAPON: %s\n" % weapon_str
	text += "SPEED: %.2f m/s\n" % speed
	text += "POS: %s\n" % var_to_str(player.global_position).replace("Vector3", "")
	text += "GROUNDED: %s\n" % ("YES" if player.is_on_floor() else "NO")
	text += "FLASHLIGHT: %s\n" % flashlight_str

	metrics_label.text = text


## Toggles the visual state of the metrics panel on and off.
func toggle_window() -> void:
	visible = not visible
	print("DebugPanel: Visibility toggled to ", visible)


## Samples the current frametime from the [RenderingServer] and pushes it into the history arrays.
func _update_frametime_history() -> void:
	var current_tick: int = Time.get_ticks_usec()
	var frametime_total: float = (current_tick - _last_tick) * 0.001
	_last_tick = current_tick

	var vp_rid: RID = get_viewport().get_viewport_rid()
	var frame_setup: float = RenderingServer.get_frame_setup_time_cpu()
	var frametime_cpu: float = (
		RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + frame_setup
	)
	var frametime_gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)

	_total_sum += frametime_total
	_total_history.push_back(frametime_total)
	if _total_history.size() > HISTORY_NUM_FRAMES:
		_total_sum -= _total_history.pop_front()

	_cpu_sum += frametime_cpu
	_cpu_history.push_back(frametime_cpu)
	if _cpu_history.size() > HISTORY_NUM_FRAMES:
		_cpu_sum -= _cpu_history.pop_front()

	_gpu_sum += frametime_gpu
	_gpu_history.push_back(frametime_gpu)
	if _gpu_history.size() > HISTORY_NUM_FRAMES:
		_gpu_sum -= _gpu_history.pop_front()


## Formats a metric category into a clean BBCode table row string.
## [param title] The name of the metric (e.g. "CPU:").
## [param sum_val] The current rolling sum of the metric.
## [param history] The array containing the history of the metric.
func _format_metric_row(title: String, sum_val: float, history: Array[float]) -> String:
	if history.is_empty():
		return ""

	# Explicitly cast to float to prevent Godot string formatting errors with Variants
	var avg_val: float = float(sum_val) / float(history.size())
	var min_val: float = float(history.min())
	var max_val: float = float(history.max())
	var last_val: float = float(history.back())

	var row_format: String = (
		"[cell]%s [/cell][cell][color=%s]%.2f[/color][/cell]"
		+ "[cell][color=%s]%.2f[/color][/cell][cell][color=%s]%.2f[/color][/cell]"
		+ "[cell][color=%s]%.2f[/color][/cell]\n"
	)

	return (
		row_format
		% [
			title,
			_get_ms_color(avg_val),
			avg_val,
			_get_ms_color(min_val),
			min_val,
			_get_ms_color(max_val),
			max_val,
			_get_ms_color(last_val),
			last_val
		]
	)


## Returns a hex color string based on how fast a millisecond timing is.
## [param ms] The time in milliseconds.
func _get_ms_color(ms: float) -> String:
	if ms < 8.34:
		return "#38bdf8"
	if ms < 16.67:
		return "#80e25f"
	if ms < 33.34:
		return "#facc15"
	return "#ef4444"


## Queries the [OS] and [RenderingServer] once on load to build hardware information strings.
func _cache_hardware_info() -> void:
	var cpu_name: String = OS.get_processor_name().replace("(R)", "").replace("(TM)", "")
	var threads: int = OS.get_processor_count()
	var os_name: String = OS.get_name()
	var bitness: String = "64-bit" if OS.has_feature("64") else "32-bit"

	var gpu_name: String = RenderingServer.get_video_adapter_name().trim_suffix("/PCIe/SSE2")
	var api_ver: String = RenderingServer.get_video_adapter_api_version()

	var driver: String = str(ProjectSettings.get_setting("rendering/rendering_device/driver"))
	var api_str: String = "Vulkan" if driver == "vulkan" else driver.capitalize()

	_hardware_info_str = (
		"%s, %d threads\n%s %s, %s %s\n%s\n"
		% [cpu_name, threads, os_name, bitness, api_str, api_ver, gpu_name]
	)


## Queries [ProjectSettings] to build strings for non-dynamic graphics settings.
func _cache_static_settings_info() -> void:
	_settings_info_static_str = ""
	var method: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	var method_str: String = "Forward+" if method == "forward_plus" else method.capitalize()
	_settings_info_static_str += "Rendering Method: %s\n" % method_str


## Checks the current active viewport to build strings for dynamic graphics settings.
func _get_dynamic_settings_string() -> String:
	var dyn_str: String = ""
	var vp: Viewport = get_viewport()
	var win: Window = get_window()

	dyn_str += "Viewport: %dx%d\n" % [win.size.x, win.size.y]

	var fsr_str: String = "Disabled"
	if vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2:
		fsr_str = "FSR2 (Scale: %.2f)" % vp.scaling_3d_scale
	elif vp.scaling_3d_scale < 1.0:
		fsr_str = "Bilinear (Scale: %.2f)" % vp.scaling_3d_scale
	dyn_str += "FSR/Scaling: %s\n" % fsr_str

	var aa_str: String = "Disabled"
	if vp.msaa_3d != Viewport.MSAA_DISABLED:
		aa_str = "MSAA"
	if vp.use_taa:
		aa_str += " + TAA"
	if vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA:
		aa_str = "FXAA"
	dyn_str += "Anti-Aliasing: %s\n" % aa_str

	var cam: Camera3D = vp.get_camera_3d()
	if cam and cam.get_world_3d() and cam.get_world_3d().environment:
		var env: Environment = cam.get_world_3d().environment
		dyn_str += "SSR: %s\n" % ("On" if env.ssr_enabled else "Off")
		dyn_str += "SSAO: %s\n" % ("On" if env.ssao_enabled else "Off")
		dyn_str += "SSIL: %s\n" % ("On" if env.ssil_enabled else "Off")
		var sdfgi_str: String = "On (%d Cascades)" % env.sdfgi_cascades
		dyn_str += "SDFGI: %s\n" % (sdfgi_str if env.sdfgi_enabled else "Off")
		dyn_str += "Glow: %s\n" % ("On" if env.glow_enabled else "Off")
		dyn_str += "Volumetric Fog: %s\n" % ("On" if env.volumetric_fog_enabled else "Off")

	dyn_str += "Shadow Atlas Size: %d\n" % vp.positional_shadow_atlas_size
	dyn_str += "Mesh LOD Threshold: %.2f\n" % vp.mesh_lod_threshold

	return dyn_str
