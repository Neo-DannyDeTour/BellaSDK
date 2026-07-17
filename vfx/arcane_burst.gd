class_name ArcaneBurst
extends GPUParticles3D

## Optional parameter to configure how long the particles should emit.
@export var burst_duration: float = 1.0


func _ready() -> void:
	print("ArcaneBurst: _ready() called. Spawning an arcane burst VFX.")
	finished.connect(_on_finished)
	emitting = true
	one_shot = true


func _on_finished() -> void:
	queue_free()
