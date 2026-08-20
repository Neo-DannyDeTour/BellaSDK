## [ValidateAssets] validates asset integrity, scene dependencies, and resource references.
##
## Scans the project directory for all scene and resource files to detect broken dependencies,
## invalid UIDs, and runtime instantiation errors in automated CI/CD pipelines.
class_name ValidateAssets
extends SceneTree

## Maximum directory traversal depth to prevent infinite recursion.
const MAX_SEARCH_DEPTH: int = 32

## Root project path to scan for assets.
const SCAN_ROOT_PATH: String = "res://"

## Tracks the total number of validation errors encountered during execution.
var _error_count: int = 0

## Tracks the total number of files scanned during execution.
var _scanned_count: int = 0


## Initializes the headless validation suite, runs all checks, and sets the exit code.
func _init() -> void:
	print("[ValidateAssets] Starting asset integrity validation...")
	_run_validation()
	if _error_count > 0:
		print("[ValidateAssets] Validation failed with %d error(s)." % _error_count)
		quit(1)
	else:
		print("[ValidateAssets] All %d asset(s) validated successfully." % _scanned_count)
		quit(0)


## Orchestrates the asset discovery and test execution pipeline.
func _run_validation() -> void:
	print("[ValidateAssets] Discovering asset files in %s" % SCAN_ROOT_PATH)
	var asset_paths: Array[String] = _gather_asset_files(SCAN_ROOT_PATH, 0)
	print("[ValidateAssets] Found %d total asset files to validate." % asset_paths.size())
	for file_path: String in asset_paths:
		_scanned_count += 1
		if file_path.ends_with(".tscn"):
			_validate_scene_file(file_path)
		elif file_path.ends_with(".tres"):
			_validate_resource_file(file_path)


## Recursively gathers all .tscn and .tres file paths from [param dir_path].
func _gather_asset_files(dir_path: String, depth: int) -> Array[String]:
	var results: Array[String] = []
	if depth > MAX_SEARCH_DEPTH:
		print("[ValidateAssets] Maximum recursion depth reached at: %s" % dir_path)
		return results

	var dir: DirAccess = DirAccess.open(dir_path)
	if not dir:
		print("[ValidateAssets] Failed to open directory: %s" % dir_path)
		_error_count += 1
		return results

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var full_path: String = dir_path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with(".") and file_name != ".godot":
				results.append_array(_gather_asset_files(full_path, depth + 1))
		else:
			if file_name.ends_with(".tscn") or file_name.ends_with(".tres"):
				results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	return results


## Loads and instantiates the [PackedScene] at
## [param scene_path] to detect missing nodes or scripts.
func _validate_scene_file(scene_path: String) -> void:
	print("[ValidateAssets] Validating scene: %s" % scene_path)
	if not ResourceLoader.exists(scene_path):
		print("[ValidateAssets] ERROR: Scene file not found: %s" % scene_path)
		_error_count += 1
		return

	var resource: Resource = ResourceLoader.load(
		scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE
	)
	if not resource:
		print("[ValidateAssets] ERROR: Failed to load scene: %s" % scene_path)
		_error_count += 1
		return

	var packed_scene: PackedScene = resource as PackedScene
	if not packed_scene:
		print("[ValidateAssets] ERROR: Resource is not a PackedScene: %s" % scene_path)
		_error_count += 1
		return

	var instance: Node = packed_scene.instantiate()
	if not instance:
		print("[ValidateAssets] ERROR: Failed to instantiate scene: %s" % scene_path)
		_error_count += 1
		return

	instance.free()


## Loads the [Resource] at [param resource_path] to verify integrity and dependencies.
func _validate_resource_file(resource_path: String) -> void:
	print("[ValidateAssets] Validating resource: %s" % resource_path)
	if not ResourceLoader.exists(resource_path):
		print("[ValidateAssets] ERROR: Resource file not found: %s" % resource_path)
		_error_count += 1
		return

	var resource: Resource = ResourceLoader.load(
		resource_path, "", ResourceLoader.CACHE_MODE_REPLACE
	)
	if not resource:
		print("[ValidateAssets] ERROR: Failed to load resource: %s" % resource_path)
		_error_count += 1
