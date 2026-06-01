class_name PlayerStateMachine
extends Node

# --------------------------------------
# SIGNALS
# --------------------------------------
signal transitioned(state_name: String)

# --------------------------------------
# EXPORTS & VARIABLES
# --------------------------------------
# Set this in the inspector (e.g., assign the "Walk" or "Idle" node)
@export var initial_state: NodePath

@onready var state: PlayerState = get_node(initial_state)


func _ready() -> void:
	# Wait for the player body (owner) to be fully ready
	await owner.ready

	# Automatically inject dependencies into every child state
	for child: Node in get_children():
		if child is PlayerState:
			child.state_machine = self
			child.player = owner as CharacterBody3D

	# Boot up the first state
	state.enter()


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
	# Safety check: Does the state exist?
	if not has_node(target_state_name):
		push_error(
			"StateMachine: Cannot transition to state '%s' (Node not found)." % target_state_name
		)
		return

	# 1. Clean up the current state
	state.exit()

	# 2. Swap the active state reference
	state = get_node(target_state_name)

	# 3. Initialize the new state
	state.enter(msg)

	# 4. Notify external systems (like UI or animation controllers)
	transitioned.emit(state.name)
