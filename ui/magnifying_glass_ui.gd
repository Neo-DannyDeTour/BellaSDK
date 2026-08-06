extends CanvasLayer
class_name MagnifyingGlassUI

@export_category("Zoom Settings")
## Minimum allowed zoom multiplier.
@export var min_zoom: float = 1.5
## Maximum allowed zoom multiplier.
@export var max_zoom: float = 5.0
## How much the zoom changes per mouse wheel scroll.
@export var zoom_step: float = 0.5

@export_category("Radius Settings")
## Minimum allowed radius for the glass on screen.
@export var min_radius: float = 0.1
## Maximum allowed radius for the glass on screen.
@export var max_radius: float = 0.4
## How much the radius changes per mouse wheel scroll.
@export var radius_step: float = 0.05

## Node reference to the full-screen ColorRect that holds the shader material.
@onready var glass_rect: ColorRect = $ColorRect

## Current active state of the magnifying glass overlay.
var _is_active: bool = false
## Current zoom multiplier passed to the shader.
var _current_zoom: float = 2.0
## Current radius of the magnifying glass passed to the shader.
var _current_radius: float = 0.15


func _ready() -> void:
	if is_instance_valid(glass_rect):
		glass_rect.hide()
	print("MagnifyingGlassUI: Initialized and hidden on ready.")


# Changed from _input to _unhandled_input so NoteReader can consume the event first
func _unhandled_input(event: InputEvent) -> void:
	# Toggle on Z press
	if event is InputEventKey and event.physical_keycode == KEY_Z:
		if event.pressed and not event.echo:
			_toggle_glass()
			
	if not _is_active:
		return
		
	# Handle mouse wheel scaling
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_glass(1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_glass(-1.0)


func _process(_delta: float) -> void:
	if _is_active and is_instance_valid(glass_rect) and glass_rect.material != null:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var screen_size: Vector2 = get_viewport().get_visible_rect().size
		
		# Convert standard mouse position into 0.0 to 1.0 UV space for the shader
		var mouse_uv: Vector2 = mouse_pos / screen_size
		var aspect: float = screen_size.x / screen_size.y
		
		glass_rect.material.set_shader_parameter("mouse_uv", mouse_uv)
		glass_rect.material.set_shader_parameter("aspect_ratio", aspect)


func _toggle_glass() -> void:
	_is_active = not _is_active
	
	if _is_active:
		if is_instance_valid(glass_rect):
			glass_rect.show()
			_update_shader_params()
		print("MagnifyingGlassUI: Glass ACTIVATED.")
	else:
		if is_instance_valid(glass_rect):
			glass_rect.hide()
		print("MagnifyingGlassUI: Glass DEACTIVATED.")


func _adjust_glass(direction: float) -> void:
	_current_zoom = clampf(_current_zoom + (zoom_step * direction), min_zoom, max_zoom)
	_current_radius = clampf(_current_radius + (radius_step * direction), min_radius, max_radius)
	
	_update_shader_params()
	print("MagnifyingGlassUI: Adjusted | Zoom: ", _current_zoom, " | Radius: ", _current_radius)


func _update_shader_params() -> void:
	if is_instance_valid(glass_rect) and glass_rect.material != null:
		glass_rect.material.set_shader_parameter("zoom", _current_zoom)
		glass_rect.material.set_shader_parameter("glass_radius_uv", _current_radius)
		print("MagnifyingGlassUI: Shader parameters updated in UI.")
