## A transient 3D particle effect that automatically despawns when finished.
class_name DustPuff
extends GPUParticles3D


## Wires up the finished signal safely via [Utilities] to auto-delete the node.
func _ready() -> void:
	print("DustPuff: Particle system initialized -> ", name)
	Utilities.safe_connect(finished, queue_free)
