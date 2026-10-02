## Base state class defining lifecycle callbacks and state machine bindings.
class_name State
extends Node

@warning_ignore("unused_signal")
## Emitted when requesting a state change. Passes target state name and payload.
signal transition_requested(target_state_name: StringName, message: Dictionary)

## The state machine governing this state instance.
var state_machine: StateMachine = null


## Lifecycle hook invoked when entering this state.
func enter(_message: Dictionary = {}) -> void:
	print("State: enter() called on state: ", name)


## Lifecycle hook invoked when exiting this state.
func exit() -> void:
	print("State: exit() called on state: ", name)


## Frame update callback executing every process step.
func update(_delta: float) -> void:
	pass


## Physics update callback executing every physics step.
func physics_update(_delta: float) -> void:
	pass


## Input handling callback evaluating unhandled input events.
func handle_input(_event: InputEvent) -> void:
	pass
