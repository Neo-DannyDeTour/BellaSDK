## Editor dock controller managing brush tools, mask painting, and cloud driver bindings.
##
## Provides a real-time viewport painting interface to author 2D mask density
## textures and synchronize parameters directly with [SunshineCloudsDriverGD].
@tool
class_name CloudsEditorController
extends Control

## Available painting modes for viewport brush interactions.
enum DrawingMode {
	## No painting tool active; standard editor camera navigation.
	NONE,
	## Paint scalar cloud weight and density values into the mask.
	WEIGHT,
	## Paint RGB color tint values into the mask.
	COLOR,
	## Direct flood-fill assignment across the entire mask resolution.
	SET_VALUE,
}

## Legacy enum alias for backward compatibility.
const DRAWINGMODE = DrawingMode

@export_category("Driver Tools")
## Label displaying active cloud driver registration status.
@export var clouds_status_label: Label

## Toggle button controlling continuous cloud simulation updates.
@export var clouds_active_toggle: CheckButton

## Button prompting a manual rescan and driver attachment.
@export var clouds_driver_refresh: Button

## Accordion folding container for driver property sections.
@export var clouds_driver_accordian_button: Button

@export_category("Mask Tools")
## Toggle button enabling authored mask texture overriding.
@export var use_mask_toggle: CheckButton

## Label displaying mask file path and resolution status.
@export var mask_status_label: Label

## File path input pointing to the active `.exr` mask texture.
@export var mask_file_path: LineEdit

## Pixel resolution input for authored mask image buffers.
@export var mask_resolution: SpinBox

## World-space width of the authored mask projection in kilometers.
@export var mask_width: SpinBox

@export_category("Draw Tools")
## Button toggling scalar weight painting mode.
@export var draw_weight_enable: TextureButton

## Button toggling RGB color painting mode.
@export var draw_color_enable: TextureButton

## Color picker selecting the active RGB brush tint.
@export var draw_color_picker: ColorPicker

## Parent container for brush adjustment sliders and controls.
@export var draw_tools: Control

## Slider adjusting the brush hardness falloff exponent.
@export var draw_sharpness: HSlider

## Slider adjusting the brush density deposit strength per second.
@export var draw_strength: HSlider

## Compute shader performing rasterization of brush stamps into the mask.
@export var compute_shader: RDShaderFile

## Primary gizmo color representing additive brush deposits.
@export var drawing_color: Color = Color(0.2, 0.6, 1.0, 0.8)

## Inverted gizmo color representing subtractive brush carving.
@export var inverted_drawing_color: Color = Color(1.0, 0.3, 0.2, 0.8)

## Default brush radius in world units.
@export_range(100.0, 50000.0, 50.0, "suffix:m") var default_brush_size: float = 1000.0

## Default altitude in world units where the brush gizmo projects.
@export_range(100.0, 50000.0, 50.0, "suffix:m") var default_clouds_height: float = 2000.0

## Active [SunshineCloudsDriverGD] instance found in the edited scene tree.
var driver: SunshineCloudsDriverGD

## Root node of the currently edited scene in the editor viewport.
var current_root: Node

## Rendering device handle for the GPU mask storage texture.
var current_drawing_mask: RID = RID()

## Current radius of the viewport brush gizmo in world units.
var draw_scale: float = 1000.0

## Current plane altitude in world units where the brush cursor projects.
var current_clouds_height: float = 2000.0

## The active painting mode selected in the editor dock.
var current_draw_mode: DrawingMode = DrawingMode.NONE

## Tracks whether a continuous brush stroke is currently being held down.
var drawing_currently: bool = false

## Flags whether the active brush is inverted to carve/erase density.
var draw_inverted: bool = false

## Material applied to the viewport brush projection mesh.
var draw_brush_tool_material: BaseMaterial3D = preload(
	"res://addons/SunshineClouds2/Dock/Materials/DrawBrushToolsMaterial.tres"
)

## Packed scene containing the brush cylinder gizmo mesh.
var draw_brush_tool_prefab: PackedScene = preload(
	"res://addons/SunshineClouds2/Dock/CloudsDrawBrush.tscn"
)

## Instantiated brush cylinder gizmo mesh in the editor scene.
var draw_brush_tool: MeshInstance3D

## Flags whether the compute pipeline is compiled and ready for dispatch.
var compute_enabled: bool = false

