extends Node3D


func _ready() -> void:
	# Wait 5 seconds, then delete this node so we don't cause a memory leak!
	await get_tree().create_timer(5.0).timeout
	queue_free()
