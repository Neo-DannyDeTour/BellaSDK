class_name BenchmarkRunner
extends SceneTree

## Target overall frame budget in milliseconds (16.67ms = 60 FPS).
var _target_frame_time_ms: float = 16.67

## Total frame samples to record before generating report.
var _frames_to_sample: int = 600

## Warmup frames skipped to avoid initial load stutter in metrics.
var _warmup_frames: int = 60

## Current processed frame index.
var _current_frame: int = 0

## Cached RID of the root viewport used for render time queries.
var _viewport_rid: RID

## Frame process CPU times in milliseconds.
var _cpu_times: Array[float] = []

## Frame render GPU times in milliseconds.
var _gpu_times: Array[float] = []

## Rendered draw call count recorded per frame.
var _draw_call_counts: Array[int] = []


func _init() -> void:
	print("BenchmarkRunner: Initializing performance benchmark...")
	call_deferred("_setup_viewport_measurement")


func _process(_delta: float) -> bool:
	_current_frame += 1

	if _current_frame <= _warmup_frames:
		return false

	_record_frame_metrics()

	if _cpu_times.size() >= _frames_to_sample:
		_evaluate_metrics_and_exit()
		return true

	return false


## Enables render time measurement on the active viewport.
func _setup_viewport_measurement() -> void:
	print("BenchmarkRunner: Enabling GPU/CPU viewport measurements...")
	_viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)


## Collects frame metrics for CPU, GPU, and draw calls.
func _record_frame_metrics() -> void:
	print("BenchmarkRunner: Recording active frame metrics...")
	var cpu_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_cpu_times.append(cpu_ms)

	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
	_gpu_times.append(gpu_ms)

	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_draw_call_counts.append(draw_calls)


## Calculates metrics, writes JSON report, and exits with status code.
func _evaluate_metrics_and_exit() -> void:
	print("BenchmarkRunner: Evaluating metrics and exporting report...")
	var samples: int = _cpu_times.size()
	if samples == 0:
		printerr("BenchmarkRunner ERROR: No frame samples recorded.")
		quit(1)
		return

	var avg_cpu: float = _calculate_average_float(_cpu_times)
	var p99_cpu: float = _calculate_percentile_float(_cpu_times, 0.99)
	var avg_gpu: float = _calculate_average_float(_gpu_times)
	var p99_gpu: float = _calculate_percentile_float(_gpu_times, 0.99)
	var avg_draws: float = _calculate_average_int(_draw_call_counts)
	var max_draws: int = _find_max_int(_draw_call_counts)

	var passed: bool = (p99_cpu <= _target_frame_time_ms) and (p99_gpu <= _target_frame_time_ms)

	var report: Dictionary = {
		"samples": samples,
		"cpu_time_ms": {"avg": avg_cpu, "p99": p99_cpu},
		"gpu_time_ms": {"avg": avg_gpu, "p99": p99_gpu},
		"draw_calls": {"avg": avg_draws, "max": max_draws},
		"passed": passed
	}

	_print_report_summary(avg_cpu, p99_cpu, avg_gpu, p99_gpu, avg_draws, max_draws)
	_save_report_file(report)

	if not passed:
		printerr("BenchmarkRunner FAIL: Performance budget exceeded!")
		quit(1)
	else:
		print("BenchmarkRunner PASS: Metrics within budget.")
		quit(0)


## Calculates average of a float array.
func _calculate_average_float(values: Array[float]) -> float:
	print("BenchmarkRunner: Calculating float array average...")
	var sum: float = 0.0
	for val in values:
		sum += val
	return sum / values.size()


## Calculates average of an int array.
func _calculate_average_int(values: Array[int]) -> float:
	print("BenchmarkRunner: Calculating int array average...")
	var sum: float = 0.0
	for val in values:
		sum += val
	return sum / values.size()


## Calculates percentile value of a float array.
func _calculate_percentile_float(values: Array[float], percentile: float) -> float:
	print("BenchmarkRunner: Calculating array percentile...")
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var index: int = int(sorted.size() * percentile)
	index = clampi(index, 0, sorted.size() - 1)
	return sorted[index]


## Finds maximum integer value in an array.
func _find_max_int(values: Array[int]) -> int:
	print("BenchmarkRunner: Finding maximum integer in array...")
	var max_val: int = values[0]
	for val in values:
		if val > max_val:
			max_val = val
	return max_val


## Prints structured benchmark results to standard output.
func _print_report_summary(
	avg_cpu: float, p99_cpu: float, avg_gpu: float, p99_gpu: float, avg_draws: float, max_draws: int
) -> void:
	print("BenchmarkRunner: Printing benchmark summary to console...")
	print("\n=== PERFORMANCE REPORT ===")
	print("CPU Time  | Avg: %.2f ms | 99th %%: %.2f ms" % [avg_cpu, p99_cpu])
	print("GPU Time  | Avg: %.2f ms | 99th %%: %.2f ms" % [avg_gpu, p99_gpu])
	print("Draw Calls| Avg: %.1f    | Max: %d" % [avg_draws, max_draws])
	print("==========================\n")


## Writes benchmark data dictionary to user JSON file.
func _save_report_file(report: Dictionary) -> void:
	print("BenchmarkRunner: Saving report to benchmark_report.json...")
	var file: FileAccess = FileAccess.open("user://benchmark_report.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
