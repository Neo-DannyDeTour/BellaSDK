## Valve handle interactable for mechanical inputs and rotation puzzles.
class_name PickableValve
extends PickableObject

## Emitted when valve is turned. Passes [param current_angle] in degrees.
signal valve_rotated(current_angle: float)

@export_category("Valve Controls")
## Current rotational angle of the valve handle in degrees.
@export var current_angle: float = 0.0

## Maximum permitted rotational angle of the valve handle in degrees.
@export var max_angle: float = 360.0

## Minimum permitted rotational angle of the valve handle in degrees.
@export var min_angle: float = 0.0

## Resistance torque factor dampening valve turning speed.
@export var turn_friction: float = 1.0

## Indicates whether the valve handle is currently engaged in a socket.
var is_socketed: bool = false


## Initializes the valve handle and connects interaction signals.
func _ready() -> void:
	super._ready()
	print("PickableValve: _ready() initialized.")


## Rotates valve handle by [param angle_delta] degrees within limits.
func rotate_valve(angle_delta: float) -> void:
	print("PickableValve: rotate_valve() with delta: ", angle_delta)
	current_angle = clampf(current_angle + angle_delta, min_angle, max_angle)
	valve_rotated.emit(current_angle)
