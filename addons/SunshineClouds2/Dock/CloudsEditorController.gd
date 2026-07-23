# gdlint: ignore=max-file-lines,max-public-methods,class-definitions-order
@tool
class_name CloudsEditorController
extends Control

enum DRAWINGMODE {NONE, WEIGHT, COLOR, SET_VALUE}
@export_category("Driver Tools")
@export var clouds_status_label : Label
@export var clouds_active_toggle : CheckButton
@export var clouds_driver_refresh : Button
@export var clouds_driver_accordian_button : AccordionButton
@export_category("Mask Tools")
@export var use_mask_toggle : CheckButton
@export var mask_status_label : Label
@export var mask_file_path : LineEdit
@export var mask_resolution : SpinBox
@export var mask_width : SpinBox
@export_category("Draw Tools")
@export var draw_weight_enable : TextureButton
@export var draw_color_enable : TextureButton
@export var draw_color_picker : ColorPicker
@export var draw_tools : Control
@export var draw_sharpness : HSlider
@export var draw_strength : HSlider
@export var compute_shader : RDShaderFile
@export var drawing_color : Color
@export var inverted_drawing_color : Color
@export_range(100,50000,50) var default_brush_size : float = 1000.0
@export_range(100,50000,50) var default_clouds_height : float = 2000.0
var driver : SunshineCloudsDriverGD
var current_root : Node
var current_drawing_mask : RID = RID()
var draw_scale : float
var current_clouds_height : float
var current_draw_mode : DRAWINGMODE = DRAWINGMODE.NONE
var drawing_currently : bool = false
var draw_inverted : bool = false
# gdlint: disable=max-line-length
var draw_brush_tool_material : BaseMaterial3D = preload("res://addons/SunshineClouds2/Dock/Materials/DrawBrushToolsMaterial.tres")
# gdlint: disable=max-line-length
var draw_brush_tool_prefab : PackedScene = preload("res://addons/SunshineClouds2/Dock/CloudsDrawBrush.tscn")
var draw_brush_tool : MeshInstance3D
var compute_enabled : bool = false
var rd : RenderingDevice
var shader : RID = RID()
var pipeline : RID = RID()
var uniform_set : RID
var push_constants : PackedByteArray
var last_image_data : PackedByteArray = []
var pause_updates : bool = false
func _enter_tree() -> void:
	draw_scale = default_brush_size
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(self):
		RenderingServer.call_on_render_thread(clear_compute)
func _process(delta: float) -> void:
	if (current_draw_mode != DRAWINGMODE.NONE):
		var selection: Variant = EditorInterface.get_selection()
		if (selection.get_selected_nodes().size() == 0):
			if (driver != null):
				selection.add_node(driver)
		if (current_draw_mode == DRAWINGMODE.COLOR):
			draw_brush_tool_material.albedo_color = draw_color_picker.color
		if (drawing_currently):
			RenderingServer.call_on_render_thread(execute_compute.bindv([delta, false,
				Color.WHITE]))
func initial_scene_load() -> void:
	var scene_root: Variant = await find_scene_node()
	scene_changed(scene_root)
	print("initial scene load")
	await get_tree().create_timer(0.5).timeout
	var version_info: Variant = Engine.get_version_info()
	var file = FileAccess.open("res://addons/SunshineClouds2/CloudsInc.comp", FileAccess.READ_WRITE)
	var content: Variant = file.get_as_text()
	var major_index: Variant = content.find("GODOT_VERSION_MAJOR") + 20
	var minor_index: Variant = content.find("GODOT_VERSION_MINOR") + 20
	# gdlint: disable=max-line-length
	if content[major_index] != str(version_info.major) || content[minor_index] != str(version_info.minor):
		print("Version conflict, updating and reimporting...")
		content[major_index] = str(version_info.major)
		content[minor_index] = str(version_info.minor)
		file.store_string(content)
		file.close()
		# gdlint: disable=max-line-length
		EditorInterface.get_resource_filesystem().reimport_files(["res://addons/SunshineClouds2/SunshineCloudsCompute.glsl", "res://addons/SunshineClouds2/SunshineCloudsPostCompute.glsl", "res://addons/SunshineClouds2/SunshineCloudsPostCompute.msaa.glsl", "res://addons/SunshineClouds2/SunshineCloudsPreCompute.glsl", "res://addons/SunshineClouds2/SunshineCloudsDisplay.glsl", "res://addons/SunshineClouds2/SunshineCloudsDisplay.msaa.glsl"])
		await get_tree().create_timer(0.1).timeout
		if driver != null && driver.clouds_resource != null:
			driver.clouds_resource.refresh_compute()
		# gdlint: disable=max-line-length
		print("Version updated, launching normally.")
	else:
		print("Version correct, launching normally.")
		file.close()
