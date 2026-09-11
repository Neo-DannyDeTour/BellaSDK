## Manages the active state and transitions for the player character.
class_name PlayerStateMachine
extends Node

## Emitted when the state machine transitions to the given state.
##
## [param state_name] The name of the new state.
signal transitioned(state_name: String)

@export_category("State Machine Configuration")

## Inspector path pointing to the initial [PlayerState] node.
@export var initial_state: NodePath

## The currently active player state handling engine ticks.
@onready var state: PlayerState = get_node(initial_state) as PlayerState

## Cache for O(1) state transitions mapping state names to nodes.
var _states: Dictionary = {}


## Lifecycle method injecting dependencies into child state nodes.
func _ready() -> void:
	print("PlayerStateMachine: _ready() called. Awaiting owner readiness.")
	await owner.ready

	print("PlayerStateMachine: Owner ready. Injecting dependencies.")
	for child: Node in get_children():
		if child is PlayerState:
			child.state_machine = self
			child.player = owner as CharacterBody3D
			_states[child.name] = child

	print("PlayerStateMachine: Booting initial state: ", state.name)
	state.enter({})


## Routes unhandled input events to the active state.
##
## [param event] The [InputEvent] to be handled.
func _unhandled_input(event: InputEvent) -> void:
	state.handle_input(event)


## Routes process ticks to the active state.
##
## [param delta] The process frame delta time.
func _process(delta: float) -> void:
	state.update(delta)


## Routes physics process ticks to the active state.
##
## [param delta] The physics frame delta time.
func _physics_process(delta: float) -> void:
	state.physics_update(delta)


## Transitions to a new state passing optional data.
##
## [param target_state_name] The string name of the target [PlayerState] node.
## [param msg] Optional dictionary payload for state initialization.
func transition_to(target_state_name: String, msg: Dictionary = {}) -> void:
	print("PlayerStateMachine: transition_to() to: ", target_state_name)

	if not _states.has(target_state_name):
		push_warning(
			"StateMachine: Cannot transition to state '%s' (Node not found)." % target_state_name
		)
		return

	state.exit()
	state = _states[target_state_name] as PlayerState
	state.enter(msg)

	transitioned.emit(state.name)
