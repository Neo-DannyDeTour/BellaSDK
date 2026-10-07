## Finite state machine executing lifecycle hooks and typed transitions.
class_name StateMachine
extends Node

# --------------------------------------
# SIGNALS
# --------------------------------------
## Emitted when active state changes, passing old and new [State] nodes.
signal state_changed(old_state: State, new_state: State)

# --------------------------------------
# EXPORTS
# --------------------------------------
## Initial active [State] set upon state machine initialization.
@export var initial_state: State

## Tracks whether state transitions are currently locked.
@export var is_locked: bool = false

# --------------------------------------
# RUNTIME STATE
# --------------------------------------
## Currently active [State] instance processing frame updates.
var current_state: State = null

## Internal dictionary mapping state names to [State] child nodes.
var _states: Dictionary[StringName, State] = {}


## Collects child states, binds transitions, and enters initial state.
func _ready() -> void:
	print("StateMachine: Initializing state machine: ", name)
	_collect_states()

	if self is PlayerStateMachine:
		return

	if is_instance_valid(initial_state):
		change_state(initial_state.name)
	elif not _states.is_empty():
		var fallback_state: State = _states.values()[0] if _states.values()[0] is State else null
		change_state(fallback_state.name)
	else:
		push_warning("StateMachine: No states configured on: " + name)


## Scans child nodes and registers all valid child [State] instances.
func _collect_states() -> void:
	print("StateMachine: Collecting child states on: ", name)
	_states.clear()

	for child: Node in get_children():
		if child is State:
			var state_node: State = child if child is State else null
			state_node.state_machine = self
			state_node.transition_requested.connect(_on_transition_requested)
			_states[state_node.name] = state_node
			print("StateMachine: Registered state: ", state_node.name)


## Forwards process frame tick to active [State] update hook.
func _process(delta: float) -> void:
	if is_instance_valid(current_state):
		current_state.update(delta)


## Forwards physics tick to active [State] physics update hook.
func _physics_process(delta: float) -> void:
	if is_instance_valid(current_state):
		current_state.physics_update(delta)


## Forwards unhandled input events to active [State] input hook.
func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(current_state):
		current_state.handle_input(event)


## Transitions active state to [param target_state_name] with payload.
func change_state(target_state_name: StringName, message: Dictionary = {}) -> bool:
	print("StateMachine: Transition requested to: ", target_state_name)
	if is_locked:
		print("StateMachine: Transition rejected, state machine is locked.")
		return false

	var target_state: State = (
		_states.get(target_state_name) if _states.get(target_state_name) is State else null
	)
	if not is_instance_valid(target_state):
		push_warning("StateMachine: Target state not found: " + str(target_state_name))
		return false

	if target_state == current_state:
		return false

	var old_state: State = current_state

	if is_instance_valid(current_state):
		current_state.exit()

	current_state = target_state
	current_state.enter(message)

	state_changed.emit(old_state, current_state)
	return true


## Alias forwarding transition requests to [method change_state].
func transition_to(target_state_name: StringName, message: Dictionary = {}) -> bool:
	return change_state(target_state_name, message)


## Callback receiving transition signals from individual state nodes.
func _on_transition_requested(target_state_name: StringName, message: Dictionary = {}) -> void:
	print("StateMachine: Received transition signal to: ", target_state_name)
	change_state(target_state_name, message)


## Returns currently active [State] instance.
func get_current_state() -> State:
	return current_state


## Checks whether given state name matches currently active state.
func is_in_state(state_name: StringName) -> bool:
	if not is_instance_valid(current_state):
		return false
	return current_state.name == state_name
