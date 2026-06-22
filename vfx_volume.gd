@tool
extends Area3D
class_name ColorGradingVolume3D

enum Preset {
	CUSTOM,
	BLACK_AND_WHITE,
	SEPIA,
	COLD,
	WARM
}

@export_category("Color Grading Volume")

## The custom color grading shader file (.gdshader).
@export var grading_shader: Shader:
	set(value):
		grading_shader = value
		_initialize_material()

@export var preset: Preset = Preset.CUSTOM:
	set(value):
		preset = value
		_apply_preset()

@export_group("Parameters")
@export var brightness: float = 1.0:
	set(value):
		brightness = value
		_update_shader_params()

@export var contrast: float = 1.0:
	set(value):
		contrast = value
		_update_shader_params()

@export var saturation: float = 1.0:
	set(value):
		saturation = value
		_update_shader_params()

@export var tint_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		tint_color = value
		_update_shader_params()

@export_group("Volume Control")
@export var blend_time: float = 1.0
@export var preview_in_editor: bool = false:
	set(value):
		preview_in_editor = value
		_update_editor_preview()

var _canvas_layer: CanvasLayer
var _back_buffer: BackBufferCopy
var _color_rect: ColorRect
var _blend_tween: Tween
var _material: ShaderMaterial


func _ready() -> void:
	print("ColorGradingVolume3D: Initializing node setup for screen overlay.")
	_setup_screen_ui()
	
	if Engine.is_editor_hint():
		return
		
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _setup_screen_ui() -> void:
	print("ColorGradingVolume3D: Spawning CanvasLayer, BackBufferCopy, and ColorRect.")
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 10 
	add_child(_canvas_layer)
	
	_back_buffer = BackBufferCopy.new()
	_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_canvas_layer.add_child(_back_buffer)
	
	_color_rect = ColorRect.new()
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.modulate.a = 0.0
	_color_rect.hide()
	
	_canvas_layer.add_child(_color_rect)
	_initialize_material()


func _initialize_material() -> void:
	if not is_inside_tree() or not _color_rect or not grading_shader:
		return
		
	if not _material:
		_material = ShaderMaterial.new()
		_color_rect.material = _material
		
	_material.shader = grading_shader
	_update_shader_params()
	_update_editor_preview()


func _update_shader_params() -> void:
	if not _material:
		return
		
	_material.set_shader_parameter("brightness", brightness)
	_material.set_shader_parameter("contrast", contrast)
	_material.set_shader_parameter("saturation", saturation)
	_material.set_shader_parameter("tint_color", tint_color)


func _apply_preset() -> void:
	if preset == Preset.CUSTOM:
		return
		
	match preset:
		Preset.BLACK_AND_WHITE:
			brightness = 1.0
			contrast = 1.2
			saturation = 0.0
			tint_color = Color(1.0, 1.0, 1.0, 1.0)
		Preset.SEPIA:
			brightness = 0.9
			contrast = 1.1
			saturation = 0.0
			tint_color = Color(1.2, 1.0, 0.8, 1.0)
		Preset.COLD:
			brightness = 1.0
			contrast = 1.05
			saturation = 0.9
			tint_color = Color(0.85, 0.9, 1.0, 1.0)
		Preset.WARM:
			brightness = 1.05
			contrast = 1.05
			saturation = 1.1
			tint_color = Color(1.0, 0.95, 0.85, 1.0)


func _update_editor_preview() -> void:
	if not is_inside_tree() or not _color_rect:
		return
		
	if Engine.is_editor_hint():
		if preview_in_editor and grading_shader:
			print("ColorGradingVolume3D: Enabling editor preview visibility.")
			_color_rect.show()
			_color_rect.modulate.a = 1.0
		else:
			print("ColorGradingVolume3D: Disabling editor preview visibility.")
			_color_rect.hide()
			_color_rect.modulate.a = 0.0


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		print("ColorGradingVolume3D: Player entered volume. Fading in VFX.")
		_fade_effect(1.0)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		print("ColorGradingVolume3D: Player exited volume. Fading out VFX.")
		_fade_effect(0.0)


func _fade_effect(target_alpha: float) -> void:
	print("ColorGradingVolume3D: Executing alpha fade to ", target_alpha)
	if target_alpha > 0.0:
		_color_rect.show()
		
	if _blend_tween and _blend_tween.is_valid():
		_blend_tween.kill()
		
	_blend_tween = create_tween()
	_blend_tween.tween_property(
		_color_rect, 
		"modulate:a", 
		target_alpha, 
		blend_time
	).set_trans(Tween.TRANS_SINE)
	
	if target_alpha <= 0.0:
		_blend_tween.tween_callback(_color_rect.hide)
