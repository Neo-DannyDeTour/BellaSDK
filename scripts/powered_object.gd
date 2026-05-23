extends Node3D
class_name PowerComponent

signal powered_on
signal powered_off

@export var required_power: int = 1
var current_power: int = 0
var is_powered: bool = false


func add_power() -> void:
	current_power += 1
	_evaluate_power_state()


func remove_power() -> void:
	current_power = max(0, current_power - 1)
	_evaluate_power_state()


func _evaluate_power_state() -> void:
	# Remember what we were before this check
	var was_powered := is_powered

	# Are we currently meeting the power requirement?
	is_powered = (current_power >= required_power)

	# If the state JUST changed to ON
	if is_powered and not was_powered:
		print(get_parent().name + " received enough power!")
		powered_on.emit()

	# If the state JUST changed to OFF
	elif not is_powered and was_powered:
		print(get_parent().name + " lost power!")
		powered_off.emit()
