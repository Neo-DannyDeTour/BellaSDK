## Base player state providing injected actor reference and lifecycle stubs.
class_name PlayerState
extends State

## Reference to controlling [CharacterBody3D] player instance.
var player: CharacterBody3D


## Virtual method called when entering this state with optional parameters.
func enter(_msg: Dictionary = {}) -> void:
	return


## Virtual method called when exiting this state for cleanup.
func exit() -> void:
	return


## Virtual method receiving unhandled input events forwarded from state machine.
func handle_input(_event: InputEvent) -> void:
	return


## Virtual method executed during the standard frame processing loop.
func update(_delta: float) -> void:
	return


## Virtual method executed during the physics process frame update.
func physics_update(_delta: float) -> void:
	return
