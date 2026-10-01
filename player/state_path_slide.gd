## Handles rail and stick sliding locomotion along predefined paths in [StatePathSlide].
class_name StatePathSlide
extends PlayerState

## The specific [PathStick] node the player is currently sliding on.
var active_stick: PathStick = null

## Positional offset relative to stick to visually hang correctly.
var hold_offset: Vector3 = Vector3(0.0, -1.0, 0.0)


## Suspends locomotion physics and anchors player to sliding stick.
func enter(msg: Dictionary = {}) -> void:
	print("StatePathSlide: enter() called. Player mounting path slide stick.")
	var typed_player: Player = player as Player
	active_stick = msg.get(&"stick") as PathStick

	if is_instance_valid(typed_player) and is_instance_valid(typed_player.locomotion_component):
		typed_player.locomotion_component.set_physics_active(false)


## Restores locomotion physics and releases player from active stick.
func exit() -> void:
	print("StatePathSlide: exit() called. Player releasing from path slide.")
	var typed_player: Player = player as Player

	if is_instance_valid(typed_player) and is_instance_valid(typed_player.locomotion_component):
		typed_player.locomotion_component.set_physics_active(true)

	if is_instance_valid(active_stick):
		active_stick.release_player()

	active_stick = null


## Evaluates jump or crouch inputs to manually drop off sliding stick.
func handle_input(event: InputEvent) -> void:
	print("StatePathSlide: handle_input() polling manual drop gestures.")
	if event.is_action_pressed(&"jump") or event.is_action_pressed(&"crouch"):
		print("StatePathSlide: Player requested manual stick release.")
		var typed_player: Player = player as Player
		if is_instance_valid(typed_player):
			typed_player.exit_path_slide()


## Keeps player anchored to moving [PathStick] position each frame.
func physics_update(_delta: float) -> void:
	print("StatePathSlide: physics_update() updating stick anchor transform.")
	if not is_instance_valid(active_stick) or not is_instance_valid(player):
		return

	player.global_position = active_stick.global_position + hold_offset