func refresh_scene_node() -> void:
	var scene_root: Variant = await find_scene_node()
	scene_changed(scene_root)
func find_scene_node() -> Node:
	var editor_interface: Variant = EditorPlugin.new().get_editor_interface()
	var scene_root: Variant = editor_interface.get_edited_scene_root()
	var iterationcount: int = 300 #30 seconds of checking.
	while scene_root == null && iterationcount > 0:
		await get_tree().create_timer(0.1).timeout
		iterationcount -= 1
		scene_root = editor_interface.get_edited_scene_root()
	return scene_root


func scene_changed(scene_root: Node) -> void:
	print("Executing scene_changed: Resetting UI state and retrieving clouds driver.")
	pause_updates = true
	
	# Safely check if UI elements are initialized before modifying them
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
			use_mask_toggle.button_pressed = driver.clouds_resource.extra_large_used_as_mask
			
	if is_instance_valid(mask_file_path) and ResourceLoader.exists(mask_file_path.text):
		var image: Image = ResourceLoader.load(mask_file_path.text) as Image
		if image and is_instance_valid(mask_resolution):
			print("Executing scene_changed: Retrieved mask scale successfully.")
			mask_resolution.value = image.get_width()
			
	pause_updates = false
	update_status_display()


func retrieve_clouds_driver(scene_root : Node) -> SunshineCloudsDriverGD:
	if (scene_root != null):
		for child in scene_root.get_children():
			if child is SunshineCloudsDriverGD:
				return child
			var new_driver: Variant = retrieve_clouds_driver(child)
			if (new_driver):
				return new_driver
	return null


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
			
		if is_instance_valid(clouds_driver_accordian_button):
			clouds_driver_accordian_button.open_accordion()
			
		if is_instance_valid(clouds_status_label):
			clouds_status_label.text = "Clouds not present"
			
	if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
		if is_instance_valid(use_mask_toggle):
			use_mask_toggle.disabled = false
	else:
		if is_instance_valid(use_mask_toggle):
			use_mask_toggle.disabled = true
			use_mask_toggle.button_pressed = false


func update_mask_settings():
	if (pause_updates):
		return
	print("Update mask settings")
	if (driver != null && driver.clouds_resource != null):
		driver.clouds_resource.mask_width_km = mask_width.value
		driver.clouds_resource.extra_large_used_as_mask = use_mask_toggle.button_pressed
		if (!use_mask_toggle.button_pressed):
			# gdlint: disable=max-line-length
			driver.clouds_resource.extra_large_noise_patterns = ResourceLoader.load("res://addons/SunshineClouds2/NoiseTextures/ExtraLargeScaleNoise.tres")
		elif ResourceLoader.exists(mask_file_path.text):
			# gdlint: disable=max-line-length
			driver.clouds_resource.extra_large_noise_patterns = ResourceLoader.load(mask_file_path.text)
	initialize_mask_texture()


func initialize_mask_texture():
	if not rd:
		rd = RenderingServer.get_rendering_device()
		if not rd:
			return
	print("initializing mask")
	if ResourceLoader.exists(mask_file_path.text):
		print("loading mask")
		var image: Variant = ResourceLoader.load(mask_file_path.text) as CompressedTexture2D
		if (!image || image.get_width() != mask_resolution.value):
			print(mask_file_path.text)
			# gdlint: disable=max-line-length
			print("mask incorrect size found size:",  image.get_width(), " desired:", mask_resolution.value)
			image = Image.create(mask_resolution.value, mask_resolution.value, false,
				Image.FORMAT_RGBAF)
			image.clear_mipmaps()
			image.save_exr(mask_file_path.text)
			var editor_file_system := EditorInterface.get_resource_filesystem()
			editor_file_system.scan()
	else:
		var image: Variant = Image.create(mask_resolution.value, mask_resolution.value, false,
			Image.FORMAT_RGBAF)
		image.clear_mipmaps()
		image.save_exr(mask_file_path.text)
		var editor_file_system := EditorInterface.get_resource_filesystem()
		editor_file_system.scan()
	RenderingServer.call_on_render_thread(initialize_compute)
	call_deferred("update_status_display")


