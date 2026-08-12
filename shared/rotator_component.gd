class_name RotatorComponent
extends Node3D

## The speed of rotation in radians per second. Negative values reverse the direction.
@export_group("Rotation Settings")
@export var speed: float = 5.0

## The axis to rotate around: 0 for X, 1 for Y, 2 for Z.
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
