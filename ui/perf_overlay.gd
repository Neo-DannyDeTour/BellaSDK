## Displays live performance diagnostics (FPS, CPU/GPU ms, Headroom, VRAM) overlaid on viewport.
class_name DioramaPerfOverlay
extends MarginContainer

## Interval in seconds between diagnostic string refreshes.
const UPDATE_INTERVAL: float = 0.25

## Target frame time budget for locked 60 FPS in milliseconds.
const TARGET_FRAME_BUDGET_MS: float = 16.67

## Label displaying formatted performance metrics.
@onready var stats_label: Label = %StatsLabel

## Dedicated timer driving periodic diagnostic metric refreshes.
var _refresh_timer: Timer = null

## Stored previous FPS metric value to prevent redundant text rebuilds.
var _last_fps: int = -1

## Stored previous CPU time in milliseconds.
var _last_cpu_ms: float = -1.0

## Stored previous GPU time in milliseconds.
var _last_gpu_ms: float = -1.0

## Stored previous VRAM metric value in megabytes.
var _last_vram_mb: float = -1.0


## Lifecycle initialization configuring anchors and starting diagnostics.
func _ready() -> void:
	print("UI: Initializing Diorama Performance Overlay.")
	set_process(false)
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 10.0
	offset_bottom = 30.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(stats_label):
		stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var vp: Viewport = get_viewport()
	if is_instance_valid(vp):
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)

	_setup_refresh_timer()
	_update_metrics()


## Instantiates and starts the periodic timer for diagnostic refreshes.
func _setup_refresh_timer() -> void:
	print("UI: Setting up diagnostic refresh timer.")
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = UPDATE_INTERVAL
	_refresh_timer.one_shot = false
	_refresh_timer.autostart = true
	_refresh_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_timer.timeout.connect(_update_metrics)
	add_child(_refresh_timer)


## Queries engine performance monitors and updates the label text if changed.
func _update_metrics() -> void:
	if not is_instance_valid(stats_label):
		return

	var current_fps: int = int(Performance.get_monitor(Performance.TIME_FPS))
	var vp: Viewport = get_viewport()
	var vp_rid: RID = vp.get_viewport_rid() if is_instance_valid(vp) else RID()

	var frame_setup: float = RenderingServer.get_frame_setup_time_cpu()
	var render_cpu: float = (
		RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) if vp_rid.is_valid() else 0.0
	)
	var proc_script: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var proc_phys: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var vsync_on: bool = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	var cpu_active: float = 0.0
	if vsync_on or Engine.max_fps > 0:
		cpu_active = proc_phys + frame_setup + render_cpu
	else:
		cpu_active = proc_script + proc_phys + frame_setup + render_cpu
	var cpu_ms: float = snappedf(cpu_active, 0.1)

	var gpu_ms: float = (
		snappedf(RenderingServer.viewport_get_measured_render_time_gpu(vp_rid), 0.1)
		if vp_rid.is_valid()
		else 0.0
	)

	var vram_bytes: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var vram_mb: float = snappedf(vram_bytes / (1024.0 * 1024.0), 0.1)

	if (
		current_fps == _last_fps
		and is_equal_approx(cpu_ms, _last_cpu_ms)
		and is_equal_approx(gpu_ms, _last_gpu_ms)
		and is_equal_approx(vram_mb, _last_vram_mb)
	):
		return

	_last_fps = current_fps
	_last_cpu_ms = cpu_ms
	_last_gpu_ms = gpu_ms
	_last_vram_mb = vram_mb

	var headroom_ms: float = snappedf(TARGET_FRAME_BUDGET_MS - maxf(cpu_ms, gpu_ms), 0.1)

	stats_label.text = (
		"FPS: %d  |  CPU: %.1f ms  |  GPU: %.1f ms  |  Headroom: %.1f ms  |  VRAM: %.1f MB"
		% [current_fps, cpu_ms, gpu_ms, headroom_ms, vram_mb]
	)
