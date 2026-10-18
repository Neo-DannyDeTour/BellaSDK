## Base player state providing injected actor reference, input actions, and lifecycle stubs.
class_name PlayerState
extends State

## Input action identifier for moving left.
const ACTION_LEFT: StringName = &"left"

## Input action identifier for moving right.
const ACTION_RIGHT: StringName = &"right"

## Input action identifier for moving forward.
const ACTION_FORWARD: StringName = &"forward"

## Input action identifier for moving backward.
const ACTION_BACKWARD: StringName = &"backward"

## Input action identifier for jumping.
const ACTION_JUMP: StringName = &"jump"

## Input action identifier for crouching.
const ACTION_CROUCH: StringName = &"crouch"

## Input action identifier for sprinting.
const ACTION_SPRINT: StringName = &"sprint"

## Input action identifier for interacting.
const ACTION_INTERACT: StringName = &"interact"

## Input action identifier for camera zoom.
const ACTION_ZOOM: StringName = &"zoom"

## Reference to controlling [CharacterBody3D] player instance.
var player: CharacterBody3D


## Returns owning player as a concrete [Player] instance.
func get_player() -> Player:
	return player as Player


## Returns owning player as a concrete [Player] instance.
func _get_player() -> Player:
	return player as Player


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
