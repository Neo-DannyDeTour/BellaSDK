## A performance monitoring node that detects and logs frame drops.
##
## [FrameSpikeDetector] hooks into the process loop to measure frame delta times.
## If a frame takes longer than the [constant SPIKE_THRESHOLD_MS], it triggers an
## immediate console report containing memory and rendering performance metrics.
class_name FrameSpikeDetector
extends Node

## The maximum acceptable frame time in milliseconds before triggering a warning.
## Target: 60 FPS -> ~16.66 ms frame time.
const SPIKE_THRESHOLD_MS: float = 16.6


## Called when the node enters the scene tree for the first time.
## Initializes the detector and prints the monitoring threshold.
func _ready() -> void:
	print("FrameSpikeDetector initialized.")
	print("Monitoring for frames over ", SPIKE_THRESHOLD_MS, " ms.")


## Called every frame. Checks if the [param delta] exceeds the threshold.
## [param delta] The time elapsed since the previous frame in seconds.
func _process(delta: float) -> void:
	var frame_time_ms: float = delta * 1000.0

	if frame_time_ms > SPIKE_THRESHOLD_MS:
		_report_spike_data(frame_time_ms)


## Prints a detailed performance snapshot when a frame spike occurs.
## [param frame_time_ms] The duration of the slow frame in milliseconds.
func _report_spike_data(frame_time_ms: float) -> void:
	print("!!! FRAME SPIKE DETECTED !!!")
	print("Frame Time: ", frame_time_ms, " ms")
	print("Gathering performance metrics...")

	# Calculate Memory and VRAM in Megabytes
	var mem_used: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vram_used: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0

	# Gather Rendering metrics (Draw calls, poly count, objects)
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))

	print("--- Performance Snapshot ---")
	print("RAM Used: ", snapped(mem_used, 0.01), " MB")
	print("VRAM Used: ", snapped(vram_used, 0.01), " MB (Check textures if this spikes)")
	print("Draw Calls: ", draw_calls, " (High calls = CPU bottleneck submitting to GPU)")
	print("Primitives (Polygons): ", primitives, " (High count = Too many high-poly meshes)")
	print("Objects Drawn: ", objects)
	print("----------------------------")

	# breakpoint
