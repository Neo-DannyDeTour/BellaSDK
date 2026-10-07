## Handles player transit inside pneumatic transport tubes in [StateTube].
class_name StateTube
extends PlayerState

## Active tube instance currently carrying the player character.
var active_tube: Node3D = null

## Tracks whether the player was crouched prior to entering pneumatic tube.
var _was_crouched_before: bool = false


## Locks player stance to crouched, disables locomotion, and caches stance.
func enter(msg: Dictionary = {}) -> void:
	print("StateTube: enter() called. Player entering tube state.")
	var raw_tube: Variant = msg.get(&"tube")
	active_tube = raw_tube if raw_tube is Node3D else null
	var pl: Player = player if player is Player else null

	if is_instance_valid(pl) and is_instance_valid(pl.locomotion_component):
		var loco: PlayerLocomotionComponent = (
			pl.locomotion_component
			if pl.locomotion_component is PlayerLocomotionComponent
			else null
		)
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


## Restores pre-tube crouch stance and re-enables locomotion physics.
func exit() -> void:
	print("StateTube: exit() called. Player exiting tube state.")
	var pl: Player = player if player is Player else null

	if is_instance_valid(pl) and is_instance_valid(pl.locomotion_component):
		var loco: PlayerLocomotionComponent = (
			pl.locomotion_component
			if pl.locomotion_component is PlayerLocomotionComponent
			else null
		)
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


## Consumes input events during tube transit without affecting movement.
func handle_input(_event: InputEvent) -> void:
	print("StateTube: handle_input() consuming input event during tube transit.")


## Per-frame logic update executing during tube transport.
func update(_delta: float) -> void:
	print("StateTube: update() running visual update tick.")


## Locks player velocity to zero while traveling along pneumatic spline.
func physics_update(_delta: float) -> void:
	print("StateTube: physics_update() locking character velocity.")
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