## Rendering device handle for compute shader dispatch.
var rd: RenderingDevice

## Shader resource handle for the mask drawing compute shader. Needs manual cleanup.
var shader: RID = RID()

## Compute pipeline handle for mask stamp rasterization. Needs manual cleanup.
var pipeline: RID = RID()

## Uniform set binding the mask storage image to the compute pipeline. Needs manual cleanup.
var uniform_set: RID = RID()

## Encoded push constant byte array passing brush stroke parameters.
var push_constants: PackedByteArray = PackedByteArray()

## Raw byte buffer cached from the latest GPU mask readback.
var last_image_data: PackedByteArray = PackedByteArray()

## Mutex flag preventing recursive UI updates during scene initialization.
var pause_updates: bool = false

# --- Lifecycle Callbacks ---


## Initializes default brush dimensions upon entering the scene tree.
func _enter_tree() -> void:
	draw_scale = default_brush_size


## Clears GPU compute allocations when the control node is removed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(self):
		RenderingServer.call_on_render_thread(clear_compute)


## Manages editor node selection and continuous brush stamp dispatches.
func _process(delta: float) -> void:
	if current_draw_mode != DrawingMode.NONE:
		var selection: EditorSelection = EditorInterface.get_selection()
		if selection.get_selected_nodes().is_empty() and is_instance_valid(driver):
			selection.add_node(driver)

		if current_draw_mode == DrawingMode.COLOR and is_instance_valid(draw_color_picker):
			draw_brush_tool_material.albedo_color = draw_color_picker.color

		if drawing_currently:
			RenderingServer.call_on_render_thread(execute_compute.bind(delta, false, Color.WHITE))


# --- Scene Scanning & Initialization ---


## Performs initial scene tree inspection and validates engine version compatibility.
func initial_scene_load() -> void:
	print("CloudsEditorController: Performing initial scene load.")
	var scene_root: Node = await find_scene_node()
	scene_changed(scene_root)

	await get_tree().create_timer(0.5).timeout
	var version_info: Dictionary = Engine.get_version_info()
	var file_path: String = "res://addons/SunshineClouds2/CloudsInc.comp"

	if not FileAccess.file_exists(file_path):
		return

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ_WRITE)
	if file == null:
		return

	var content: String = file.get_as_text()
	var major_index: int = content.find("GODOT_VERSION_MAJOR") + 20
	var minor_index: int = content.find("GODOT_VERSION_MINOR") + 20

	var needs_update: bool = (
		content[major_index] != str(version_info.major)
		or content[minor_index] != str(version_info.minor)
	)

	if needs_update:
		print("CloudsEditorController: Engine version mismatch. Updating shader header...")
		content[major_index] = str(version_info.major)
		content[minor_index] = str(version_info.minor)
		file.store_string(content)
		file.close()

		var reimport_paths: PackedStringArray = [
			"res://addons/SunshineClouds2/SunshineCloudsCompute.glsl",
			"res://addons/SunshineClouds2/SunshineCloudsPostCompute.glsl",
			"res://addons/SunshineClouds2/SunshineCloudsPostCompute.msaa.glsl",
			"res://addons/SunshineClouds2/SunshineCloudsPreCompute.glsl",
			"res://addons/SunshineClouds2/SunshineCloudsDisplay.glsl",
			"res://addons/SunshineClouds2/SunshineCloudsDisplay.msaa.glsl"
		]
		EditorInterface.get_resource_filesystem().reimport_files(reimport_paths)
		await get_tree().create_timer(0.1).timeout

		if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
			driver.clouds_resource.refresh_compute()
		print("CloudsEditorController: Shader definitions updated successfully.")
	else:
		file.close()


## Refreshes driver bindings when the active edited scene changes.
func refresh_scene_node() -> void:
	print("CloudsEditorController: Manually refreshing scene node.")
	var scene_root: Node = await find_scene_node()
	scene_changed(scene_root)


## Polls the editor interface until the active scene root is available.
func find_scene_node() -> Node:
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	var iteration_count: int = 300
	while scene_root == null and iteration_count > 0:
		await get_tree().create_timer(0.1).timeout
		iteration_count -= 1
		scene_root = EditorInterface.get_edited_scene_root()
	return scene_root


