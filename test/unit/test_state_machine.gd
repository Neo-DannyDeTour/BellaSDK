## Unit tests verifying StateMachine state transitions, registration, and frame updates.
class_name TestStateMachine
extends GutTest

## The [StateMachine] under test.
var state_machine: StateMachine = null


## A simple dummy state for test tracking.
class DummyState:
	extends State

	## Tracks if enter() was called.
	var enter_called: bool = false
	## Tracks if exit() was called.
	var exit_called: bool = false
	## Tracks if update() was called.
	var update_called: bool = false
	## Tracks if physics_update() was called.
	var physics_update_called: bool = false
	## Tracks if handle_input() was called.
	var input_handled: bool = false

	func enter(_message: Dictionary = {}) -> void:
		print("TestStateMachine: DummyState enter.")
		enter_called = true

	func exit() -> void:
		print("TestStateMachine: DummyState exit.")
		exit_called = true

	func update(_delta: float) -> void:
		update_called = true

	func physics_update(_delta: float) -> void:
		physics_update_called = true

	func handle_input(_event: InputEvent) -> void:
		input_handled = true

	func emit_transition(target: StringName, msg: Dictionary = {}) -> void:
		transition_requested.emit(target, msg)


## Sets up environment before each test.
func before_each() -> void:
	print("TestStateMachine: Setup test environment.")
	state_machine = StateMachine.new()
	state_machine.name = "TestStateMachine"
	add_child_autofree(state_machine)


## Verifies _ready initializes using the explicit initial_state.
func test_initialization_with_initial_state() -> void:
	print("TestStateMachine: Testing initialization with initial_state.")
	var state1: DummyState = DummyState.new()
	state1.name = "State1"
	var state2: DummyState = DummyState.new()
	state2.name = "State2"

	state_machine.add_child(state1)
	state_machine.add_child(state2)
	state_machine.initial_state = state2

	state_machine._ready()

	assert_eq(
		state_machine.get_current_state(), state2, "Should initialize into State2 as initial_state."
	)
	assert_true(state2.enter_called, "State2 enter() should be called.")


## Verifies fallback to first state when initial_state is not explicitly set.
func test_initialization_fallback() -> void:
	print("TestStateMachine: Testing initialization fallback.")
	var state1: DummyState = DummyState.new()
	state1.name = "State1"
	state_machine.add_child(state1)

	state_machine._ready()

	assert_eq(state_machine.get_current_state(), state1, "Should fallback to first child state.")
	assert_true(state1.enter_called, "State1 enter() should be called on fallback.")


## Verifies lifecycle update forwarding to the active state.
func test_state_lifecycle_updates() -> void:
	print("TestStateMachine: Testing process update forwarding.")
	var state: DummyState = DummyState.new()
	state.name = "ActiveState"
	state_machine.add_child(state)
	state_machine._ready()

	state_machine._process(0.1)
	assert_true(state.update_called, "Should forward _process to current_state.")

	state_machine._physics_process(0.1)
	assert_true(state.physics_update_called, "Should forward _physics_process to current_state.")

	var event: InputEventKey = InputEventKey.new()
	state_machine._unhandled_input(event)
	assert_true(state.input_handled, "Should forward _unhandled_input to current_state.")


## Verifies successful state transitions via change_state.
func test_change_state_success() -> void:
	print("TestStateMachine: Testing successful state change.")
	var state_a: DummyState = DummyState.new()
	state_a.name = "StateA"
	var state_b: DummyState = DummyState.new()
	state_b.name = "StateB"

	state_machine.add_child(state_a)
	state_machine.add_child(state_b)
	state_machine._ready()

	watch_signals(state_machine)
	var success: bool = state_machine.change_state("StateB")

	assert_true(success, "change_state should return true on success.")
	assert_true(state_a.exit_called, "Old state exit() should be called.")
	assert_true(state_b.enter_called, "New state enter() should be called.")
	assert_eq(
		state_machine.get_current_state(), state_b, "Current state should be updated to StateB."
	)
	assert_signal_emitted(state_machine, "state_changed", "state_changed signal should emit.")


## Verifies transitions are blocked when locked.
func test_change_state_locked() -> void:
	print("TestStateMachine: Testing locked state transition.")
	var state_a: DummyState = DummyState.new()
	state_a.name = "StateA"
	var state_b: DummyState = DummyState.new()
	state_b.name = "StateB"

	state_machine.add_child(state_a)
	state_machine.add_child(state_b)
	state_machine._ready()

	state_machine.is_locked = true
	var success: bool = state_machine.change_state("StateB")

	assert_false(success, "change_state should fail when locked.")
	assert_false(state_b.enter_called, "StateB should not be entered.")
	assert_eq(state_machine.get_current_state(), state_a, "Current state should remain StateA.")


## Verifies missing state transitions fail gracefully.
func test_change_state_not_found() -> void:
	print("TestStateMachine: Testing missing state transition.")
	var state_a: DummyState = DummyState.new()
	state_a.name = "StateA"

	state_machine.add_child(state_a)
	state_machine._ready()

	var success: bool = state_machine.change_state("NonExistentState")
	assert_false(success, "Transition to missing state should fail.")


## Verifies transition_requested signal binding triggers state change.
func test_transition_requested_signal() -> void:
	print("TestStateMachine: Testing transition_requested signal binding.")
	var state_a: DummyState = DummyState.new()
	state_a.name = "StateA"
	var state_b: DummyState = DummyState.new()
	state_b.name = "StateB"

	state_machine.add_child(state_a)
	state_machine.add_child(state_b)
	state_machine._ready()

	state_a.emit_transition("StateB")
	assert_eq(
		state_machine.get_current_state(),
		state_b,
		"Emitting transition_requested should change state."
	)
