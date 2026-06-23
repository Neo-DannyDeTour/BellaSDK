extends Node3D

## How far the gate moves when powered on
@export var open_offset: Vector3 = Vector3(0.0, 4.0, 0.0)
## Duration of the opening/closing animation in seconds
@export var move_duration: float = 2.0

var closed_position: Vector3
var _move_tween: Tween


func _ready() -> void:
	closed_position = position


func power_on() -> void:
	print("Gate: power_on() called. Opening gate.")
	_animate_gate(closed_position + open_offset)


func power_off() -> void:
	print("Gate: power_off() called. Closing gate.")
	_animate_gate(closed_position)


func _animate_gate(target_pos: Vector3) -> void:
	# Kill the existing tween to prevent conflicting movements if spammed
	if is_instance_valid(_move_tween):
		_move_tween.kill()

	_move_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(self, "position", target_pos, move_duration)


func update_progress(progress_value: float) -> void:
	# Kill the digital on/off tween so it doesn't fight the analog wheel movement
	if is_instance_valid(_move_tween) and _move_tween.is_running():
		_move_tween.kill()
		
	# Direct lerp ensures optimal 60 FPS matching with the wheel's movement
	position = closed_position.lerp(closed_position + open_offset, progress_value)
