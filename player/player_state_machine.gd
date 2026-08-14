class_name PlayerStateMachine
extends Node

# --------------------------------------
# SIGNALS
# --------------------------------------
## Emitted when the state machine successfully transitions to a new state.
signal transitioned(state_name: String)

# --------------------------------------
# EXPORTS & VARIABLES
# --------------------------------------
@export_category("State Machine Configuration")
## Set this in the inspector (e.g., assign the "Walk" or "Idle" node) to dictate the starting state.
@export var initial_state: NodePath

## The currently active player state handling engine ticks and physics processing.
@onready var state: PlayerState = get_node(initial_state) as PlayerState

## Cache for O(1) state transitions, mapping string state names directly to their node references.
var _states: Dictionary = {}


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


# --------------------------------------
# ENGINE TICK ROUTING
# --------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	state.handle_input(event)


func _process(delta: float) -> void:
	state.update(delta)


func _physics_process(delta: float) -> void:
	state.physics_update(delta)


# --------------------------------------
# TRANSITION LOGIC
# --------------------------------------
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
