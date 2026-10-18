## Unit test suite validating StateVault signals, velocity locks, and state transitions.
class_name TestStateVault
extends GutTest

const STATE_VAULT_SCRIPT: GDScript = preload("res://player/state_vault.gd")

## The vault state instance under test.
var state_vault: StateVault = null

## The mock player instance.
var mock_player: MockPlayer = null

## The player state machine coordinator.
var state_machine: PlayerStateMachine = null

## Mock vault controller emitting completion signal.
var mock_vault_ctrl: MockVaultController = null

## Mock destination state for Ground.
var ground_state: MockTargetState = null

## Mock destination state for Air.
var air_state: MockTargetState = null


## Mock vault controller providing the vault_finished signal.
class MockVaultController:
	extends Node

	## Signal emitted when vault motion sequence completes.
	@warning_ignore("unused_signal")
	signal vault_finished


## Mock state recording transitions from StateVault.
class MockTargetState:
	extends PlayerState

	## Records whether enter was invoked on this target state.
	var entered: bool = false

	## Marks state as entered.
	func enter(_msg: Dictionary = {}) -> void:
		print("MockTargetState: enter() called on ", name)
		entered = true


## Sets up an isolated MockPlayer and StateVault instance before each test.
func before_each() -> void:
	print("TestStateVault: before_each() setup started.")
	mock_player = MockPlayer.new()
	add_child_autofree(mock_player)

	mock_vault_ctrl = MockVaultController.new()
	mock_player.add_child(mock_vault_ctrl)
	mock_player.environment_component.vault_controller = mock_vault_ctrl

	state_machine = PlayerStateMachine.new()
	mock_player.add_child(state_machine)

	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	state_vault = STATE_VAULT_SCRIPT.new() as StateVault
	state_vault.name = "Vault"
	state_machine.add_child(state_vault)

	ground_state = MockTargetState.new()
	ground_state.name = "Ground"
	state_machine.add_child(ground_state)

	air_state = MockTargetState.new()
	air_state.name = "Air"
	state_machine.add_child(air_state)

	state_vault.state_machine = state_machine
	state_vault.player = mock_player
	state_machine.owner = mock_player

	state_machine._collect_states()


## Verifies that entering vault zeroes player velocity and connects completion signal.
func test_enter_zeroes_velocity_and_binds_signal() -> void:
	print("TestStateVault: test_enter_zeroes_velocity_and_binds_signal() called.")
	mock_player.velocity = Vector3(8.0, 4.0, -8.0)

	state_vault.enter({})

	assert_eq(mock_player.velocity, Vector3.ZERO, "Player velocity must be zeroed on vault enter.")
	assert_true(
		mock_vault_ctrl.is_connected(&"vault_finished", state_vault._on_vault_finished),
		"vault_finished signal must be connected on enter."
	)


## Verifies that exiting vault disconnects the completion signal cleanly.
func test_exit_disconnects_signal() -> void:
	print("TestStateVault: test_exit_disconnects_signal() called.")
	state_vault.enter({})
	state_vault.exit()

	assert_false(
		mock_vault_ctrl.is_connected(&"vault_finished", state_vault._on_vault_finished),
		"vault_finished signal must be disconnected on exit."
	)


## Verifies that physics_update keeps player velocity clamped to zero during tweens.
func test_physics_update_maintains_zero_velocity() -> void:
	print("TestStateVault: test_physics_update_maintains_zero_velocity() called.")
	mock_player.velocity = Vector3(5.0, 2.0, 5.0)

	state_vault.physics_update(0.016)

	assert_eq(mock_player.velocity, Vector3.ZERO, "Velocity must remain zero during vault physics.")


## Verifies that completing a vault transitions to Air when player is not grounded.
func test_on_vault_finished_transitions_to_air() -> void:
	print("TestStateVault: test_on_vault_finished_transitions_to_air() called.")
	state_vault._on_vault_finished()

	assert_true(air_state.entered, "Should transition to Air state when airborne.")
	assert_false(ground_state.entered, "Ground state should not be entered when airborne.")
