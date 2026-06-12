class_name PlayerState
extends Node

# --------------------------------------
# DEPENDENCY INJECTION
# --------------------------------------
# These are populated automatically by the StateMachine when the game starts.
var player: CharacterBody3D
var state_machine: Node


# --------------------------------------
# VIRTUAL METHODS
# --------------------------------------
# Called by the state machine when transitioning INTO this state.
# The 'msg' dictionary allows you to pass data (like jump velocity or zip-line vectors).
func enter(_msg: Dictionary = {}) -> void:
	# Virtual method: Intentionally left blank for child classes to override.
	return


# Called by the state machine when transitioning OUT of this state.
# Use this to clean up tweens, reset variables, or release objects.
func exit() -> void:
	# Virtual method: Intentionally left blank for child classes to override.
	return


# Corresponds to _unhandled_input()
func handle_input(_event: InputEvent) -> void:
	# Virtual method: Intentionally left blank for child classes to override.
	return


# Corresponds to _process()
func update(_delta: float) -> void:
	# Virtual method: Intentionally left blank for child classes to override.
	return


# Corresponds to _physics_process()
func physics_update(_delta: float) -> void:
	# Virtual method: Intentionally left blank for child classes to override.
	return
