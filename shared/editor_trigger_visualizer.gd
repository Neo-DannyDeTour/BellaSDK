@tool
class_name EditorTriggerVisualizer
extends MeshInstance3D

@export_category("Trigger Visuals")
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_mesh()

@export var trigger_color: Color = Color(1.0, 0.5, 0.0, 0.8):
	set(value):
		trigger_color = value
		_update_material()

@export var trigger_text: String = "TRIGGER":
	set(value):
		trigger_text = value
		_update_material()

var _viewport: SubViewport
var _bg_rect: ColorRect
var _text_label: Label
var _trigger_material: StandardMaterial3D


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
		
	_setup_nodes()
	_update_mesh()
	_update_material()


func _setup_nodes() -> void:
	_viewport = SubViewport.new()
	# Increased resolution to 512 for crisp text
	_viewport.size = Vector2i(512, 512)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	
	_bg_rect = ColorRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_bg_rect)
	
	_text_label = Label.new()
	_text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Scaled up font size to match the new 512x512 viewport
	_text_label.add_theme_font_size_override("font_size", 84)
	_text_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8))
	_viewport.add_child(_text_label)
	
	_trigger_material = StandardMaterial3D.new()
	_trigger_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trigger_material.albedo_texture = _viewport.get_texture()
	_trigger_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Disabled triplanar; standard dynamic UVs map beautifully to BoxMeshes
	_trigger_material.uv1_triplanar = false


func _update_mesh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
		
	if not mesh:
		mesh = BoxMesh.new()
		
	if mesh is BoxMesh:
		var box := mesh as BoxMesh
		box.size = trigger_size
		
	if _trigger_material:
		# Dynamically scale the texture so it tiles exactly once every 2 meters
		_trigger_material.uv1_scale = trigger_size / 2.0
		set_surface_override_material(0, _trigger_material)


func _update_material() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or not _viewport:
		return
		
	_bg_rect.color = trigger_color
	_text_label.text = trigger_text
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
