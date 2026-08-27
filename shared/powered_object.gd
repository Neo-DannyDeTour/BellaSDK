## A logic component that tracks power state and emits signals upon state change.
##
## Attach to interactable objects that require a minimum power threshold to activate.
class_name PowerComponent
extends Node3D

## Emitted when the required power threshold is met.
signal powered_on
## Emitted when the power falls below the required threshold.
signal powered_off

## The minimum amount of power required to turn on the object.
@export var required_power: int = 1
## The current amount of power supplied to the object.
var current_power: int = 0
## Indicates whether the object is currently meeting its power requirements.
var is_powered: bool = false


## Increments the current power count and evaluates state changes.
func add_power() -> void:
	current_power += 1
	_evaluate_power_state()


## Decrements the current power count and evaluates state changes.
func remove_power() -> void:
	current_power = max(0, current_power - 1)
	_evaluate_power_state()


## Checks the power requirement against current supply and triggers signals if changed.
func _evaluate_power_state() -> void:
	# Remember what we were before this check
	var was_powered: bool = is_powered

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
