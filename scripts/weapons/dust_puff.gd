extends GPUParticles3D


func _ready() -> void:
	# Tell Godot to delete this node the moment the particles finish playing
	finished.connect(queue_free)