func initialize_compute() -> void:
	compute_enabled = false
	if not rd:
		rd = RenderingServer.get_rendering_device()
		if not rd:
			compute_enabled = false
			printerr("No rendering device on load.")
			return
	clear_compute()
	if not compute_shader:
		# gdlint: disable=max-line-length
		compute_shader = ResourceLoader.load("res://addons/SunshineClouds2/Dock/MaskDrawingCompute.glsl")
	if not compute_shader:
		compute_enabled = false
		printerr("No Shader found for drawing tool.")
		clear_compute()
		return
	var shader_spirv: Variant = compute_shader.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	if shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)
	else:
		compute_enabled = false
		printerr("Shader failed to compile.")
		clear_compute()
		return
	var uniforms_array : Array[RDUniform] = []
	var new_format : RDTextureFormat = RDTextureFormat.new()
	new_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	new_format.height = mask_resolution.value
	new_format.width = mask_resolution.value
	# gdlint: disable=max-line-length
	new_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var image : Image
	if ResourceLoader.exists(mask_file_path.text):
		image = (ResourceLoader.load(mask_file_path.text) as CompressedTexture2D).get_image()
	if image == null:
		image = Image.create(mask_resolution.value, mask_resolution.value, false,
			Image.FORMAT_RGBAF)
	current_drawing_mask = rd.texture_create(new_format, RDTextureView.new(), [image.get_data()])
	if (driver != null && driver.clouds_resource != null):
		driver.clouds_resource.update_mask(current_drawing_mask)
	var mask_uniform: Variant = RDUniform.new()
	mask_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mask_uniform.binding = 0
	mask_uniform.add_id(current_drawing_mask)
	uniforms_array.append(mask_uniform)
	uniform_set = rd.uniform_set_create(uniforms_array, shader, 0)
	compute_enabled = true
func clear_compute() -> void:
	if rd:
		if shader.is_valid():
			rd.free_rid(shader)
		shader = RID()
		if current_drawing_mask.is_valid():
			rd.free_rid(current_drawing_mask)
		current_drawing_mask = RID()
func execute_compute(delta : float, setvalue : bool, setvalue_color : Color):
	if (!compute_enabled):
		return
	var resolution : float = mask_resolution.value
	var draw_position : Vector2 = Vector2.ZERO
	var draw_radius: float = 0.0
	if (!setvalue):
		draw_position = Vector2(draw_brush_tool.global_position.x,
			draw_brush_tool.global_position.z)
		draw_position = (draw_position / (mask_width.value * 1000.0)) * resolution
		draw_position += Vector2(resolution * 0.5, resolution * 0.5)
		draw_radius = (draw_brush_tool.scale.x / (mask_width.value * 1000.0)) * resolution
	var groups: Variant = ceil(resolution / 32) + 1
	var draw_sharpness_var: Variant = draw_sharpness.value
	var draw_strength_var: Variant = draw_strength.value * delta
	if (draw_inverted):
		draw_strength_var = -draw_strength_var
	var editingtype : float = 0.0
	if setvalue:
		editingtype = 2.0
	elif current_draw_mode == DRAWINGMODE.COLOR:
		editingtype = 1.0
	var ms: Variant = StreamPeerBuffer.new()
	ms.put_float(draw_position.x)
	ms.put_float(draw_position.y)
	ms.put_float(draw_radius)
	ms.put_float(draw_sharpness_var)
	ms.put_float(draw_strength_var)
	ms.put_float(editingtype)
	ms.put_float(resolution)
	ms.put_float(0.0)
	if (setvalue):
		ms.put_float(setvalue_color.r)
		ms.put_float(setvalue_color.g)
		ms.put_float(setvalue_color.b)
		ms.put_float(setvalue_color.a)
	else:
		ms.put_float(draw_color_picker.color.r)
		ms.put_float(draw_color_picker.color.g)
		ms.put_float(draw_color_picker.color.b)
		ms.put_float(0.0)
	push_constants = ms.get_data_array()
	var compute_list: Variant = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, groups, groups, 1)
	rd.compute_list_end()
	await RenderingServer.frame_post_draw
	rd.texture_get_data_async(current_drawing_mask, 0, complete_retrieval)


func complete_retrieval(data: PackedByteArray) -> void:
	last_image_data = data


