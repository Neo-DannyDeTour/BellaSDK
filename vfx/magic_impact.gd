class_name MagicImpact
extends GPUParticles3D

## Determines if the impact effect should automatically start emitting upon entering the tree.
@export var auto_start: bool = true


func _ready() -> void:
	print("MagicImpact: _ready() called. Spawning Magic Impact VFX.")
	if auto_start:
		trigger_effect()


## Triggers the particle emission and connects the cleanup signal.
func trigger_effect() -> void:
	emitting = true
	if not finished.is_connected(queue_free):
		finished.connect(queue_free)
