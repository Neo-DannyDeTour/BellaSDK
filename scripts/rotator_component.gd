extends Node3D

@export_group("Rotation Settings")
# How fast it spins. Negative numbers will spin it in reverse!
@export var speed: float = 5.0

# Choose which axis the fan spins around (0 = X, 1 = Y, 2 = Z)
@export_enum("X (Pitch)", "Y (Yaw)", "Z (Roll)") var axis: int = 2


func _process(delta: float) -> void:
	# We use rotate_object_local so if you tilt the fan on a wall,
	# it still spins correctly around its own center, not the world's center.
	if axis == 0:
		rotate_object_local(Vector3.RIGHT, speed * delta)
	elif axis == 1:
		rotate_object_local(Vector3.UP, speed * delta)
	elif axis == 2:
		rotate_object_local(Vector3.FORWARD, speed * delta)
