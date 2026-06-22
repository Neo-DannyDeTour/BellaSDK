extends ScrollContainer
class_name AutoScrollContainer

@export var animate: bool = true
@export var transition_time: float = 0.2
@export var gamepad_scroll_speed: int = 5
@export var gamepad_scroll_deadzone: float = 0.1

var scrollable: Control = null
var _last_input_event: InputEvent = null
var gamepad_scroll: float = 0.0


func _ready() -> void:
	if get_child_count() > 0 and get_child(0) is Control:
		scrollable = get_child(0) as Control
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func _get_position_relative_to_control(a: Control, b: Control) -> Vector2:
	return b.get_global_rect().position - a.get_global_rect().position 


func _on_focus_changed(focus: Control) -> void:
	if _last_input_event is InputEventMouseButton:
		return
		
	if not scrollable:
		return
		
	var scroll_destination: int = int(_get_position_relative_to_control(scrollable, focus).y - (get_rect().size.y / 2.0))
	
	if animate:
		var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scroll_vertical", scroll_destination, transition_time)
	else:
		scroll_vertical = scroll_destination


func _input(event: InputEvent) -> void:
	_last_input_event = event

	if event is InputEventJoypadMotion:
		# JOY_AXIS_RIGHT_Y is typically axis 3, but using the constant is safer
		if event.get_axis() == JOY_AXIS_RIGHT_Y: 
			gamepad_scroll = event.get_axis_value()


func _process(_delta: float) -> void:
	if abs(gamepad_scroll) > gamepad_scroll_deadzone:
		scroll_vertical += int(gamepad_scroll_speed * gamepad_scroll)
