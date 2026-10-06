@tool
extends ColorRect
# #############################################################################
# Resize Handle control.  Place onto a control.  Set the orientation, then
# set the control that this should resize.  Then you can resize the control
# by dragging this thing around.  It's pretty neat.
# #############################################################################
enum ORIENTATION {
	LEFT,
	RIGHT
}

@export var orientation: Variant = ORIENTATION.RIGHT :
	get: return orientation
	set(val):
		orientation = val
		queue_redraw()
@export var resize_control : Control = null
@export var vertical_resize: bool = true

var _line_width: float = .5
var _line_color: Color = Color(.4, .4, .4)
var _active_line_color: Color = Color(.3, .3, .3)
var _invalid_line_color: Color = Color(1, 0, 0)

var _line_space: int = 3
var _num_lines: int = 8

var _mouse_down: bool = false
# Called when the node enters the scene tree for the first time.


func _draw() -> void:
	var c: Variant = _line_color
	if(resize_control == null):
		c = _invalid_line_color
	elif(_mouse_down):
		c = _active_line_color

	if(orientation == ORIENTATION.LEFT):
		_draw_resize_handle_left(c)
	else:
		_draw_resize_handle_right(c)


func _gui_input(event: InputEvent) -> void:
	if(resize_control == null):
		return

	if(orientation == ORIENTATION.LEFT):
		_handle_left_input(event)
	else:
		_handle_right_input(event)


# Draw the lines in the corner to show where you can
# drag to resize the dialog
func _draw_resize_handle_right(draw_color: Variant) -> void:
	var br: Variant = size

	for i in range(_num_lines):
		var start: Variant = br - Vector2(i * _line_space, 0)
		var end: Variant = br - Vector2(0, i * _line_space)
		draw_line(start, end, draw_color, _line_width, true)


func _draw_resize_handle_left(draw_color: Variant) -> void:
	var bl: Vector2 = Vector2(0, size.y)

	for i in range(_num_lines):
		var start: Variant = bl + Vector2(i * _line_space, 0)
		var end: Variant = bl -  Vector2(0, i * _line_space)
		draw_line(start, end, draw_color, _line_width, true)


func _handle_right_input(event : InputEvent) -> void:
	if(event is InputEventMouseMotion):
		if(_mouse_down and
			event.global_position.x > 0 and
			event.global_position.y < DisplayServer.window_get_size().y):

			if(vertical_resize):
				resize_control.size.y += event.relative.y
			resize_control.size.x += event.relative.x
	elif(event is InputEventMouseButton):
		if(event.button_index == MOUSE_BUTTON_LEFT):
			_mouse_down = event.pressed
			queue_redraw()


func _handle_left_input(event : InputEvent) -> void:
	if(event is InputEventMouseMotion):
		if(_mouse_down and
			event.global_position.x > 0 and
			event.global_position.y < DisplayServer.window_get_size().y):

			var start_size: Variant = resize_control.size
			resize_control.size.x -= event.relative.x
			if(resize_control.size.x != start_size.x):
				resize_control.global_position.x += event.relative.x

			if(vertical_resize):
				resize_control.size.y += event.relative.y
	elif(event is InputEventMouseButton):
		if(event.button_index == MOUSE_BUTTON_LEFT):
			_mouse_down = event.pressed
			queue_redraw()