## Updates dock state, UI controls, and driver handles when [param scene_root] changes.
func scene_changed(scene_root: Node) -> void:
	print("CloudsEditorController: Resetting UI state and retrieving clouds driver.")
	pause_updates = true

	if is_instance_valid(draw_weight_enable):
		draw_weight_enable.button_pressed = false

	if is_instance_valid(draw_color_enable):
		draw_color_enable.button_pressed = false

	last_image_data = PackedByteArray()
	disable_draw_mode()
	current_root = scene_root
	driver = retrieve_clouds_driver(scene_root)

	if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
		driver.clouds_resource.mask_drawn_rid = RID()

		if is_instance_valid(mask_width):
			mask_width.value = driver.clouds_resource.mask_width_km

		if is_instance_valid(use_mask_toggle):
			use_mask_toggle.button_pressed = (driver.clouds_resource.extra_large_used_as_mask)

	if is_instance_valid(mask_file_path) and ResourceLoader.exists(mask_file_path.text):
		var image: Image = ResourceLoader.load(mask_file_path.text) as Image
		if image and is_instance_valid(mask_resolution):
			mask_resolution.value = image.get_width()

	pause_updates = false
	update_status_display()


## Recursively searches down scene tree node [param scene_root] to locate a Driver.
func retrieve_clouds_driver(scene_root: Node) -> SunshineCloudsDriverGD:
	if scene_root == null:
		return null

	for child: Node in scene_root.get_children():
		if child is SunshineCloudsDriverGD:
			return child as SunshineCloudsDriverGD
		var new_driver: SunshineCloudsDriverGD = retrieve_clouds_driver(child)
		if new_driver != null:
			return new_driver
	return null


## Refreshes the visual labels, toggles, and tool groups in the dock UI.
func update_status_display() -> void:
	if is_instance_valid(driver):
		if is_instance_valid(clouds_active_toggle):
			clouds_active_toggle.disabled = false
			clouds_active_toggle.button_pressed = driver.update_continuously

		if is_instance_valid(clouds_driver_refresh):
			clouds_driver_refresh.visible = false

		if is_instance_valid(clouds_status_label):
			clouds_status_label.text = "Clouds present"

		if is_instance_valid(mask_file_path) and ResourceLoader.exists(mask_file_path.text):
			if is_instance_valid(mask_status_label):
				mask_status_label.text = "Mask Detected: " + mask_file_path.text
			if is_instance_valid(draw_tools):
				draw_tools.visible = true
		else:
			if is_instance_valid(mask_status_label):
				mask_status_label.text = "Mask Not Found."
			if is_instance_valid(draw_tools):
				draw_tools.visible = false
	else:
		if is_instance_valid(clouds_active_toggle):
			clouds_active_toggle.disabled = true
			clouds_active_toggle.button_pressed = false

		if is_instance_valid(clouds_driver_refresh):
			clouds_driver_refresh.visible = true

		if is_instance_valid(draw_tools):
			draw_tools.visible = false

		if is_instance_valid(clouds_status_label):
			clouds_status_label.text = "Clouds not present"

	if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
		if is_instance_valid(use_mask_toggle):
			use_mask_toggle.disabled = false
	else:
		if is_instance_valid(use_mask_toggle):
			use_mask_toggle.disabled = true
			use_mask_toggle.button_pressed = false


# --- Mask Management & Compute Pipeline ---


## Synchronizes mask projection dimensions and noise patterns with the cloud resource.
func update_mask_settings() -> void:
	if pause_updates:
		return

	print("CloudsEditorController: Updating mask settings.")
	if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
		if is_instance_valid(mask_width):
			driver.clouds_resource.mask_width_km = float(mask_width.value)

		if is_instance_valid(use_mask_toggle):
			driver.clouds_resource.extra_large_used_as_mask = (use_mask_toggle.button_pressed)

			if not use_mask_toggle.button_pressed:
				driver.clouds_resource.extra_large_noise_patterns = (ResourceLoader.load(
					"res://addons/SunshineClouds2/NoiseTextures/ExtraLargeScaleNoise.tres"
				))
			elif is_instance_valid(mask_file_path) and ResourceLoader.exists(mask_file_path.text):
				driver.clouds_resource.extra_large_noise_patterns = (ResourceLoader.load(
					mask_file_path.text
				))

	initialize_mask_texture()


