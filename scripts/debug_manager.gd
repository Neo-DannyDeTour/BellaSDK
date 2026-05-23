extends Node


func _ready() -> void:
	# Connect to the signal from your debug menu
	Events.wireframe_toggled.connect(_on_events_wireframe_toggled)


func _on_events_wireframe_toggled(is_on: bool) -> void:
	if is_on:
		# This tells the entire game window to draw only the lines (polygons)
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	else:
		# This returns the game to normal shaded rendering
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
