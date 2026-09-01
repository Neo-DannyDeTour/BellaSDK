## A player state that locks character movement and frees the mouse cursor.
##
## Used when the player interacts with UI screens, terminals, or during specific
## cinematic moments where normal locomotion and camera controls should be disabled.
class_name StateMachineLock
extends PlayerState


## Called by the state machine upon changing the active state.
## [param _msg] A dictionary with arbitrary data the state can use to initialize itself.
func enter(_msg: Dictionary = {}) -> void:
	print("StateMachineLock: enter() initialized. Player physics locked.")

	# Safely halt any residual momentum
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
		if is_instance_valid(player.locomotion_component):
			player.locomotion_component.reset_momentum()

	# 1. Show the cursor so the player can click the UI
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Corresponds to the `_process()` callback.
## [param _delta] The time elapsed since the previous frame in seconds.
func update(_delta: float) -> void:
	pass


## Corresponds to the `_physics_process()` callback.
## [param _delta] The time elapsed since the previous frame in seconds.
func physics_update(_delta: float) -> void:
	pass


## Corresponds to the `_unhandled_input()` callback.
## [param event] The input event to process.
func handle_input(event: InputEvent) -> void:
	# 2. Prevent the camera from moving by swallowing mouse motion events
	if event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


## Called by the state machine before changing the active state.
func exit() -> void:
	print("StateMachineLock: exit() called. Player physics restored.")
	# Hide and trap the cursor again when leaving the terminal
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
