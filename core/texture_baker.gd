@tool
extends SubViewport

enum BakeResolution {
	RES_256 = 256, RES_512 = 512, RES_1024 = 1024, RES_2048 = 2048, RES_4096 = 4096
}

enum ArchitectureType {
	NONE = 0,
	LADDER = 1,
	VENT = 2,
	HAZARD = 3,
	RULER = 4,
	SPAWN_POINT = 5,
	WINDOW = 6,
	DOOR = 7,
	STAIRS = 8
}

@export_group("Architecture Elements")
@export var architecture_type: ArchitectureType = ArchitectureType.NONE:
	set(value):
		architecture_type = value
		_update_shader_parameter("architecture_type", value)
		print("set_architecture_type(): Active architectural pattern changed to index ", value)

@export_group("Export Settings")
@export_dir var save_directory: String = "res://"
@export var base_file_name: String = "dev_texture"

## If true, appends the color, Godiva state, resolution, and transparency to the file name.
@export var smart_auto_naming: bool = true

## Sets the output resolution and forces the SubViewport to match.
@export var output_resolution: BakeResolution = BakeResolution.RES_1024:
	set(value):
		output_resolution = value
		size = Vector2i(value, value)
		print("output_resolution_set(): Viewport resolution updated to ", value, "x", value)

@export_group("Automation Setup")
@export var background_mesh: MeshInstance3D
@export var godiva_outline_mesh: MeshInstance3D
@export var target_camera: Camera3D

@export_group("Shader Parameters")
@export_range(0.1, 10.0) var unit_scale: float = 1.0:
	set(value):
		unit_scale = value
		_update_shader_parameter("unit_scale", value)

@export_range(2.0, 10.0) var major_subdivisions: float = 2.0:
	set(value):
		major_subdivisions = value
		_update_shader_parameter("major_subdivisions", value)

@export_range(2.0, 20.0) var minor_subdivisions: float = 8.0:
	set(value):
		minor_subdivisions = value
		_update_shader_parameter("minor_subdivisions", value)

@export_range(0.001, 0.05) var line_thickness: float = 0.01:
	set(value):
		line_thickness = value
		_update_shader_parameter("line_thickness", value)

## Drops the background opacity to 0.0 so only the grid lines remain.
@export var transparent_grid_only: bool = false:
	set(value):
		transparent_grid_only = value
		transparent_bg = value
		_update_shader_parameter("bg_alpha", 0.0 if value else 1.0)
		print("transparent_grid_only_set(): Transparent background state set to ", value)

@export_group("Actions")
@export var randomize_bg_color: bool = false:
	set(value):
		if value:
			_apply_random_dev_color()
		randomize_bg_color = false

@export var fit_camera_now: bool = false:
	set(value):
		if value:
			_fit_camera_to_mesh()
		fit_camera_now = false

@export var bake_single_now: bool = false:
	set(value):
		if value:
			_trigger_bake()
		bake_single_now = false

const CONTRAST_SHIFT: float = 0.12


func _update_shader_parameter(param_name: String, new_value: Variant) -> void:
	if background_mesh == null:
		return

	var active_mat: Material = background_mesh.get_active_material(0)
	var shader_mat: ShaderMaterial = active_mat as ShaderMaterial

	if shader_mat != null:
		shader_mat.set_shader_parameter(param_name, new_value)
		print("_update_shader_parameter(): Pushed ", param_name, " = ", new_value, " to shader.")


func _apply_random_dev_color() -> void:
	print("_apply_random_dev_color(): Generating random hue variation.")

	var random_hue: float = randf()
	var base_color: Color = Color.from_hsv(random_hue, 0.6, 0.5)

	var color_a: Color = base_color.darkened(CONTRAST_SHIFT)
	var color_b: Color = base_color.lightened(CONTRAST_SHIFT)

	_update_shader_parameter("bg_color_a", color_a)
	_update_shader_parameter("bg_color_b", color_b)


func _get_color_name_from_shader() -> String:
	if background_mesh == null:
		return "unknown"

	var active_mat: Material = background_mesh.get_active_material(0)
	var shader_mat: ShaderMaterial = active_mat as ShaderMaterial

	if shader_mat != null:
		var color_val: Variant = shader_mat.get_shader_parameter("bg_color_a")
		if color_val is Color:
			var c: Color = color_val as Color
			var h: float = c.h
			var s: float = c.s

			# If saturation is very low, it's a shade of grey
			if s < 0.15:
				return "grey"

			# Map hue to general color names
			if h < 0.05 or h > 0.95:
				return "red"
			if h < 0.15:
				return "orange"
			if h < 0.25:
				return "yellow"
			if h < 0.45:
				return "green"
			if h < 0.55:
				return "cyan"
			if h < 0.75:
				return "blue"
			if h < 0.85:
				return "purple"
			return "pink"

	return "default"


func _trigger_bake() -> void:
	print("_trigger_bake(): Preparing viewport for immediate capture.")

	# Guarantee the viewport matches the requested resolution before capturing
	size = Vector2i(output_resolution, output_resolution)
	render_target_update_mode = SubViewport.UPDATE_ONCE

	await RenderingServer.frame_post_draw

	var final_name: String = base_file_name

	if smart_auto_naming:
		# Detect Color
		var color_name: String = _get_color_name_from_shader()
		final_name += "_%s" % color_name

		# Detect Godiva Outline visibility
		if godiva_outline_mesh != null and godiva_outline_mesh.visible:
			final_name += "_with_godiva"

		# Append resolution and alpha state
		final_name += "_%s" % str(output_resolution)
		if transparent_grid_only:
			final_name += "_alpha"

	_bake_texture(final_name)


func _fit_camera_to_mesh() -> void:
	print("_fit_camera_to_mesh(): Calculating bounds for camera fitting.")

	if background_mesh == null or target_camera == null:
		print("_fit_camera_to_mesh(): ERROR - Missing target node assignments.")
		return

	var quad: QuadMesh = background_mesh.mesh as QuadMesh
	if quad == null:
		print("_fit_camera_to_mesh(): ERROR - background_mesh does not contain a QuadMesh.")
		return

	var max_dimension: float = maxf(quad.size.x, quad.size.y)
	target_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	target_camera.size = max_dimension

	var mesh_pos: Vector3 = background_mesh.global_position
	target_camera.global_position = Vector3(mesh_pos.x, mesh_pos.y, mesh_pos.z + 1.0)

	print("_fit_camera_to_mesh(): Success. Camera size set to ", max_dimension)


func _bake_texture(final_name: String) -> void:
	var raw_path: String = save_directory + "/" + final_name + ".png"
	var final_path: String = raw_path.replace("//", "/").replace("res:/", "res://")

	print("_bake_texture(): Processing target destination: ", final_path)

	var tex: ViewportTexture = get_texture()
	var img: Image = tex.get_image()

	if img == null or img.is_empty():
		print("_bake_texture(): ERROR - Viewport image is empty.")
		return

	img.linear_to_srgb()

	var err: Error = img.save_png(final_path)

	if err == OK:
		print("_bake_texture(): SUCCESS - Texture saved to ", final_path)
		EditorInterface.get_resource_filesystem().scan()
	else:
		print("_bake_texture(): ERROR - Failed to save. Godot Error Code: ", err)
