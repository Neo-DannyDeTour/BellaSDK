@tool
extends EditorScript

const CACHE_PATH: String = "res://shared/shader_cache.tres"
const MATERIALS_DIR: String = "res://"


func _run() -> void:
	print("EditorScript: Starting automated shader cache generation...")
	
	var cache: ShaderCache = load(CACHE_PATH) as ShaderCache
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
		print("EditorScript: Successfully saved %d materials to %s." % [cache.materials.size(), CACHE_PATH])
	else:
		push_error("EditorScript: Failed to save cache. Error code: %d" % error)


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
