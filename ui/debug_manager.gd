## Global autoload managing debug rendering overrides.
##
## Hooks into global Event bus signals to enforce debug draw modes directly
## on the main viewport, allowing the player to toggle features like wireframe rendering.
class_name DebugManager
extends Node


## Lifecycle initialization connecting to the global event bus.
func _ready() -> void:
	print("System: Debug Manager initialized.")
	if Events.has_signal("wireframe_toggled"):
		Events.wireframe_toggled.connect(_on_events_wireframe_toggled)


## Handles global wireframe rendering toggles.
## [param is_on] The requested toggle state.
func _on_events_wireframe_toggled(is_on: bool) -> void:
	print("Engine: Viewport wireframe rendering toggled to: ", is_on)
	if is_on:
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	else:
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
