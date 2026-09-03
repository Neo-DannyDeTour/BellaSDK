## Autonomous CLI tool to generate preview snapshots for gameplay scenes.
class_name DocScreenshotGenerator
extends SceneTree

const OUTPUT_DIR: String = "res://docs_md/images/previews/"
const SCREENSHOT_SIZE: Vector2i = Vector2i(800, 600)
const SCENE_SEARCH_PATH: String = "res://"


## Instantiates the rendering pipeline, iterates over scenes, and exits the engine.
func _init() -> void:
	print("Starting automated doc screenshot capture...")
	var dir: DirAccess = DirAccess.open("res://")
	if not dir.dir_exists(OUTPUT_DIR):
		dir.make_dir_recursive(OUTPUT_DIR)

	var viewport: SubViewport = _setup_viewport()
	root.add_child(viewport)

	var scene_paths: Array[String] = _find_scenes(SCENE_SEARCH_PATH)
	for scene_path: String in scene_paths:
		_capture_scene(viewport, scene_path)

	print("Screenshot generation completed.")
	quit()


## Configures an isolated SubViewport with lighting and an isometric Camera3D.
func _setup_viewport() -> SubViewport:
	var vp: SubViewport = SubViewport.new()
	vp.size = SCREENSHOT_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true

	var world: World3D = World3D.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.15, 1.0)
	world.environment = env
	vp.world_3d = world

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 45.0, 0.0)
	vp.add_child(light)

	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(45.0, -135.0, 0.0)
	fill_light.light_energy = 0.4
	vp.add_child(fill_light)

	var camera: Camera3D = Camera3D.new()
	camera.name = "CaptureCamera"
	vp.add_child(camera)

	return vp


## Recursively discovers all .tscn files, excluding addons and build folders.
func _find_scenes(base_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir: DirAccess = DirAccess.open(base_path)
	if not dir:
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir():
			if not file_name in [".git", ".github", "addons", "docs_md", "site"]:
				result.append_array(_find_scenes(base_path.path_join(file_name)))
		elif file_name.ends_with(".tscn"):
			result.append(base_path.path_join(file_name))
		file_name = dir.get_next()
	return result


## Computes the combined AABB bounding box for visual nodes in the scene.
func _calculate_aabb(node: Node) -> AABB:
	var total_aabb: AABB = AABB()
	var found_first: bool = false

	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is VisualInstance3D and not (current is Light3D):
			var aabb: AABB = current.get_aabb()
			if aabb.size != Vector3.ZERO:
				var global_aabb: AABB = current.transform * aabb
				if not found_first:
					total_aabb = global_aabb
					found_first = true
				else:
					total_aabb = total_aabb.merge(global_aabb)
		for child: Node in current.get_children():
			stack.append(child)

	if not found_first:
		return AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))
	return total_aabb


## Instantiates target scene, frames the camera, forces frames, and writes PNG.
func _capture_scene(viewport: SubViewport, path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if not packed or not packed.can_instantiate():
		return

	var instance: Node = packed.instantiate()
	if not is_instance_valid(instance) or not (instance is Node3D):
		if is_instance_valid(instance):
			instance.free()
		return

	viewport.add_child(instance)

	var aabb: AABB = _calculate_aabb(instance)
	var camera: Camera3D = viewport.get_node("CaptureCamera") as Camera3D

	var max_dim: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var distance: float = maxf(max_dim * 1.8, 2.5)

	var center: Vector3 = aabb.get_center()
	var cam_offset: Vector3 = Vector3(1.0, 0.8, 1.0).normalized() * distance

	if is_instance_valid(camera) and camera.is_inside_tree():
		camera.global_position = center + cam_offset
		camera.look_at(center, Vector3.UP)

	for i: int in range(3):
		RenderingServer.force_draw(true)

	var tex: ViewportTexture = viewport.get_texture()
	if not is_instance_valid(tex):
		instance.free()
		return

	var img: Image = tex.get_image()
	if not is_instance_valid(img) or img.is_empty():
		instance.free()
		return

	var base_stem: String = path.get_file().get_basename()
	var script: Script = instance.get_script() as Script
	var class_ident: String = base_stem

	if is_instance_valid(script):
		var global_name: String = script.get_global_name()
		if not global_name.is_empty():
			class_ident = global_name

	var save_path: String = OUTPUT_DIR.path_join(class_ident + ".png")
	img.save_png(save_path)

	var sanitized_stem: String = base_stem.to_lower().replace("_", "")
	var fallback_path: String = OUTPUT_DIR.path_join(sanitized_stem + ".png")
	if fallback_path != save_path:
		img.save_png(fallback_path)

	print("Captured preview: ", save_path)
	instance.free()