## Creates or resizes the active mask image file and triggers compute shader setup.
func initialize_mask_texture() -> void:
	if not rd:
		rd = RenderingServer.get_rendering_device()
		if not rd:
			return

	print("CloudsEditorController: Initializing mask texture.")
	var res: int = int(mask_resolution.value) if is_instance_valid(mask_resolution) else 1024
	var path: String = mask_file_path.text if is_instance_valid(mask_file_path) else ""

	if ResourceLoader.exists(path):
		var image: Image = Image.load_from_file(path)
		if image == null or image.get_width() != res:
			print("CloudsEditorController: Mask dimension mismatch. Recreating EXR...")
			image = Image.create(res, res, false, Image.FORMAT_RGBAF)
			image.save_exr(path)
			EditorInterface.get_resource_filesystem().scan()
	elif path != "":
		var image: Image = Image.create(res, res, false, Image.FORMAT_RGBAF)
		image.save_exr(path)
		EditorInterface.get_resource_filesystem().scan()

	RenderingServer.call_on_render_thread(initialize_compute)
	call_deferred(&"update_status_display")


## Compiles the mask drawing compute pipeline and creates the GPU storage texture.
func initialize_compute() -> void:
	compute_enabled = false
	if not rd:
		rd = RenderingServer.get_rendering_device()
		if not rd:
			printerr("CloudsEditorController: No RenderingDevice available.")
			return

	clear_compute()

	if not compute_shader:
		compute_shader = ResourceLoader.load(
			"res://addons/SunshineClouds2/Dock/MaskDrawingCompute.glsl"
		)
	if not compute_shader:
		printerr("CloudsEditorController: Missing compute shader for mask drawing.")
		clear_compute()
		return

	var shader_spirv: RDShaderSPIRV = compute_shader.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	if shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)
	else:
		printerr("CloudsEditorController: Drawing compute shader failed to compile.")
		clear_compute()
		return

	var res: int = int(mask_resolution.value) if is_instance_valid(mask_resolution) else 1024
	var new_format: RDTextureFormat = RDTextureFormat.new()
	new_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	new_format.width = res
	new_format.height = res
	new_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)

	var path: String = mask_file_path.text if is_instance_valid(mask_file_path) else ""
	var image: Image
	if ResourceLoader.exists(path):
		image = Image.load_from_file(path)
	if image == null:
		image = Image.create(res, res, false, Image.FORMAT_RGBAF)

	current_drawing_mask = rd.texture_create(new_format, RDTextureView.new(), [image.get_data()])

	if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
		driver.clouds_resource.update_mask(current_drawing_mask)

	var mask_uniform: RDUniform = RDUniform.new()
	mask_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mask_uniform.binding = 0
	mask_uniform.add_id(current_drawing_mask)

	uniform_set = rd.uniform_set_create([mask_uniform], shader, 0)
	compute_enabled = true


## Frees rendering device pipeline, shader, and drawing mask allocations.
func clear_compute() -> void:
	print("CloudsEditorController: Freeing GPU resources to prevent VRAM leak.")
	if rd:
		if pipeline.is_valid():
			rd.free_rid(pipeline)
		pipeline = RID()
		if shader.is_valid():
			rd.free_rid(shader)
		shader = RID()
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
		uniform_set = RID()
		if current_drawing_mask.is_valid():
			rd.free_rid(current_drawing_mask)
		current_drawing_mask = RID()


