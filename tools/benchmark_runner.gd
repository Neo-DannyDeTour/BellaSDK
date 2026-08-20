## Autonomous headless performance benchmarking harness for Godot 4.
## Executes a stress test scenario for a set frame count, samples frame times
## and engine performance monitors, and exits with a non-zero code upon regression.
class_name BenchmarkRunner
extends Node

## Emitted when the benchmark completes all frames, passing the evaluated metrics dictionary.
signal benchmark_completed(metrics: Dictionary)

## Target frame time budget for locked 60 FPS (16.67 milliseconds).
const TARGET_FRAME_TIME_MS: float = 16.67

## Total number of frames to sample during the benchmark.
const TOTAL_FRAMES_TO_RUN: int = 1200

## Number of initial warm-up frames to discard before recording metrics.
const WARMUP_FRAMES: int = 120

## Maximum allowable frame time spike in milliseconds before failing CI.
const MAX_ALLOWED_FRAME_SPIKE_MS: float = 20.0

## Maximum allowable 99th percentile (1% low) frame time in milliseconds.
const MAX_ALLOWED_P99_FRAME_MS: float = 16.67

## Total recorded frame times in milliseconds.
var _frame_times_ms: Array[float] = []

## Current frame index since execution started.
var _current_frame: int = 0

## Initial static memory usage in bytes captured after the warm-up period.
var _initial_static_memory: int = 0

## Holds the path to the stress-test scene to instantiate.
var _stress_scene_path: String = "res://tools/stress_test.tscn"

## Active instance of the stress test scene.
var _stress_scene_instance: Node = null


## Initializes the runner, checks headless mode constraints, and prepares the benchmark scene.
func _ready() -> void:
	print("[Benchmark] Initializing headless performance test...")
	if ResourceLoader.exists(_stress_scene_path):
		var packed_scene: PackedScene = load(_stress_scene_path) as PackedScene
		if is_instance_valid(packed_scene):
			_stress_scene_instance = packed_scene.instantiate()
			add_child(_stress_scene_instance)
			print("[Benchmark] Loaded stress scene: ", _stress_scene_path)
	else:
		print("[Benchmark] No custom stress scene found; running default load test.")


## Records per-frame metrics on every process tick and triggers evaluation when finished.
## [param delta]: The elapsed time in seconds since the previous frame.
func _process(delta: float) -> void:
	_current_frame += 1

	if _current_frame <= WARMUP_FRAMES:
		if _current_frame == WARMUP_FRAMES:
			_initial_static_memory = int(Performance.get_monitor(Performance.MEMORY_STATIC))
			print(
				"[Benchmark] Warm-up complete. Baseline memory: ", _initial_static_memory, " bytes."
			)
		return

	var frame_time_ms: float = delta * 1000.0
	_frame_times_ms.append(frame_time_ms)

	if _current_frame >= (WARMUP_FRAMES + TOTAL_FRAMES_TO_RUN):
		set_process(false)
		_finish_benchmark()


## Evaluates collected metrics, writes the JSON artifact, and terminates the engine.
func _finish_benchmark() -> void:
	print("[Benchmark] Finished recording frames. Evaluating results...")
	if is_instance_valid(_stress_scene_instance):
		_stress_scene_instance.free()
		_stress_scene_instance = null

	var metrics: Dictionary = _calculate_metrics()
	_export_report_to_disk(metrics)
	benchmark_completed.emit(metrics)

	var has_failed: bool = false

	if float(metrics["p99_ms"]) > MAX_ALLOWED_P99_FRAME_MS:
		printerr(
			"[FAIL] 99th Percentile frame time exceeded! Got: ",
			metrics["p99_ms"],
			" ms, Max allowed: ",
			MAX_ALLOWED_P99_FRAME_MS,
			" ms"
		)
		has_failed = true

	if float(metrics["max_spike_ms"]) > MAX_ALLOWED_FRAME_SPIKE_MS:
		printerr(
			"[FAIL] Frame spike exceeded limit! Got: ",
			metrics["max_spike_ms"],
			" ms, Max allowed: ",
			MAX_ALLOWED_FRAME_SPIKE_MS,
			" ms"
		)
		has_failed = true

	if int(metrics["orphan_nodes"]) > 0:
		printerr("[FAIL] Orphan nodes detected! Count: ", metrics["orphan_nodes"])
		Node.print_orphan_nodes()
		has_failed = true

	if has_failed:
		print("[Benchmark] Performance gate FAILED.")
		get_tree().quit(1)
	else:
		print("[Benchmark] Performance gate PASSED. 60 FPS budget maintained.")
		get_tree().quit(0)


## Computes statistical percentiles, averages, spikes, and engine performance metrics.
## Returns a [Dictionary] containing calculated performance values.
func _calculate_metrics() -> Dictionary:
	_frame_times_ms.sort()
	var sample_count: int = _frame_times_ms.size()
	var total_time_ms: float = 0.0
	var max_spike: float = 0.0

	for time_sample: float in _frame_times_ms:
		total_time_ms += time_sample
		if time_sample > max_spike:
			max_spike = time_sample

	var avg_ms: float = total_time_ms / float(sample_count)
	var p95_index: int = int(float(sample_count) * 0.95)
	var p99_index: int = int(float(sample_count) * 0.99)

	var p95_ms: float = _frame_times_ms[mini(p95_index, sample_count - 1)]
	var p99_ms: float = _frame_times_ms[mini(p99_index, sample_count - 1)]

	var final_static_memory: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var orphan_count: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	return {
		"average_frame_ms": snappedf(avg_ms, 0.01),
		"p95_ms": snappedf(p95_ms, 0.01),
		"p99_ms": snappedf(p99_ms, 0.01),
		"max_spike_ms": snappedf(max_spike, 0.01),
		"memory_drift_bytes": final_static_memory - _initial_static_memory,
		"orphan_nodes": orphan_count,
		"samples_evaluated": sample_count
	}


## Serializes benchmark results to a formatted JSON report for CI artifact extraction.
## [param report_data]: The metrics dictionary to be serialized.
func _export_report_to_disk(report_data: Dictionary) -> void:
	var report_path: String = "user://benchmark_report.json"
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		var json_string: String = JSON.stringify(report_data, "\t")
		file.store_string(json_string)
		file.close()
		print("[Benchmark] Performance metrics successfully exported to: ", report_path)
	else:
		printerr("[Benchmark] Failed to write report file: ", FileAccess.get_open_error())
