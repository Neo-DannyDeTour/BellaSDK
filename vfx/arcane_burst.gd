## A transient 3D particle effect representing an arcane magic burst.
##
## Acts as a generic magic burst visual effect that manages its own lifecycle.
## Extends [GPUParticles3D].
class_name ArcaneBurst
extends GPUParticles3D

## The duration in seconds that the particles will emit before stopping.
## Used to control the length of the visual effect. Defaults to 1.0.
@export var burst_duration: float = 1.0


## Automatically called when the node enters the scene tree.
## Lifecycle trigger: _ready.
## Starts emitting and connects the [signal finished] signal.
## Returns void.
func _ready() -> void:
	print("ArcaneBurst: _ready() called. Spawning an arcane burst VFX.")
	finished.connect(_on_finished)
	emitting = true
	one_shot = true


## Deletes the node when the particle effect finishes playing to prevent memory leaks.
## Returns void.
func _on_finished() -> void:
	queue_free()
