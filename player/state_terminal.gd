## Manages player immobility and gravity while focused on an interactive terminal.
class_name StateTerminal
extends PlayerState

## Reference to the active terminal [Node3D] passed during state entry.
var active_terminal: Node3D = null

## Cached reference to [PlayerLocomotionComponent] on the player character.
var _locomotion: PlayerLocomotionComponent = null


## Halts player locomotion and caches active terminal on state entry.
## [param msg] Initialization dictionary payload containing terminal node reference.
func enter(msg: Dictionary = {}) -> void:
	print("StateTerminal: Entered terminal state. Locomotion suspended.")
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
		_locomotion = player.locomotion_component as PlayerLocomotionComponent
		if is_instance_valid(_locomotion):
			_locomotion.set_physics_active(false)

	if msg.has("terminal") and msg["terminal"] is Node3D:
		active_terminal = msg["terminal"] as Node3D


## Restores locomotion physics and releases terminal reference on state exit.
func exit() -> void:
	print("StateTerminal: Exiting terminal state. Restoring locomotion physics.")
	active_terminal = null
	if is_instance_valid(_locomotion):
		_locomotion.set_physics_active(true)
	_locomotion = null


## Maintains stationary character position while applying downward gravity.
## [param delta] The physics frame delta time in seconds.
func physics_update(delta: float) -> void:
	if not is_instance_valid(player):
		return

	player.velocity.x = 0.0
	player.velocity.z = 0.0

	if not player.is_on_floor():
		player.velocity.y -= player.get_gravity().y * delta
	else:
		player.velocity.y = -0.1

	player.move_and_slide()
