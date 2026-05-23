@tool
extends Node3D
class_name BasaltMagnet

@export var push_force: float = 5.0  ## Positive to push up, negative to push down
@export var effect_radius: float = 5.0


func _ready() -> void:
	# If the game is actually running (not in the editor), hide the node and its mesh child
	if not Engine.is_editor_hint():
		hide()
