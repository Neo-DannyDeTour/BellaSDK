## A transient 3D particle effect representing a burst of plasma sparks.
##
## Acts as a generic electric/plasma visual effect that manages its own lifecycle.
## Extends [GPUParticles3D].
class_name PlasmaSpark
extends GPUParticles3D

## The intensity of the spark burst, affecting particle speed or count.
## Used to scale the visual impact of the effect. Defaults to 1.0.
@export var burst_intensity: float = 1.0


## Automatically called when the node enters the scene tree.
## Starts emitting and connects the [signal finished] signal.
func _ready() -> void:
	print("PlasmaSpark: _ready() called. Spawning a plasma spark VFX.")
	finished.connect(_on_finished)
	emitting = true
	one_shot = true


## Deletes the node when the particle effect finishes playing to prevent memory leaks.
func _on_finished() -> void:
	queue_free()
