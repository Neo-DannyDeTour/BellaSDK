## A state machine that manages the active state for the player character.
##
## This node routes input, process, and physics_process callbacks to the active [PlayerState],
## while providing methods to transition between different states smoothly.
class_name PlayerStateMachine
extends Node

## Emitted when the state machine successfully transitions to a new state.
signal transitioned(state_name: String)

@export_category("State Machine Configuration")
## Set this in the inspector (e.g., assign the "Walk" or "Idle" node) to dictate the starting state.
@export var initial_state: NodePath

## The currently active player state handling engine ticks and physics processing.
@onready var state: PlayerState = get_node(initial_state) as PlayerState

## Cache for O(1) state transitions, mapping string state names directly to their node references.
var _states: Dictionary = {}


## Initializes the state machine by injecting dependencies into child [PlayerState] nodes
## and booting the initial state.
func _ready() -> void:
	print("PlayerStateMachine: _ready() called. Awaiting owner readiness.")
	await owner.ready

	print("PlayerStateMachine: Owner ready. Injecting dependencies into child states.")
	for child: Node in get_children():
		if child is PlayerState:
			child.state_machine = self
			child.player = owner as CharacterBody3D
			_states[child.name] = child

	print("PlayerStateMachine: Booting initial state: ", state.name)
	state.enter({})


## Routes unhandled input events to the currently active state.
func _unhandled_input(event: InputEvent) -> void:
	state.handle_input(event)


## Routes process ticks to the currently active state.
func _process(delta: float) -> void:
	state.update(delta)


## Routes physics process ticks to the currently active state.
func _physics_process(delta: float) -> void:
	state.physics_update(delta)


## Transitions the state machine to a new state specified by [param target_state_name].
## An optional dictionary [param msg] can be passed to the new state's `enter` method.
func transition_to(target_state_name: String, msg: Dictionary = {}) -> void:
	print("PlayerStateMachine: transition_to() called. Transitioning to state: ", target_state_name)

	if not _states.has(target_state_name):
		push_error(
			"StateMachine: Cannot transition to state '%s' (Node not found)." % target_state_name
		)
		return

	state.exit()
	state = _states[target_state_name]
	state.enter(msg)

	transitioned.emit(state.name)
