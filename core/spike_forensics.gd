## Forensic frame-spike profiler writing attributed JSONL snapshots to user logs.
# class_name SpikeForensics
extends Node

## Emitted when a frame exceeds [constant SPIKE_THRESHOLD_MS] with full attribution.
signal spike_detected(record: Dictionary)

## Directory storing runtime spike forensic logs.
const LOG_DIR: String = "user://logs"

## Active JSONL forensic log path.
const LOG_PATH: String = "user://logs/spike_forensics.jsonl"

## Rotated backup log path used when active log exceeds [constant MAX_LOG_BYTES].
const BACKUP_LOG_PATH: String = "user://logs/spike_forensics.jsonl.bak"

## Maximum log file size in bytes before rotation (5 MiB).
const MAX_LOG_BYTES: int = 5242880

## Frame duration threshold in milliseconds for recording a warning spike.
const SPIKE_THRESHOLD_MS: float = 20.0

## Frame duration threshold in milliseconds for severe hitch classification.
const HITCH_THRESHOLD_MS: float = 33.333

## Interval in seconds between buffered disk flushes.
const FLUSH_INTERVAL_SEC: float = 2.0

## Maximum number of recent spike records retained in memory.
const MAX_RECENT_SPIKES: int = 20

## Maximum node entries captured per frame to prevent spike-cascade allocations.
const MAX_FRAME_NODES: int = 24

## Conversion factor from bytes to megabytes.
const BYTES_PER_MB: float = 1048576.0

## Whether forensic frame monitoring is active.
var _enabled: bool = false

## Whether spike recording is temporarily suppressed during deliberate editor/debug scans.
var _suppressed: bool = false

## Monotonic microsecond timestamp of the previous frame.
var _last_tick_usec: int = 0

## Accumulated seconds since the last buffered disk flush.
var _flush_timer: float = 0.0

## Previous frame static RAM usage in megabytes.
var _prev_ram_mb: float = 0.0

## Previous frame video RAM usage in megabytes.
var _prev_vram_mb: float = 0.0

## Previous frame total draw call count.
var _prev_draw_calls: int = 0

## Previous frame total rendered primitive count.
var _prev_primitives: int = 0

## Ring buffer of recent attributed spike records for live UI inspection.
var _recent_spikes: Array[Dictionary] = []

## Buffered JSONL lines awaiting periodic disk flush.
var _write_buffer: PackedStringArray = PackedStringArray()

## Node descriptors added to the [SceneTree] during the current frame.
var _frame_nodes_added: PackedStringArray = PackedStringArray()

## Node descriptors removed from the [SceneTree] during the current frame.
var _frame_nodes_freed: PackedStringArray = PackedStringArray()

## Start timestamps in microseconds for active [method begin_scope] markers.
var _scope_starts_usec: Dictionary[StringName, int] = {}

## Accumulated durations in milliseconds for scopes completed this frame.
var _scope_durations_ms: Dictionary[StringName, float] = {}


## Initializes baseline counters, tree hooks, and debug-gated processing.
func _ready() -> void:
	_enabled = OS.has_feature("debug") or OS.get_cmdline_args().has("--spike-forensics")
	if not _enabled:
		set_process(false)
		return

	var tree: SceneTree = get_tree()
	if is_instance_valid(tree):
		if not tree.node_added.is_connected(_on_tree_node_added):
			tree.node_added.connect(_on_tree_node_added)
		if not tree.node_removed.is_connected(_on_tree_node_removed):
			tree.node_removed.connect(_on_tree_node_removed)

	_snapshot_baselines()
	_last_tick_usec = Time.get_ticks_usec()
	print("SpikeForensics: Active -> ", ProjectSettings.globalize_path(LOG_PATH))


## Disconnects tree hooks and flushes pending forensic records on exit.
func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if is_instance_valid(tree):
		if tree.node_added.is_connected(_on_tree_node_added):
			tree.node_added.disconnect(_on_tree_node_added)
		if tree.node_removed.is_connected(_on_tree_node_removed):
			tree.node_removed.disconnect(_on_tree_node_removed)
	flush_to_disk()


