extends Node3D

## How far the gate moves when the valve is at 100% (e.g., up 4 meters on the Y axis)
@export var open_offset: Vector3 = Vector3(0, 4, 0)

var closed_position: Vector3


func _ready() -> void:
	# Remember where we started in the editor!
	closed_position = position


# This is called every single frame by the Valve!
func set_progress(val: float) -> void:
	# Lerp perfectly blends between the closed and open position based on the valve's 0.0 to 1.0 value
	position = closed_position.lerp(closed_position + open_offset, val)
