extends GutTest

## The target State instance we are testing
var _state: State


func before_each() -> void:
	print("Setting up test environment for State")
	_state = State.new()
	add_child_autofree(_state)


func test_enter() -> void:
	print("Testing State.enter()")
	_state.enter({"test": true})
	assert_true(true, "enter() executed without error")


func test_exit() -> void:
	print("Testing State.exit()")
	_state.exit()
	assert_true(true, "exit() executed without error")


func test_update() -> void:
	print("Testing State.update()")
	_state.update(0.1)
	assert_true(true, "update() executed without error")


func test_physics_update() -> void:
	print("Testing State.physics_update()")
	_state.physics_update(0.1)
	assert_true(true, "physics_update() executed without error")


func test_handle_input() -> void:
	print("Testing State.handle_input()")
	var input: InputEventKey = InputEventKey.new()
	_state.handle_input(input)
	assert_true(true, "handle_input() executed without error")


func test_transition_requested_signal() -> void:
	print("Testing transition_requested signal emission")
	watch_signals(_state)
	_state.transition_requested.emit(&"next_state", {"data": 1})
	assert_signal_emitted_with_parameters(
		_state, "transition_requested", [&"next_state", {"data": 1}]
	)
