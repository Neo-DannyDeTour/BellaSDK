## State handling player transport inside a [PneumaticTube] in crouched stance.
class_name StateTube
extends PlayerState

## Active tube instance currently carrying the player character.
var active_tube: Node3D = null

## Tracks whether the player character was crouched prior to suction.
var _was_crouched_before: bool = false


## Forces crouch height, disables movement physics, and caches entry state.
func enter(msg: Dictionary = {}) -> void:
	print("StateTube: enter() called. Player entering tube state.")
	active_tube = msg.get("tube") as Node3D
	var pl: Player = player as Player

	if is_instance_valid(pl) and is_instance_valid(pl.locomotion_component):
		var loco: PlayerLocomotionComponent = pl.locomotion_component as PlayerLocomotionComponent
		if loco != null:
			_was_crouched_before = loco.crouching
			loco.crouching = true
			if is_instance_valid(loco.standing_collision):
				loco.standing_collision.disabled = true
			if is_instance_valid(loco.crouching_collision):
				loco.crouching_collision.disabled = false
			if is_instance_valid(loco.head):
				loco.head.position.y = PlayerLocomotionComponent.CROUCHING_HEIGHT
			loco.reset_momentum()
			loco.set_physics_active(false)


## Restores original stance collisions and re-enables locomotion physics.
func exit() -> void:
	print("StateTube: exit() called. Player exiting tube state.")
	var pl: Player = player as Player

	if is_instance_valid(pl) and is_instance_valid(pl.locomotion_component):
		var loco: PlayerLocomotionComponent = pl.locomotion_component as PlayerLocomotionComponent
		if loco != null:
			loco.crouching = _was_crouched_before
			if is_instance_valid(loco.standing_collision):
				loco.standing_collision.disabled = _was_crouched_before
			if is_instance_valid(loco.crouching_collision):
				loco.crouching_collision.disabled = not _was_crouched_before
			if is_instance_valid(loco.head):
				var target_y: float = (
					PlayerLocomotionComponent.CROUCHING_HEIGHT
					if _was_crouched_before
					else PlayerLocomotionComponent.STANDING_HEIGHT
				)
				loco.head.position.y = target_y
			loco.set_physics_active(true)

	active_tube = null


## Unhandled input routing during tube transport.
func handle_input(_event: InputEvent) -> void:
	pass


## Process frame tick during tube transport.
func update(_delta: float) -> void:
	pass


## Physics frame tick ensuring player velocity is locked while moving on path.
func physics_update(_delta: float) -> void:
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
