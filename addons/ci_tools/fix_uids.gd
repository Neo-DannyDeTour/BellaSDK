## Utility script executed in headless mode to scan, validate, and rebuild
## project UID registries and fix broken scene/resource dependencies.
@tool
extends SceneTree


## Entry point executed when the script is invoked from the command line.
## Scans all project resources, forces UID updates, and quits cleanly.
func _init() -> void:
	print("Executing headless UID integrity scanner and dependency repair pass.")
	var root_dir: String = "res://"
	var files: Array[String] = _get_all_resource_files(root_dir)
	var broken_count: int = 0

	for file_path: String in files:
		if file_path.begins_with("res://.godot/"):
			continue

		var cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE
		var res: Resource = ResourceLoader.load(file_path, "", cache_mode)
		if res == null:
			print("WARNING: Could not load resource: ", file_path)
			broken_count += 1
			continue

		var err: Error = ResourceSaver.save(res, file_path)
		if err != OK:
			print("ERROR: Failed to resave resource: ", file_path)
			broken_count += 1

	print("UID Repair Complete. Issues encountered: ", broken_count)
	quit(0 if broken_count == 0 else 1)


## Recursively collects all resource and scene file paths in the project.
## [param current_path]: Target directory path to scan.
## Returns an [Array] of absolute resource path [String] instances.
func _get_all_resource_files(current_path: String) -> Array[String]:
	print("Scanning directory for project resources: ", current_path)
	var result: Array[String] = []
	var dir: DirAccess = DirAccess.open(current_path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not file_name.begins_with("."):
			var full_path: String = current_path.path_join(file_name)
			if dir.current_is_dir():
				result.append_array(_get_all_resource_files(full_path))
			elif file_name.ends_with(".tscn") or file_name.ends_with(".tres"):
				result.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result
