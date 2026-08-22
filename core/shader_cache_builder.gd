@tool
## An [EditorScript] utility to automatically gather and cache all materials in the project.
##
## This script recursively scans the project directory for [Material] resources and
## compiles them into a single [ShaderCache] resource. This cache can then be loaded
## at runtime to preemptively compile shaders and prevent frame drops.
class_name ShaderCacheBuilder
extends EditorScript

## The path where the generated [ShaderCache] resource will be saved.
const CACHE_PATH: String = "res://shared/shader_cache.tres"

## The root directory to start scanning for materials.
const MATERIALS_DIR: String = "res://"


## Executed when the script is run from the editor's Script tab.
## Initializes the scan and saves the resulting [ShaderCache].
func _run() -> void:
	print("EditorScript: Starting automated shader cache generation...")

	var cache: ShaderCache
	if ResourceLoader.exists(CACHE_PATH):
		cache = load(CACHE_PATH) as ShaderCache
	if not cache:
		cache = ShaderCache.new()
		print("EditorScript: Created new ShaderCache instance.")

	# 1. Create a fresh, unlocked local array
	var gathered_materials: Array[Material] = []

	# 2. Pass our local array to be filled
	_scan_directory(MATERIALS_DIR, gathered_materials)

	# 3. Overwrite the resource's locked array with our populated one
	cache.materials = gathered_materials

	var error: Error = ResourceSaver.save(cache, CACHE_PATH)
	if error == OK:
		print(
			(
				"EditorScript: Successfully saved %d materials to %s."
				% [cache.materials.size(), CACHE_PATH]
			)
		)
	else:
		push_error("EditorScript: Failed to save cache. Error code: %d" % error)


## Recursively scans a directory for files ending in `.tres` or `.material`
## and appends them to the provided array if they are [Material] resources.
## [param path] The current directory path being scanned.
## [param array_ref] The array where discovered [Material] resources will be appended.
func _scan_directory(path: String, array_ref: Array[Material]) -> void:
	var dir: DirAccess = DirAccess.open(path)

	if not dir:
		push_error("EditorScript: Failed to open directory: " + path)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if dir.current_is_dir():
			# Recursively scan subfolders, ignoring hidden system folders like .godot
			if not file_name.begins_with("."):
				_scan_directory(path + "/" + file_name, array_ref)
		else:
			# Check for standard Godot resource files that might be materials
			if file_name.ends_with(".tres") or file_name.ends_with(".material"):
				var res_path: String = path + "/" + file_name
				var res: Resource = load(res_path)

				if res is Material:
					array_ref.append(res as Material)
					print("EditorScript: Added material to cache -> " + res_path)

		file_name = dir.get_next()
