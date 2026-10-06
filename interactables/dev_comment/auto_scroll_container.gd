## An automatically scrolling UI container for long text segments like developer commentary.
class_name AutoScrollContainer
extends ScrollContainer

## If true, smooth scrolling animation will be applied between focused elements.
@export var animate: bool = true
## Transition time in seconds for the focus tween animation.
@export var transition_time: float = 0.2
## Multiplier applied to analog stick input to scale scroll speed.
@export var gamepad_scroll_speed: int = 5
## Deadzone threshold to ignore subtle analog stick drift.
@export var gamepad_scroll_deadzone: float = 0.1

## A reference to the child [Control] that provides the bounds for scrolling.
var scrollable: Control = null
## Caches the most recent input event to differentiate between input types.
var _last_input_event: InputEvent = null
## Current analog accumulation for scrolling speed and direction.
var gamepad_scroll: float = 0.0


## Resolves child scrollable control and connects GUI focus notifications.
func _ready() -> void:
	print("AutoScrollContainer: _ready() called. Initializing container.")
	if get_child_count() > 0 and get_child(0) is Control:
		scrollable = get_child(0) as Control
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Calculates the relative coordinate offset between two control nodes.
func _get_position_relative_to_control(a: Control, b: Control) -> Vector2:
	return b.get_global_rect().position - a.get_global_rect().position


## Responds to UI focus changes and initiates automatic smooth scrolling.
func _on_focus_changed(focus: Control) -> void:
	if _last_input_event is InputEventMouseButton:
		return

	if not scrollable:
		return

	print("AutoScrollContainer: Focus changed to -> ", focus.name)
	var relative_y: float = _get_position_relative_to_control(scrollable, focus).y
	var scroll_destination: int = int(relative_y - (get_rect().size.y * 0.5))

	if animate:
		var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scroll_vertical", scroll_destination, transition_time)
	else:
		scroll_vertical = scroll_destination


## Evaluates input events, parsing analog stick values on gamepad motion.
func _input(event: InputEvent) -> void:
	_last_input_event = event

	if event is InputEventJoypadMotion:
		var joy_event: InputEventJoypadMotion = event if event is InputEventJoypadMotion else null
		if joy_event.axis == JOY_AXIS_RIGHT_Y:
			gamepad_scroll = joy_event.axis_value


## Applies accumulated analog stick values continuously per frame.
func _process(_delta: float) -> void:
	if absf(gamepad_scroll) > gamepad_scroll_deadzone:
		scroll_vertical += int(gamepad_scroll_speed * gamepad_scroll)
