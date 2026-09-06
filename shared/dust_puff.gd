## A transient 3D particle effect that automatically despawns when finished.
##
## Acts as a generic dust puff visual effect that manages its own lifecycle.
## Extends [GPUParticles3D].
class_name DustPuff
extends GPUParticles3D


## Wires up the finished signal to auto-delete the node from the scene tree.
## Called when the node enters the scene tree.
func _ready() -> void:
	# Tell Godot to delete this node the moment the particles finish playing
	if not finished.is_connected(queue_free):
		finished.connect(queue_free)
