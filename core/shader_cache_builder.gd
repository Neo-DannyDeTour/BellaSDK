@tool
## Gathers and pre-caches all project materials across resources, scenes, and meshes.
class_name ShaderCacheBuilder
extends EditorScript

## The path where the generated [ShaderCache] resource will be saved.
const CACHE_PATH: String = "res://shared/shader_cache.tres"

## The root directory to start scanning for materials.
const MATERIALS_DIR: String = "res://"

## Folders to completely ignore during scanning.
const IGNORED_DIRS: Array[String] = [".godot", ".git", "addons"]


## Initiates the deep recursive material scan.
func _run() -> void:
	print("ShaderCacheBuilder: Starting deep material scan...")
	var cache: ShaderCache = ShaderCache.new()
	var gathered_materials: Array[Material] = []

	_scan_directory(MATERIALS_DIR, gathered_materials)
	cache.materials = gathered_materials

	var error: Error = ResourceSaver.save(cache, CACHE_PATH)
	if error == OK:
		print("ShaderCacheBuilder: Saved %d materials." % cache.materials.size())
	else:
		push_error("ShaderCacheBuilder: Save failed: " + error_string(error))


## Recursively scans the file system for scenes and materials.
func _scan_directory(path: String, array_ref: Array[Material]) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if (
			dir.current_is_dir()
			and not file_name.begins_with(".")
			and file_name not in IGNORED_DIRS
		):
			_scan_directory(path.path_join(file_name), array_ref)
		elif not dir.current_is_dir():
			_process_file(path.path_join(file_name), array_ref)
		file_name = dir.get_next()


## Evaluates a file and extracts material definitions.
func _process_file(res_path: String, array_ref: Array[Material]) -> void:
	if res_path == CACHE_PATH:
		return

	if res_path.ends_with(".tres") or res_path.ends_with(".material"):
		var res: Resource = load(res_path)
		if res is Material:
			_append_unique_material(res as Material, array_ref)
	elif res_path.ends_with(".tscn"):
		var scene: PackedScene = load(res_path) as PackedScene
		if scene:
			_extract_scene_materials(scene, array_ref)


## Deep scans all nodes and sub-resources inside a PackedScene.
func _extract_scene_materials(scene: PackedScene, array_ref: Array[Material]) -> void:
	var state: SceneState = scene.get_state()
	for node_idx: int in range(state.get_node_count()):
		for prop_idx: int in range(state.get_node_property_count(node_idx)):
			var prop_val: Variant = state.get_node_property_value(node_idx, prop_idx)
			if prop_val is Material:
				_append_unique_material(prop_val as Material, array_ref)
			elif prop_val is Mesh:
				var mesh: Mesh = prop_val as Mesh
				for surf_idx: int in range(mesh.get_surface_count()):
					var surf_mat: Material = mesh.surface_get_material(surf_idx)
					if surf_mat:
						_append_unique_material(surf_mat, array_ref)


## Filters out non-visual/particle materials that cannot be warmed on quads.
func _append_unique_material(mat: Material, array_ref: Array[Material]) -> void:
	if not is_instance_valid(mat) or array_ref.has(mat):
		return
	# ParticleProcessMaterial runs on compute/particles, not surface/canvas pipelines
	if mat is ParticleProcessMaterial:
		return
	array_ref.append(mat)
