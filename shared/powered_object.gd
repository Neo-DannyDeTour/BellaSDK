## Logic component tracking power inputs and signaling state changes.
class_name PowerComponent
extends Node3D

## Emitted when the required power threshold is met.
signal powered_on
## Emitted when power falls below the required threshold.
signal powered_off

## Minimum amount of power required to activate parent object.
@export var required_power: int = 1:
	set = _set_required_power

## Current amount of power units actively supplied to this component.
var current_power: int = 0

## Indicates whether the component currently meets its power requirement.
var is_powered: bool = false


## Increments power count and checks whether activation conditions are met.
func add_power() -> void:
	current_power += 1
	var parent_name: String = get_parent().name if get_parent() else name
	print(
		"PowerComponent: [",
		parent_name,
		"] power added. Current: ",
		current_power,
		"/",
		required_power
	)
	_evaluate_power_state()


## Decrements power count safely down to zero and re-evaluates state.
func remove_power() -> void:
	current_power = maxi(0, current_power - 1)
	var parent_name: String = get_parent().name if get_parent() else name
	print(
		"PowerComponent: [",
		parent_name,
		"] power removed. Current: ",
		current_power,
		"/",
		required_power
	)
	_evaluate_power_state()


## Checks power against required threshold and emits signals on transitions.
func _evaluate_power_state() -> void:
	var was_powered: bool = is_powered
	is_powered = (current_power >= required_power)

	var parent_name: String = get_parent().name if get_parent() else name

	if is_powered and not was_powered:
		print("PowerComponent: [", parent_name, "] THRESHOLD REACHED -> Emitting powered_on")
		powered_on.emit()
	elif not is_powered and was_powered:
		print("PowerComponent: [", parent_name, "] THRESHOLD LOST -> Emitting powered_off")
		powered_off.emit()


## Setter for [member required_power] to re-check status if changed dynamically.
## [param value]: New required threshold value.
func _set_required_power(value: int) -> void:
	required_power = maxi(1, value)
	if is_inside_tree():
		_evaluate_power_state()
