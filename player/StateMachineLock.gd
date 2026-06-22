class_name StateMachineLock
extends PlayerState

func enter(_msg: Dictionary = {}) -> void:
	print("StateMachineLock: enter() initialized. Player physics locked.")
	
	# Safely halt any residual momentum
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
		if is_instance_valid(player.locomotion_component):
			player.locomotion_component.reset_momentum()


func update(_delta: float) -> void:
	# Intentionally blank to ignore normal frame updates
	pass


func physics_update(_delta: float) -> void:
	# Intentionally blank to ignore physics updates and hardware inputs
	pass


func exit() -> void:
	print("StateMachineLock: exit() called. Player physics restored.")
