## Player locomotion state machine extending [StateMachine] with player injection.
class_name PlayerStateMachine
extends StateMachine

## Emitted when state transitions to new state, passing state name string.
signal transitioned(state_name: String)

## Cached reference to controlling [CharacterBody3D] player instance.
var player: CharacterBody3D = null

## Backward-compatible accessor property exposing [member current_state].
var state: State:
	get:
		return current_state
	set(value):
		current_state = value


## Injects player dependencies into child states and enters initial state.
func _ready() -> void:
	print("PlayerStateMachine: Initializing player state machine on: ", name)
	if owner != null:
		await owner.ready
		player = owner as CharacterBody3D

	for child: Node in get_children():
		if &"player" in child:
			child.set(&"player", player)

	state_changed.connect(_on_state_machine_state_changed)
	super._ready()


## Transitions to a new state passing an optional payload dictionary.
func transition_to(target_state_name: StringName, msg: Dictionary = {}) -> void:
	print("PlayerStateMachine: Transitioning to: ", target_state_name)
	change_state(target_state_name, msg)


## Relays base [signal StateMachine.state_changed] to legacy [signal transitioned].
func _on_state_machine_state_changed(_old_state: State, new_state: State) -> void:
	print("PlayerStateMachine: State transitioned to: ", new_state.name)
	transitioned.emit(String(new_state.name))
