## Handles player immobility and gravity while operating interactive terminals.
class_name StateTerminal
extends PlayerState

## Reference to active terminal [Node3D] passed during state entry.
var active_terminal: Node3D = null

## Cached reference to [PlayerLocomotionComponent] on player character.
var _locomotion: PlayerLocomotionComponent = null


## Suspends locomotion physics and caches active terminal on state entry.
func enter(msg: Dictionary = {}) -> void:
	print("StateTerminal: enter() called. Player locked to terminal interface.")
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
		var typed_player: Player = player if player is Player else null
		if is_instance_valid(typed_player):
			_locomotion = typed_player.locomotion_component as PlayerLocomotionComponent
		else:
			_locomotion = (player.get(&"locomotion_component") as PlayerLocomotionComponent)
		if is_instance_valid(_locomotion):
			_locomotion.set_physics_active(false)

	if msg.has(&"terminal") and msg[&"terminal"] is Node3D:
		active_terminal = msg[&"terminal"] as Node3D


## Restores locomotion physics and releases terminal reference on exit.
func exit() -> void:
	print("StateTerminal: exit() called. Restoring locomotion physics.")
	active_terminal = null
	if is_instance_valid(_locomotion):
		_locomotion.set_physics_active(true)
	_locomotion = null


## Locks horizontal velocity while applying downward gravity acceleration.
func physics_update(delta: float) -> void:
	print("StateTerminal: physics_update() maintaining terminal immobility.")
	if not is_instance_valid(player):
		return

	player.velocity.x = 0.0
	player.velocity.z = 0.0

	if not player.is_on_floor():
		player.velocity.y -= player.get_gravity().y * delta
	else:
		player.velocity.y = -0.1

	player.move_and_slide()
