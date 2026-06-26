class_name StateVault
extends PlayerState


func enter(_msg: Dictionary = {}) -> void:
	# 1. Safely route to the vault controller via the new component architecture
	var env: Node = player.environment_component
	var vault_ctrl: Node = env.get("vault_controller") if is_instance_valid(env) else null

	if is_instance_valid(vault_ctrl):
		# Listen for the VaultController to tell us it's done
		if not vault_ctrl.vault_finished.is_connected(_on_vault_finished):
			vault_ctrl.vault_finished.connect(_on_vault_finished)

	# 2. Kill momentum so the player doesn't slide during the vault
	player.velocity = Vector3.ZERO


func exit() -> void:
	var env: Node = player.environment_component
	var vault_ctrl: Node = env.get("vault_controller") if is_instance_valid(env) else null

	if is_instance_valid(vault_ctrl):
		# Clean up the connection so it doesn't fire multiple times
		if vault_ctrl.vault_finished.is_connected(_on_vault_finished):
			vault_ctrl.vault_finished.disconnect(_on_vault_finished)


func physics_update(_delta: float) -> void:
	# Do absolutely nothing. The VaultController's Tweens are moving the player.
	pass


func _on_vault_finished() -> void:
	# Return control to the player based on where they landed
	if player.is_on_floor():
		state_machine.transition_to("Ground")
	else:
		state_machine.transition_to("Air")
