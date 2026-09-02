## A transient debug marker used to visualize positions in 3D space.
##
## This node automatically deletes itself after a set duration to prevent memory leaks.
class_name DebugPellet
extends Node3D


## Automatically called when the node enters the scene tree.
## Queues the node for deletion after 5 seconds.
func _ready() -> void:
	# Wait 5 seconds, then delete this node so we don't cause a memory leak!
	await get_tree().create_timer(5.0).timeout
	queue_free()
