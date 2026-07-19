class_name PlasmaSpark
extends GPUParticles3D

## Optional parameter to configure the intensity of the spark burst.
@export var burst_intensity: float = 1.0


func _ready() -> void:
	print("PlasmaSpark: _ready() called. Spawning a plasma spark VFX.")
	finished.connect(_on_finished)
	emitting = true
	one_shot = true


func _on_finished() -> void:
	queue_free()
