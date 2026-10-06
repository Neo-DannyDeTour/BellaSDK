## Player state locking character movement and freeing mouse cursor for UI interactions.
class_name StateMachineLock
extends PlayerState


## Locks player physics, zeroes momentum, and displays cursor for UI interaction.
func enter(_msg: Dictionary = {}) -> void:
	print("StateMachineLock: enter() initialized. Player physics locked.")

	var p: Player = player as Player
	if is_instance_valid(p):
		p.velocity = Vector3.ZERO
		var loco: PlayerLocomotionComponent = p.locomotion_component as PlayerLocomotionComponent
		if is_instance_valid(loco):
			loco.reset_momentum()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Corresponds to the [method _process] callback.
func update(_delta: float) -> void:
	pass


## Corresponds to the [method _physics_process] callback.
func physics_update(_delta: float) -> void:
	pass


## Swallows [InputEventMouseMotion] to prevent camera rotation while locked.
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


## Restores captured mouse mode when transitioning out of locked state.
func exit() -> void:
	print("StateMachineLock: exit() called. Player physics restored.")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
