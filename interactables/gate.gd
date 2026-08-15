## A basic structural gate that translates positions based on power state or analog progress.
##
## Can act as a binary on/off door via a puzzle trigger, or be smoothly controlled manually
## through mechanisms like a rotary wheel.
class_name Gate
extends Node3D

## The relative local 3D offset applied to the gate when it enters the powered-on state.
@export var open_offset: Vector3 = Vector3(0.0, 4.0, 0.0)
## The time in seconds it takes for the tween animation to fully open or close the gate.
@export var move_duration: float = 2.0

## Caches the initial position to serve as the default closed state reference.
var closed_position: Vector3
## Manages binary open/close movement animations, allowing safe interruption.
var _move_tween: Tween


## Caches the starting location of the gate geometry.
func _ready() -> void:
	closed_position = position


## Triggers a tween animation toward the combined closed position and [member open_offset].
func power_on() -> void:
	print("Gate: power_on() called. Opening gate.")
	_animate_gate(closed_position + open_offset)


## Triggers a tween animation returning the gate to its initial [member closed_position].
func power_off() -> void:
	print("Gate: power_off() called. Closing gate.")
	_animate_gate(closed_position)


## Cancels active tweens and begins a new sine-eased movement to the provided coordinate.
## [param target_pos]: The desired local 3D position vector.
func _animate_gate(target_pos: Vector3) -> void:
	# Kill the existing tween to prevent conflicting movements if spammed
	if is_instance_valid(_move_tween):
		_move_tween.kill()

	_move_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(self, "position", target_pos, move_duration)


## Directly sets the gate position based on a percentage, designed for analog controllers.
## [param progress_value]: A float from 0.0 to 1.0 representing the interpolation weight.
func set_progress(progress_value: float) -> void:
	# We omit a print() statement here because this function runs every frame
	# during interaction. Printing to the console 60 times a second will cause stuttering.

	# Kill the digital on/off tween so it doesn't fight the analog wheel movement
	if is_instance_valid(_move_tween) and _move_tween.is_running():
		_move_tween.kill()

	# Direct lerp ensures optimal 60 FPS matching with the wheel's movement
	position = closed_position.lerp(closed_position + open_offset, progress_value)
