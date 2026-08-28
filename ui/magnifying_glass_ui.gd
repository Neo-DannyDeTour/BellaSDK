## Full-screen 2D magnifying glass overlay shader controller.
##
## Listens to [Events] to restrict activation exclusively to active note reading sessions.
class_name MagnifyingGlassUI
extends CanvasLayer

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
## Tracks whether the player is currently reading an inspected item.
var _is_holding_item: bool = false
## Current zoom multiplier passed to the shader.
var _current_zoom: float = 2.0
## Current radius of the magnifying glass passed to the shader.
var _current_radius: float = 0.15


## Initializes UI visibility and binds signal listeners to [Events].
func _ready() -> void:
	if is_instance_valid(glass_rect):
		glass_rect.hide()

	if Events.has_signal("note_opened"):
		Events.note_opened.connect(_on_note_opened)
	if Events.has_signal("note_closed"):
		Events.note_closed.connect(_on_note_closed)

	print("MagnifyingGlassUI: Initialized and connected to Events bus.")


## Listens for unhandled keyboard and mouse wheel inputs to control glass zoom.
## [param event] The unhandled [InputEvent] to process.
func _unhandled_input(event: InputEvent) -> void:
	if not _is_holding_item:
		return

	# Toggle on Z press only while an item is held
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


## Updates mouse position and aspect ratio uniforms on the shader material each frame.
## [param _delta] Frame delta time in seconds.
func _process(_delta: float) -> void:
	if _is_active and is_instance_valid(glass_rect) and glass_rect.material != null:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var screen_size: Vector2 = get_viewport().get_visible_rect().size

		var mouse_uv: Vector2 = mouse_pos / screen_size
		var aspect: float = screen_size.x / screen_size.y

		glass_rect.material.set_shader_parameter("mouse_uv", mouse_uv)
		glass_rect.material.set_shader_parameter("aspect_ratio", aspect)


## Callback triggered when a note or readable item is opened.
## [param _note_text] Text content sent by the opened note.
func _on_note_opened(_note_text: String) -> void:
	_is_holding_item = true
	print("MagnifyingGlassUI: Note opened. Magnifying glass interaction enabled.")


## Callback triggered when a note reading session is closed.
func _on_note_closed() -> void:
	_is_holding_item = false
	if _is_active:
		_toggle_glass()
	print("MagnifyingGlassUI: Note closed. Magnifying glass disabled.")


## Toggles visibility and active state of the 2D magnifying shader.
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


## Increments or decrements zoom factor and radius limits.
## [param direction] Direction multiplier (positive for zoom in, negative for zoom out).
func _adjust_glass(direction: float) -> void:
	_current_zoom = clampf(_current_zoom + (zoom_step * direction), min_zoom, max_zoom)
	_current_radius = clampf(_current_radius + (radius_step * direction), min_radius, max_radius)

	_update_shader_params()
	print("MagnifyingGlassUI: Adjusted | Zoom: ", _current_zoom, " | Radius: ", _current_radius)


## Pushes current zoom and radius values to the shader material parameters.
func _update_shader_params() -> void:
	if is_instance_valid(glass_rect) and glass_rect.material != null:
		glass_rect.material.set_shader_parameter("zoom", _current_zoom)
		glass_rect.material.set_shader_parameter("glass_radius_uv", _current_radius)
		print("MagnifyingGlassUI: Shader parameters updated in UI.")
