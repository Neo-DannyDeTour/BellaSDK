@tool
extends MeshInstance3D
class_name EditorTriggerVisualizer

@export_category("Trigger Visuals")

@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		_update_mesh()
		_update_material()

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
	if not Engine.is_editor_hint() and not show_in_game:
		queue_free()
		return
		
	if not Engine.is_editor_hint() and show_in_game:
		print("Initializing EditorTriggerVisualizer: ", trigger_text)

	_setup_nodes()
	_update_mesh()
	_update_material()


func _setup_nodes() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(512, 512)
	_viewport.transparent_bg = true
	# Keeps performance high by only rendering when properties change
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	
	_bg_rect = ColorRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_bg_rect)
	
	_text_label = Label.new()
	_text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Forces long text strings to wrap to the next line safely
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text_label.add_theme_font_size_override("font_size", 64)
	_text_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8))
	_viewport.add_child(_text_label)
	
	_trigger_material = StandardMaterial3D.new()
	_trigger_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trigger_material.albedo_texture = _viewport.get_texture()
	_trigger_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Triplanar mapping stops the texture from stretching on non-cube rectangular faces
	_trigger_material.uv1_triplanar = true


func _update_mesh() -> void:
	if not is_inside_tree():
		return
	if not Engine.is_editor_hint() and not show_in_game:
		return
		
	if not mesh:
		mesh = BoxMesh.new()
		
	if mesh is BoxMesh:
		var box: BoxMesh = mesh as BoxMesh
		box.size = trigger_size
		
	if _trigger_material:
		# A static scale ensures uniform text rendering via triplanar
		_trigger_material.uv1_scale = Vector3(0.5, 0.5, 0.5)
		set_surface_override_material(0, _trigger_material)


func _update_material() -> void:
	if not is_inside_tree() or not _viewport:
		return
	if not Engine.is_editor_hint() and not show_in_game:
		return
		
	_bg_rect.color = trigger_color
	_text_label.text = trigger_text
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
