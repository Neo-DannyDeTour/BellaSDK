class_name StatePathSlide
extends PlayerState

## The specific stick object the player is sliding on.
var active_stick: PathStick = null

## The positional offset from the stick to visually hang correctly.
var hold_offset: Vector3 = Vector3(0.0, -1.0, 0.0)


func enter(msg: Dictionary = {}) -> void:
	print("StatePathSlide: enter() called. Player entered path slide state.")
	var typed_player: Player = player as Player
	active_stick = msg.get("stick") as PathStick

	if is_instance_valid(typed_player) and is_instance_valid(typed_player.locomotion_component):
		typed_player.locomotion_component.set_physics_active(false)


func exit() -> void:
	print("StatePathSlide: exit() called. Player exited path slide state.")
	var typed_player: Player = player as Player

	if is_instance_valid(typed_player) and is_instance_valid(typed_player.locomotion_component):
		typed_player.locomotion_component.set_physics_active(true)

	if is_instance_valid(active_stick):
		active_stick.release_player()

	active_stick = null


func handle_input(event: InputEvent) -> void:
	# Allow the player to drop off manually at any time
	if event.is_action_pressed("jump") or event.is_action_pressed("crouch"):
		print("StatePathSlide: handle_input() called. Player manually dropping off stick.")
		var typed_player: Player = player as Player
		if is_instance_valid(typed_player):
			typed_player.exit_path_slide()


func physics_update(_delta: float) -> void:
	if not is_instance_valid(active_stick) or not is_instance_valid(player):
		return

	player.global_position = active_stick.global_position + hold_offset
