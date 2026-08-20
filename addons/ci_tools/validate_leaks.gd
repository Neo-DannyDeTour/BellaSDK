## [ValidateLeaks] tests scenes for memory leaks, un-freed instances, and orphan nodes.
##
## Loads and instantiates every scene in the project, mounts it to the active tree,
## cleans it up, and checks [Performance] counters to detect orphan nodes and memory leaks.
class_name ValidateLeaks
extends SceneTree

## Maximum directory search depth when discovering scenes.
const MAX_SEARCH_DEPTH: int = 32

## Root project path to scan for scenes.
const SCAN_ROOT_PATH: String = "res://"

## Number of frames to wait for garbage collection and deferred free cycles to settle.
const SETTLE_FRAME_COUNT: int = 5

## Total number of leak and orphan errors detected.
var _error_count: int = 0

## Total number of scenes scanned during execution.
var _scanned_count: int = 0


## Initializes the test suite, executes leak checks on all scenes, and sets the exit code.
func _init() -> void:
	print("[ValidateLeaks] Starting memory leak and orphan node checks...")
	_run_leak_validation()
	if _error_count > 0:
		var err_msg: String = (
			"[ValidateLeaks] Validation failed with %d memory/orphan error(s)." % _error_count
		)
		print(err_msg)
		quit(1)
	else:
		var pass_msg: String = (
			"[ValidateLeaks] All %d scene(s) passed without orphan nodes or memory leaks."
			% _scanned_count
		)
		print(pass_msg)
		quit(0)


## Discovers scenes and tests each one in isolation.
func _run_leak_validation() -> void:
	print("[ValidateLeaks] Discovering scenes in %s" % SCAN_ROOT_PATH)
	var scene_paths: Array[String] = _gather_scene_files(SCAN_ROOT_PATH, 0)
	print("[ValidateLeaks] Found %d scenes to test for memory leaks." % scene_paths.size())
	for scene_path: String in scene_paths:
		_scanned_count += 1
		_test_scene_for_leaks(scene_path)


## Recursively collects all .tscn scene file paths from [param dir_path].
func _gather_scene_files(dir_path: String, depth: int) -> Array[String]:
	var results: Array[String] = []
	if depth > MAX_SEARCH_DEPTH:
		print("[ValidateLeaks] Maximum recursion depth reached at: %s" % dir_path)
		return results

	var dir: DirAccess = DirAccess.open(dir_path)
	if not dir:
		print("[ValidateLeaks] Failed to open directory: %s" % dir_path)
		_error_count += 1
		return results

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var full_path: String = dir_path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with(".") and file_name != ".godot":
				results.append_array(_gather_scene_files(full_path, depth + 1))
		else:
			if file_name.ends_with(".tscn"):
				results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	return results


## Instantiates, mounts, and unloads [param scene_path] to inspect [Performance] monitors.
func _test_scene_for_leaks(scene_path: String) -> void:
	print("[ValidateLeaks] Testing scene for leaks: %s" % scene_path)
	var monitor_id: Performance.Monitor = Performance.OBJECT_ORPHAN_NODE_COUNT
	var baseline_orphans: int = int(Performance.get_monitor(monitor_id))

	var packed_scene: PackedScene = (
		ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
		as PackedScene
	)

	if not packed_scene:
		print("[ValidateLeaks] ERROR: Could not load scene: %s" % scene_path)
		_error_count += 1
		return

	var instance: Node = packed_scene.instantiate()
	if not instance:
		print("[ValidateLeaks] ERROR: Could not instantiate scene: %s" % scene_path)
		_error_count += 1
		return

	root.add_child(instance)
	root.remove_child(instance)
	instance.queue_free()

	# Process deferred frees to settle instances
	for _i: int in range(SETTLE_FRAME_COUNT):
		await process_frame

	var post_orphans: int = int(Performance.get_monitor(monitor_id))
	var orphan_diff: int = post_orphans - baseline_orphans

	if orphan_diff > 0:
		var err: String = (
			"[ValidateLeaks] ERROR: %d orphan node(s) created by %s" % [orphan_diff, scene_path]
		)
		print(err)
		_error_count += 1
