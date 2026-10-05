## Displays live performance diagnostics (FPS, RAM, VRAM) overlaid on viewport.
class_name DioramaPerfOverlay
extends MarginContainer

## Interval in seconds between diagnostic string refreshes.
const UPDATE_INTERVAL: float = 0.25

## Label displaying formatted performance metrics.
@onready var stats_label: Label = %StatsLabel

## Dedicated timer driving periodic diagnostic metric refreshes.
var _refresh_timer: Timer = null

## Stored previous FPS metric value to prevent redundant text rebuilds.
var _last_fps: int = -1

## Stored previous static RAM metric value in megabytes.
var _last_ram_mb: float = -1.0

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
	var static_ram_bytes: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var vram_bytes: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)

	var ram_mb: float = snappedf(static_ram_bytes / (1024.0 * 1024.0), 0.1)
	var vram_mb: float = snappedf(vram_bytes / (1024.0 * 1024.0), 0.1)

	if (
		current_fps == _last_fps
		and is_equal_approx(ram_mb, _last_ram_mb)
		and is_equal_approx(vram_mb, _last_vram_mb)
	):
		return

	_last_fps = current_fps
	_last_ram_mb = ram_mb
	_last_vram_mb = vram_mb

	stats_label.text = (
		"FPS: %d  |  RAM: %.1f MB  |  VRAM: %.1f MB" % [current_fps, ram_mb, vram_mb]
	)
