## An automatically scrolling UI container for long text segments like developer commentary.
##
## Tracks user gamepad or keyboard input to smoothly scroll the text up and down without
## needing a mouse.
class_name AutoScrollContainer
extends ScrollContainer

## If true, smooth scrolling animation will be applied between focused elements.
@export var animate: bool = true
## Transition time.
@export var transition_time: float = 0.2
## Gamepad scroll speed.
@export var gamepad_scroll_speed: int = 5
## Gamepad scroll deadzone.
@export var gamepad_scroll_deadzone: float = 0.1

## A reference to the child [Control] that provides the bounds for scrolling.
var scrollable: Control = null
## Caches the most recent input event to differentiate between mouse and gamepad actions.
var _last_input_event: InputEvent = null
## Current analog accumulation for scrolling speed and direction.
var gamepad_scroll: float = 0.0


## Initializes child control mapping and hooks into global GUI focus changes.
func _ready() -> void:
	if get_child_count() > 0 and get_child(0) is Control:
		scrollable = get_child(0) as Control
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Calculates the exact relative coordinate offset between two control nodes.
## [param a]: The reference base [Control].
## [param b]: The target [Control].
## Returns the 2D offset vector.
func _get_position_relative_to_control(a: Control, b: Control) -> Vector2:
	return b.get_global_rect().position - a.get_global_rect().position


## Responds to UI focus changes and initiates automatic smooth scrolling.
## [param focus]: The newly focused UI [Control] element.
func _on_focus_changed(focus: Control) -> void:
	if _last_input_event is InputEventMouseButton:
		return

	if not scrollable:
		return

	var scroll_destination: int = int(
		_get_position_relative_to_control(scrollable, focus).y - (get_rect().size.y / 2.0)
	)

	if animate:
		var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scroll_vertical", scroll_destination, transition_time)
	else:
		scroll_vertical = scroll_destination


## Evaluates global input events, specifically tracking analog stick values for gamepad scrolling.
## [param event]: The unhandled [InputEvent] to parse.
func _input(event: InputEvent) -> void:
	_last_input_event = event

	if event is InputEventJoypadMotion:
		# JOY_AXIS_RIGHT_Y is typically axis 3, but using the constant is safer
		if event.get_axis() == JOY_AXIS_RIGHT_Y:
			gamepad_scroll = event.get_axis_value()


## Applies analog stick values continuously to the vertical scrollbar per frame.
## [param _delta]: Frame delta time.
func _process(_delta: float) -> void:
	if abs(gamepad_scroll) > gamepad_scroll_deadzone:
		scroll_vertical += int(gamepad_scroll_speed * gamepad_scroll)
