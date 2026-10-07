## Handles ledge vault execution and handoff via [VaultController].
class_name StateVault
extends PlayerState


## Initializes vault state, connects finish signal, and resets player velocity.
func enter(_msg: Dictionary = {}) -> void:
	print("StateVault: enter() called. Initializing vault execution.")
	var typed_player: Player = player if player is Player else null
	var env: PlayerEnvironmentComponent = (
		typed_player.environment_component as PlayerEnvironmentComponent
		if is_instance_valid(typed_player)
		else null
	)
	var vault_ctrl: Node = env.vault_controller if is_instance_valid(env) else null

	if is_instance_valid(vault_ctrl):
		if not vault_ctrl.is_connected(&"vault_finished", _on_vault_finished):
			vault_ctrl.connect(&"vault_finished", _on_vault_finished)

	player.velocity = Vector3.ZERO


## Cleans up signal connections on [VaultController] during state exit.
func exit() -> void:
	print("StateVault: exit() called. Cleaning up vault connections.")
	var typed_player: Player = player if player is Player else null
	var env: PlayerEnvironmentComponent = (
		typed_player.environment_component as PlayerEnvironmentComponent
		if is_instance_valid(typed_player)
		else null
	)
	var vault_ctrl: Node = env.vault_controller if is_instance_valid(env) else null

	if is_instance_valid(vault_ctrl):
		if vault_ctrl.is_connected(&"vault_finished", _on_vault_finished):
			vault_ctrl.disconnect(&"vault_finished", _on_vault_finished)


## Maintains suspended physics state while vault tweens translate player.
func physics_update(_delta: float) -> void:
	print("StateVault: physics_update() holding player velocity during vault tween.")
	player.velocity = Vector3.ZERO


## Handles vault completion and transitions player to [StateGround] or [StateAir].
func _on_vault_finished() -> void:
	print("StateVault: _on_vault_finished() triggered. Evaluating landing state.")
	if player.is_on_floor():
		state_machine.transition_to(&"Ground")
	else:
		state_machine.transition_to(&"Air")
