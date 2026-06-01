class_name StateVault
extends PlayerState

func enter(_msg: Dictionary = {}) -> void:
	# Listen for the VaultController to tell us it's done
	player.vault_controller.vault_finished.connect(_on_vault_finished)
	
	# Kill momentum so the player doesn't slide during the vault
	player.velocity = Vector3.ZERO


func exit() -> void:
	# Clean up the connection so it doesn't fire multiple times
	if player.vault_controller.vault_finished.is_connected(_on_vault_finished):
		player.vault_controller.vault_finished.disconnect(_on_vault_finished)


func physics_update(_delta: float) -> void:
	# Do absolutely nothing. The VaultController's Tweens are moving the player.
	pass


func _on_vault_finished() -> void:
	# Return control to the player based on where they landed
	if player.is_on_floor():
		state_machine.transition_to("Ground")
	else:
		state_machine.transition_to("Air")