func iterate_cursor_location(viewport_camera: Camera3D, event:InputEventMouse):
	if (is_instance_valid(driver) && driver.clouds_resource != null):
		current_clouds_height = (driver.clouds_resource.cloud_floor
			+ driver.clouds_resource.cloud_ceiling) / 2.0
	else:
		current_clouds_height = default_clouds_height
	var ray_origin: Variant = viewport_camera.project_ray_origin(event.position)
	var ray_dir: Variant = viewport_camera.project_ray_normal(event.position)
	var result : float = retrieve_travel_distance(ray_origin, ray_dir)
	if (result == -1.0):
		draw_brush_tool.visible = false
	else:
		draw_brush_tool.visible = true
		draw_brush_tool.global_position = ray_origin + ray_dir * result
		draw_brush_tool.global_position.y = driver.clouds_resource.cloud_floor


func begin_cursor_draw():
	drawing_currently = true


func end_cursor_draw():
	drawing_currently = false


func scale_drawing_circle_up():
	draw_scale = min(draw_scale + (draw_scale * 0.1), 100000.0)
	set_draw_scale()


func scale_drawing_circle_down():
	draw_scale = max(draw_scale - (draw_scale * 0.1), 100.0)
	set_draw_scale()


func draw_mode_cancel():
	draw_weight_enable.button_pressed = false
	draw_color_enable.button_pressed = false
	disable_draw_mode()


func set_draw_scale():
	if driver != null && driver.clouds_resource != null:
		draw_brush_tool.scale = Vector3(draw_scale,
			driver.clouds_resource.cloud_ceiling - driver.clouds_resource.cloud_floor, draw_scale)
	else:
		draw_brush_tool.scale = Vector3(draw_scale, 1000.0, draw_scale)


func flood_fill() -> void:
	var result_color : Color = draw_color_picker.color
	result_color.a = draw_strength.value / draw_strength.max_value
	RenderingServer.call_on_render_thread(execute_compute.bindv([0.0, true, result_color]))
	await get_tree().create_timer(0.2).timeout
	call_deferred("disable_draw_mode")
func draw_weight_toggled():
	draw_color_enable.button_pressed = false
	if draw_weight_enable.button_pressed && enable_draw_mode():
		current_draw_mode = DRAWINGMODE.WEIGHT
	else:
		draw_weight_enable.button_pressed = false
func draw_color_toggled():
	draw_weight_enable.button_pressed = false
	if draw_color_enable.button_pressed && enable_draw_mode():
		current_draw_mode = DRAWINGMODE.COLOR
	else:
		draw_color_enable.button_pressed = false
func enable_draw_mode() -> bool:
	if (!compute_enabled):
		initialize_mask_texture()
	if (!is_instance_valid(current_root)):
		return false
	draw_brush_tool_material.albedo_color = drawing_color
	if (!is_instance_valid(draw_brush_tool)):
		draw_brush_tool = draw_brush_tool_prefab.instantiate() as MeshInstance3D
		current_root.add_child(draw_brush_tool)
		set_draw_scale()
	return true


func disable_draw_mode() -> void:
	if is_instance_valid(draw_color_enable):
		draw_color_enable.button_pressed = false
		
	if is_instance_valid(draw_weight_enable):
		draw_weight_enable.button_pressed = false
		
	current_draw_mode = DRAWINGMODE.NONE
	draw_inverted = false
	
	if drawing_currently:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		drawing_currently = false
		
	if is_instance_valid(draw_brush_tool):
		draw_brush_tool.queue_free()
		draw_brush_tool = null
		
	if last_image_data.size() > 0:
		print("disable_draw_mode: Saved image to disc")
		var image: Image = Image.create_from_data(mask_resolution.value, mask_resolution.value, false, Image.FORMAT_RGBAF, last_image_data)
		image.save_exr(mask_file_path.text)
		var editor_file_system: EditorFileSystem = EditorInterface.get_resource_filesystem()
		editor_file_system.scan()
		last_image_data = PackedByteArray()
		
		if is_instance_valid(driver) and is_instance_valid(driver.clouds_resource):
			driver.clouds_resource.extra_large_noise_patterns = ResourceLoader.load(mask_file_path.text)


func set_draw_invert(mode : bool):
	if (current_draw_mode == DRAWINGMODE.WEIGHT && draw_inverted != mode):
		draw_inverted = mode
		# gdlint: disable=max-line-length
		draw_brush_tool_material.albedo_color = inverted_drawing_color if draw_inverted else drawing_color
func retrieve_travel_distance(pos : Vector3, dir :Vector3) -> float:
	var t : float = (current_clouds_height - pos.y) / dir.y
	if (dir.y == 0 || t < 0.0):
		return -1.0
	return t * dir.length()
func set_clouds_updating() -> void:
	if (driver != null):
		driver.update_continuously = clouds_active_toggle.button_pressed
	update_status_display()
