extends GutTest

## The state machine being tested.
var sm: PlayerStateMachine = null

## The mock player injected into states.
var mock_player: CharacterBody3D = null


## Mock state implementation for transition verification.
class MockState:
	extends PlayerState

	## Tracks if the state is active.
	var is_active: bool = false

	## Tracks if enter was called.
	var enter_called: bool = false

	## Tracks if exit was called.
	var exit_called: bool = false

	## Enters the mock state.
	func enter(_msg: Dictionary = {}) -> void:
		print("TestPlayerStateMachine: MockState enter() called. State: ", self.name)
		is_active = true
		enter_called = true

	## Exits the mock state.
	func exit() -> void:
		print("TestPlayerStateMachine: MockState exit() called. State: ", self.name)
		is_active = false
		exit_called = true


## Sets up the state machine hierarchy before each test.
func before_each() -> void:
	print("TestPlayerStateMachine: before_each() called. Setting up mock state machine.")
	sm = load("res://player/player_state_machine.gd").new()
	mock_player = CharacterBody3D.new()

	var state1: MockState = MockState.new()
	state1.name = "State1"

	var state2: MockState = MockState.new()
	state2.name = "State2"

	var parent: Node = Node.new()
	parent.add_child(mock_player)
	mock_player.add_child(sm)
	sm.add_child(state1)
	sm.add_child(state2)

	sm.initial_state = NodePath("State1")
	sm.owner = mock_player
	sm._states = {"State1": state1, "State2": state2}
	sm.state = state1

	state1.state_machine = sm
	state1.player = mock_player
	state2.state_machine = sm
	state2.player = mock_player

	add_child_autoqfree(parent)


## Verifies initial state assignment and dependency injection.
func test_initialization() -> void:
	print("TestPlayerStateMachine: test_initialization() called.")
	assert_not_null(sm.state, "State should be initialized to State1")
	assert_eq(sm.state.name, "State1")
	assert_eq(sm.state.player, mock_player, "Player dependency should be injected.")
	assert_eq(sm.state.state_machine, sm, "StateMachine dependency should be injected.")


## Verifies successful transition between valid states.
func test_transition_to_valid_state() -> void:
	print("TestPlayerStateMachine: test_transition_to_valid_state() called.")
	watch_signals(sm)

	var state1: MockState = sm._states["State1"] as MockState
	var state2: MockState = sm._states["State2"] as MockState
	state1.enter()

	sm.transition_to("State2")

	assert_true(state1.exit_called, "State1 exit() should have been called.")
	assert_false(state1.is_active, "State1 should not be active.")
	assert_true(state2.enter_called, "State2 enter() should have been called.")
	assert_true(state2.is_active, "State2 should be active.")
	assert_eq(sm.state, state2, "Current state should now be State2.")
	assert_signal_emitted_with_parameters(sm, "transitioned", ["State2"])


## Verifies invalid state transitions abort cleanly and log an engine error.
func test_transition_to_invalid_state() -> void:
	print("TestPlayerStateMachine: test_transition_to_invalid_state() called.")
	watch_signals(sm)

	var state1: MockState = sm._states["State1"] as MockState
	state1.enter()

	# State3 does not exist; assert the expected push_error to prevent CI failure
	sm.transition_to("State3")
	assert_engine_error("Cannot transition to state 'State3'")

	assert_false(state1.exit_called, "State1 exit() should not be called if transition fails.")
	assert_eq(sm.state, state1, "Current state should remain State1.")
	assert_signal_not_emitted(sm, "transitioned")