## Dispatches the compute shader to stamp brush strokes or flood-fill into the mask texture.
func execute_compute(delta: float, set_value: bool, set_value_color: Color) -> void:
	if not compute_enabled or not pipeline.is_valid():
		return

	var res: float = mask_resolution.value if is_instance_valid(mask_resolution) else 1024.0
	var width_km: float = mask_width.value if is_instance_valid(mask_width) else 32.0
	var width_meters: float = maxf(width_km * 1000.0, 1.0)

	var draw_position: Vector2 = Vector2.ZERO
	var draw_radius: float = 0.0

	if not set_value and is_instance_valid(draw_brush_tool):
		draw_position = Vector2(
			draw_brush_tool.global_position.x, draw_brush_tool.global_position.z
		)
		draw_position = (draw_position / width_meters) * res
		draw_position += Vector2(res * 0.5, res * 0.5)
		draw_radius = (draw_brush_tool.scale.x / width_meters) * res

	var groups: int = int(ceilf(res / 32.0)) + 1
	var sharpness_val: float = draw_sharpness.value if is_instance_valid(draw_sharpness) else 1.0
	var strength_val: float = (
		draw_strength.value * delta if is_instance_valid(draw_strength) else delta
	)

	if draw_inverted:
		strength_val = -strength_val

	var editing_type: float = 0.0
	if set_value:
		editing_type = 2.0
	elif current_draw_mode == DrawingMode.COLOR:
		editing_type = 1.0

	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_float(draw_position.x)
	buffer.put_float(draw_position.y)
	buffer.put_float(draw_radius)
	buffer.put_float(sharpness_val)
	buffer.put_float(strength_val)
	buffer.put_float(editing_type)
	buffer.put_float(res)
	buffer.put_float(0.0)

	if set_value:
		buffer.put_float(set_value_color.r)
		buffer.put_float(set_value_color.g)
		buffer.put_float(set_value_color.b)
		buffer.put_float(set_value_color.a)
	elif is_instance_valid(draw_color_picker):
		buffer.put_float(draw_color_picker.color.r)
		buffer.put_float(draw_color_picker.color.g)
		buffer.put_float(draw_color_picker.color.b)
		buffer.put_float(0.0)
	else:
		buffer.put_float(1.0)
		buffer.put_float(1.0)
		buffer.put_float(1.0)
		buffer.put_float(0.0)

	push_constants = buffer.get_data_array()

	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, groups, groups, 1)
	rd.compute_list_end()

	await RenderingServer.frame_post_draw
	if current_drawing_mask.is_valid():
		rd.texture_get_data_async(current_drawing_mask, 0, complete_retrieval)


## Async callback receiving readback byte [param data] from the drawing mask texture.
func complete_retrieval(data: PackedByteArray) -> void:
	last_image_data = data


# --- Viewport Interaction & Brush Gizmo ---


## Projects a ray from [param viewport_camera] at [param event] position to place the brush gizmo.
func iterate_cursor_location(viewport_camera: Camera3D, event: InputEventMouse) -> void:
	if not is_instance_valid(viewport_camera) or not is_instance_valid(draw_brush_tool):
		return

	if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
		current_clouds_height = (
			(driver.clouds_resource.cloud_floor + driver.clouds_resource.cloud_ceiling) * 0.5
		)
	else:
		current_clouds_height = default_clouds_height

	var ray_origin: Vector3 = viewport_camera.project_ray_origin(event.position)
	var ray_dir: Vector3 = viewport_camera.project_ray_normal(event.position)
	var dist: float = retrieve_travel_distance(ray_origin, ray_dir)

	if dist < 0.0:
		draw_brush_tool.visible = false
	else:
		draw_brush_tool.visible = true
		draw_brush_tool.global_position = ray_origin + ray_dir * dist
		if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
			draw_brush_tool.global_position.y = driver.clouds_resource.cloud_floor


## Begins continuous brush stamp recording.
func begin_cursor_draw() -> void:
	print("CloudsEditorController: Starting brush stroke.")
	drawing_currently = true


## Terminates active brush stamp recording.
func end_cursor_draw() -> void:
	print("CloudsEditorController: Ending brush stroke.")
	drawing_currently = false


## Increases the brush circle radius by 10%.
func scale_drawing_circle_up() -> void:
	draw_scale = minf(draw_scale * 1.1, 100000.0)
	set_draw_scale()


## Decreases the brush circle radius by 10%.
func scale_drawing_circle_down() -> void:
	draw_scale = maxf(draw_scale * 0.9, 100.0)
	set_draw_scale()


## Cancels active drawing mode and resets tool buttons.
func draw_mode_cancel() -> void:
	print("CloudsEditorController: Cancelling draw mode.")
	if is_instance_valid(draw_weight_enable):
		draw_weight_enable.button_pressed = false
	if is_instance_valid(draw_color_enable):
		draw_color_enable.button_pressed = false
	disable_draw_mode()


## Updates the scale transform of the viewport brush cylinder mesh.
func set_draw_scale() -> void:
	if not is_instance_valid(draw_brush_tool):
		return

	var height: float = 1000.0
	if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
		height = (driver.clouds_resource.cloud_ceiling - driver.clouds_resource.cloud_floor)

	draw_brush_tool.scale = Vector3(draw_scale, maxf(height, 10.0), draw_scale)


