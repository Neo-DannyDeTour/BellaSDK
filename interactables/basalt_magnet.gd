@tool
## A magnet point that exerts directional force on physics objects within its radius.
##
## Typically used to create localized repelling or attracting fields for puzzle mechanics.
## Automatically hides its visual representation when running in the game.
class_name BasaltMagnet
extends Node3D

## The directional force applied to affected objects. Positive pushes away, negative pulls in.
@export var push_force: float = 5.0
## The maximum distance within which physics objects are affected.
@export var effect_radius: float = 5.0


## Initializes the magnet and hides visual meshes during live gameplay.
func _ready() -> void:
	if not is_inside_tree():
		return

	# If the game is actually running (not in the editor), hide the node and its mesh child
	if not Engine.is_editor_hint():
		hide()
