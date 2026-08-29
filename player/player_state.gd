## Base virtual class for all individual player movement states.
##
## [PlayerState] acts as the blueprint for states managed by the [PlayerStateMachine].
## It provides overridable virtual methods for physics, inputs, and transitions.
class_name PlayerState
extends Node

## The physical character body that this state manipulates. Populated by the state machine.
var player: CharacterBody3D
## Reference to the state machine governing this node. Populated during initialization.
var state_machine: Node


## Called by the state machine when transitioning INTO this state.
## [param _msg] Optional dictionary payload for passing initialization data.
func enter(_msg: Dictionary = {}) -> void:
	# Virtual method: Intentionally left blank for child classes to override.
	return


## Called by the state machine when transitioning OUT of this state.
func exit() -> void:
	# Virtual method: Intentionally left blank for child classes to override.
	return


## Processes unhandled input events routed from the player controller.
## [param _event] The [InputEvent] to handle.
func handle_input(_event: InputEvent) -> void:
	# Virtual method: Intentionally left blank for child classes to override.
	return


## Called every frame to handle visual logic and camera updates.
## [param _delta] Time elapsed since the previous frame.
func update(_delta: float) -> void:
	# Virtual method: Intentionally left blank for child classes to override.
	return


## Called every physics frame to execute core movement and collision logic.
## [param _delta] Time elapsed since the previous physics frame.
func physics_update(_delta: float) -> void:
	# Virtual method: Intentionally left blank for child classes to override.
	return