## Executes an instantaneous flood fill across the entire mask texture.
func flood_fill() -> void:
	print("CloudsEditorController: Performing mask flood fill.")
	var fill_color: Color = (
		draw_color_picker.color if is_instance_valid(draw_color_picker) else Color.WHITE
	)
	if is_instance_valid(draw_strength):
		fill_color.a = draw_strength.value / draw_strength.max_value

	RenderingServer.call_on_render_thread(execute_compute.bind(0.0, true, fill_color))
	await get_tree().create_timer(0.2).timeout
	call_deferred(&"disable_draw_mode")


## Toggles scalar weight painting mode.
func draw_weight_toggled() -> void:
	if not is_instance_valid(draw_weight_enable):
		return

	if is_instance_valid(draw_color_enable):
		draw_color_enable.button_pressed = false

	if draw_weight_enable.button_pressed and enable_draw_mode():
		current_draw_mode = DrawingMode.WEIGHT
		print("CloudsEditorController: Activated Weight painting mode.")
	else:
		draw_weight_enable.button_pressed = false


## Toggles RGB color painting mode.
func draw_color_toggled() -> void:
	if not is_instance_valid(draw_color_enable):
		return

	if is_instance_valid(draw_weight_enable):
		draw_weight_enable.button_pressed = false

	if draw_color_enable.button_pressed and enable_draw_mode():
		current_draw_mode = DrawingMode.COLOR
		print("CloudsEditorController: Activated Color painting mode.")
	else:
		draw_color_enable.button_pressed = false


## Instantiates the brush gizmo mesh and enables viewport drawing mode.
func enable_draw_mode() -> bool:
	if not compute_enabled:
		initialize_mask_texture()
	if not is_instance_valid(current_root):
		return false

	draw_brush_tool_material.albedo_color = drawing_color

	if not is_instance_valid(draw_brush_tool):
		draw_brush_tool = draw_brush_tool_prefab.instantiate() as MeshInstance3D
		current_root.add_child(draw_brush_tool)
		set_draw_scale()

	return true


## Disables viewport drawing mode and saves modified mask data to disk.
func disable_draw_mode() -> void:
	if is_instance_valid(draw_color_enable):
		draw_color_enable.button_pressed = false

	if is_instance_valid(draw_weight_enable):
		draw_weight_enable.button_pressed = false

	current_draw_mode = DrawingMode.NONE
	draw_inverted = false

	if drawing_currently:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		drawing_currently = false

	if is_instance_valid(draw_brush_tool):
		draw_brush_tool.queue_free()
		draw_brush_tool = null

	if last_image_data.size() > 0:
		print("CloudsEditorController: Saving modified mask texture to disk.")
		var res: int = int(mask_resolution.value) if is_instance_valid(mask_resolution) else 1024
		var path: String = mask_file_path.text if is_instance_valid(mask_file_path) else ""

		if path != "":
			var image: Image = Image.create_from_data(
				res, res, false, Image.FORMAT_RGBAF, last_image_data
			)
			image.save_exr(path)
			var editor_fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
			editor_fs.scan()
			last_image_data = PackedByteArray()

			if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
				driver.clouds_resource.extra_large_noise_patterns = (ResourceLoader.load(path))


## Sets brush inversion mode [param mode] and updates the gizmo color tint.
func set_draw_invert(mode: bool) -> void:
	if current_draw_mode == DrawingMode.WEIGHT and draw_inverted != mode:
		draw_inverted = mode
		draw_brush_tool_material.albedo_color = (
			inverted_drawing_color if draw_inverted else drawing_color
		)


## Calculates ray-plane intersection distance from [param pos] along [param dir].
func retrieve_travel_distance(pos: Vector3, dir: Vector3) -> float:
	if absf(dir.y) < 0.00001:
		return -1.0
	var t: float = (current_clouds_height - pos.y) / dir.y
	if t < 0.0:
		return -1.0
	return t * dir.length()


## Toggles continuous cloud simulation updates on the tracked driver.
func set_clouds_updating() -> void:
	if is_instance_valid(driver) and is_instance_valid(clouds_active_toggle):
		driver.update_continuously = clouds_active_toggle.button_pressed
	update_status_display()