## Measures frame time, attributes spikes, clears per-frame buffers, and flushes logs.
func _process(delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var frame_ms: float = float(now_usec - _last_tick_usec) * 0.001
	_last_tick_usec = now_usec

	if not _suppressed and frame_ms > SPIKE_THRESHOLD_MS:
		evaluate_frame_sample(frame_ms)

	_clear_frame_buffers()
	_snapshot_baselines()

	_flush_timer += delta
	if _flush_timer >= FLUSH_INTERVAL_SEC and not _write_buffer.is_empty():
		_flush_timer = 0.0
		flush_to_disk()


## Starts a lightweight microsecond timing scope for subsystem attribution.
func begin_scope(scope_name: StringName) -> void:
	if not _enabled:
		return
	_scope_starts_usec[scope_name] = Time.get_ticks_usec()


## Ends a timing scope and accumulates its duration for the current frame.
func end_scope(scope_name: StringName) -> void:
	if not _enabled or not _scope_starts_usec.has(scope_name):
		return
	var elapsed_ms: float = float(Time.get_ticks_usec() - _scope_starts_usec[scope_name]) * 0.001
	var prev_ms: float = _scope_durations_ms.get(scope_name, 0.0)
	_scope_durations_ms[scope_name] = prev_ms + elapsed_ms


## Temporarily suppresses spike capture during intentional heavy debug scans.
func set_suppressed(suppressed: bool) -> void:
	_suppressed = suppressed


## Returns a shallow copy of recent attributed spike records.
func get_recent_spikes() -> Array[Dictionary]:
	return _recent_spikes.duplicate()


## Returns the resolved user log file path.
func get_log_path() -> String:
	return LOG_PATH


## Evaluates [param frame_ms], builds an attributed record if above threshold, and queues flush.
func evaluate_frame_sample(frame_ms: float) -> Dictionary:
	if frame_ms <= SPIKE_THRESHOLD_MS:
		return {}

	var cpu_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var gpu_ms: float = _read_gpu_render_ms()

	var ram_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_PER_MB
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / BYTES_PER_MB
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	var culprit: String = _resolve_culprit(cpu_ms, physics_ms, gpu_ms)
	var scene_path: String = _get_active_scene_path()
	var scopes_dict: Dictionary = {}
	for key: StringName in _scope_durations_ms:
		scopes_dict[String(key)] = snappedf(_scope_durations_ms[key], 0.01)

	var record: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"severity": "hitch" if frame_ms >= HITCH_THRESHOLD_MS else "spike",
		"frame_ms": snappedf(frame_ms, 0.01),
		"culprit": culprit,
		"cpu_process_ms": snappedf(cpu_ms, 0.01),
		"physics_ms": snappedf(physics_ms, 0.01),
		"gpu_ms": snappedf(gpu_ms, 0.01),
		"ram_mb": snappedf(ram_mb, 0.01),
		"ram_delta_mb": snappedf(ram_mb - _prev_ram_mb, 0.02),
		"vram_mb": snappedf(vram_mb, 0.01),
		"vram_delta_mb": snappedf(vram_mb - _prev_vram_mb, 0.02),
		"draw_calls": draw_calls,
		"draw_calls_delta": draw_calls - _prev_draw_calls,
		"primitives_delta": primitives - _prev_primitives,
		"scene": scene_path,
		"nodes_added": Array(_frame_nodes_added),
		"nodes_freed": Array(_frame_nodes_freed),
		"scopes": scopes_dict,
	}

	_recent_spikes.push_back(record)
	if _recent_spikes.size() > MAX_RECENT_SPIKES:
		_recent_spikes.pop_front()

	_write_buffer.append(JSON.stringify(record))
	spike_detected.emit(record)
	return record


## Flushes buffered JSONL spike records to disk with automatic log rotation.
func flush_to_disk() -> void:
	if _write_buffer.is_empty():
		return

	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_rotate_log_if_needed()

	var mode: FileAccess.ModeFlags = (
		FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE
	)
	var file: FileAccess = FileAccess.open(LOG_PATH, mode)
	if not file:
		return

	file.seek_end()
	for line: String in _write_buffer:
		file.store_line(line)
	file.close()
	_write_buffer.clear()


## Records a newly added node descriptor up to [constant MAX_FRAME_NODES].
func _on_tree_node_added(node: Node) -> void:
	if _frame_nodes_added.size() >= MAX_FRAME_NODES or not is_instance_valid(node):
		return
	var scene_tag: String = node.scene_file_path.get_file()
	var label: String = (
		"%s(%s)" % [String(node.name), node.get_class()]
		if scene_tag.is_empty()
		else "%s[%s]" % [String(node.name), scene_tag]
	)
	_frame_nodes_added.append(label)


## Records a removed node descriptor up to [constant MAX_FRAME_NODES].
func _on_tree_node_removed(node: Node) -> void:
	if _frame_nodes_freed.size() >= MAX_FRAME_NODES or not is_instance_valid(node):
		return
	_frame_nodes_freed.append("%s(%s)" % [String(node.name), node.get_class()])


## Captures current memory and render counters as baseline for next frame deltas.
func _snapshot_baselines() -> void:
	_prev_ram_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_PER_MB
	_prev_vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / BYTES_PER_MB
	_prev_draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_prev_primitives = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


## Clears per-frame node and scope attribution buffers.
func _clear_frame_buffers() -> void:
	if not _frame_nodes_added.is_empty():
		_frame_nodes_added.clear()
	if not _frame_nodes_freed.is_empty():
		_frame_nodes_freed.clear()
	if not _scope_durations_ms.is_empty():
		_scope_durations_ms.clear()


## Reads measured GPU render time for the root viewport when available.
func _read_gpu_render_ms() -> float:
	var vp: Viewport = get_viewport()
	if not is_instance_valid(vp):
		return 0.0
	return RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())


## Resolves the dominant subsystem culprit label from CPU, physics, and GPU timings.
func _resolve_culprit(cpu_ms: float, physics_ms: float, gpu_ms: float) -> String:
	if physics_ms >= cpu_ms and physics_ms >= gpu_ms:
		return "Physics"
	if cpu_ms >= gpu_ms:
		return "CPU Process"
	return "GPU"


## Returns the current scene file path or root node name if unsaved.
func _get_active_scene_path() -> String:
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.current_scene):
		return "unknown"
	var path: String = tree.current_scene.scene_file_path
	return path if not path.is_empty() else String(tree.current_scene.name)


## Rotates [constant LOG_PATH] to [constant BACKUP_LOG_PATH] when size exceeds limit.
func _rotate_log_if_needed() -> void:
	if not FileAccess.file_exists(LOG_PATH):
		return
	var check_file: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ)
	if not check_file:
		return
	var file_size: int = check_file.get_length()
	check_file.close()
	if file_size < MAX_LOG_BYTES:
		return
	if FileAccess.file_exists(BACKUP_LOG_PATH):
		DirAccess.remove_absolute(BACKUP_LOG_PATH)
	DirAccess.rename_absolute(LOG_PATH, BACKUP_LOG_PATH)
