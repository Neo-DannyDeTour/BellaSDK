@tool
extends EditorScript

# Define where you want the baked cache file to be saved.
const CACHE_FILE_PATH: String = "res://shared/shader_cache.tres"

# Define the folders where your materials live to avoid scanning the whole project.
const SEARCH_DIRECTORIES: Array[String] = [
	"res://materials",
	"res://models",
    "res://vfx"
]


func _run() -> void:
	print("Executing EditorScript: Building shader cache...")
	
	var cache: ShaderCache = ShaderCache.new()
	
	for dir_path: String in SEARCH_DIRECTORIES:
		_scan_directory_for_materials(dir_path, cache)
		
	var error: Error = ResourceSaver.save(cache, CACHE_FILE_PATH)
	
	if error == OK:
		print("Success! Saved ", cache.materials.size(), " materials to cache.")
	else:
		push_error("Failed to save shader cache. Error code: " + str(error))


func _scan_directory_for_materials(path: String, cache: ShaderCache) -> void:
	print("Scanning directory for materials: ", path)
	
	var dir: DirAccess = DirAccess.open(path)
	if not dir:
		print("Directory not found, skipping: ", path)
		return
		
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			var sub_dir: String = path + "/" + file_name
			_scan_directory_for_materials(sub_dir, cache)
			
		elif file_name.ends_with(".tres") or file_name.ends_with(".material"):
			var resource_path: String = path + "/" + file_name
			_evaluate_and_store_resource(resource_path, cache)
			
		file_name = dir.get_next()


func _evaluate_and_store_resource(res_path: String, cache: ShaderCache) -> void:
	print("Evaluating file: ", res_path)
	
	var resource: Resource = ResourceLoader.load(res_path)
	if resource is Material:
		cache.materials.append(resource as Material)
		print("Added material to cache: ", res_path)
