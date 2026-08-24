## Displays live performance diagnostics (FPS, RAM, VRAM) overlaid on the diorama viewport.
class_name DioramaPerfOverlay
extends MarginContainer

## Interval in seconds between diagnostic string refreshes.
const UPDATE_INTERVAL: float = 0.25

## Label displaying formatted performance metrics.
@onready var stats_label: Label = %StatsLabel

## Accumulated delta time tracking the next UI refresh.
var _time_accumulator: float = 0.0


## Lifecycle initialization configuring anchors and starting diagnostics.
func _ready() -> void:
	print("UI: Initializing Diorama Performance Overlay.")
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(stats_label):
		stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_metrics()


## Frame lifecycle handling timed metric refreshes.
## [param delta] Frame execution elapsed time in seconds.
func _process(delta: float) -> void:
	_time_accumulator += delta
	if _time_accumulator >= UPDATE_INTERVAL:
		_time_accumulator = 0.0
		_update_metrics()


## Queries engine performance monitors and updates the label text.
func _update_metrics() -> void:
	if not is_instance_valid(stats_label):
		return

	var current_fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var static_ram_bytes: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var vram_bytes: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)

	var ram_mb: float = static_ram_bytes / (1024.0 * 1024.0)
	var vram_mb: float = vram_bytes / (1024.0 * 1024.0)

	stats_label.text = (
		"FPS: %d  |  RAM: %.1f MB  |  VRAM: %.1f MB" % [int(current_fps), ram_mb, vram_mb]
	)
