## Sweeps the graphics preview camera horizontally around the Y-axis like a CCTV unit.
class_name GraphicsCCTVCamera
extends Camera3D

## Maximum sweep angle in degrees to either side.
@export var max_sweep_angle: float = 35.0
## Oscillation sweep speed multiplier.
@export var sweep_speed: float = 0.8

## Base starting Y rotation in radians.
var _initial_rotation_y: float = 0.0
## Elapsed continuous time counter for oscillation math.
var _sweep_time: float = 0.0


## Lifecycle initialization caching initial heading.
func _ready() -> void:
	print("Diorama: Graphics CCTV Camera initialized.")
	_initial_rotation_y = rotation.y


## Frame update applying sinusoidal panning across the Y axis.
## [param delta] Elapsed frame step time in seconds.
func _process(delta: float) -> void:
	if not current:
		return

	_sweep_time += delta * sweep_speed
	var angle_offset: float = deg_to_rad(max_sweep_angle) * sin(_sweep_time)
	rotation.y = _initial_rotation_y + angle_offset
