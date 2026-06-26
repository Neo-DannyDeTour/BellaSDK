class_name StateMachineLock
extends PlayerState


func enter(_msg: Dictionary = {}) -> void:
	print("StateMachineLock: enter() initialized. Player physics locked.")

	# Safely halt any residual momentum
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
		if is_instance_valid(player.locomotion_component):
			player.locomotion_component.reset_momentum()

	# 1. Show the cursor so the player can click the UI
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func handle_input(event: InputEvent) -> void:
	# 2. Prevent the camera from moving by swallowing mouse motion events
	if event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


func exit() -> void:
	print("StateMachineLock: exit() called. Player physics restored.")
	# Hide and trap the cursor again when leaving the terminal
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
