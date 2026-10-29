## Player state locking character movement and freeing mouse cursor for UI interactions.
class_name StateMachineLock
extends PlayerState

## Tracks whether mouse capture mode should be preserved for remote machine operation.
var _is_mouse_captured: bool = false


## Locks player physics, zeroes momentum, and displays or captures cursor.
func enter(msg: Dictionary = {}) -> void:
	print("StateMachineLock: enter() initialized. Player physics locked.")

	var p: Player = player if player is Player else null
	if is_instance_valid(p):
		p.velocity = Vector3.ZERO
		var loco: PlayerLocomotionComponent = (
			p.locomotion_component if p.locomotion_component is PlayerLocomotionComponent else null
		)
		if is_instance_valid(loco):
			loco.reset_momentum()

	_is_mouse_captured = bool(msg.get("capture_mouse", false))
	if _is_mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Corresponds to the [method _process] callback.
func update(_delta: float) -> void:
	pass


## Corresponds to the [method _physics_process] callback.
func physics_update(_delta: float) -> void:
	pass


## Swallows [InputEventMouseMotion] for UI locks, allows it through for captured machine ops.
func handle_input(event: InputEvent) -> void:
	if not _is_mouse_captured and event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


## Restores captured mouse mode when transitioning out of locked state.
func exit() -> void:
	print("StateMachineLock: exit() called. Player physics restored.")
	_is_mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
