## A door node supporting manual interactions, proximity detection, and puzzle power systems.
class_name DoorInteract
extends Node3D

## The total amount of power required to activate this door.
@export var required_power: int = 1

## Determines if the door is currently open. Changing this updates animations.
@export var open: bool = false:
	set = _set_open

## Flags whether this is a locked puzzle door or a normal proximity/manual door.
var is_powered_door: bool = false

## Prevents the door from being toggled too rapidly by manual interactions.
var is_on_cooldown: bool = false

## The power component handling required and current power logic.
var power_component: PowerComponent

## The [AnimationPlayer] responsible for physical movement of door geometry.
@onready var animation_player: AnimationPlayer = $AnimatableBody3D/AnimationPlayer

## The [Timer] used to automatically close door after player leaves detector area.
@onready var timer: Timer = $Timer


## Initializes the door, checks for [PowerComponent], and connects signals.
func _ready() -> void:
	power_component = get_node_or_null("PowerComponent") as PowerComponent

	if is_instance_valid(power_component):
		is_powered_door = true
		power_component.required_power = required_power

		if not power_component.powered_on.is_connected(_on_powered_on):
			power_component.powered_on.connect(_on_powered_on)
		if not power_component.powered_off.is_connected(_on_powered_off):
			power_component.powered_off.connect(_on_powered_off)

	if is_instance_valid(animation_player):
		if open:
			animation_player.play("open")
			animation_player.seek(animation_player.current_animation_length, true)


## Triggered by [PowerComponent] when required power is met. Opens the door.
func _on_powered_on() -> void:
	print(
		"DoorInteract: ", name, " reached full power requirement (", required_power, "). Opening."
	)
	open = true


## Triggered by [PowerComponent] when power falls below required threshold. Closes the door.
func _on_powered_off() -> void:
	print("DoorInteract: ", name, " dropped below power threshold. Closing.")
	open = false


## Resolves visual state by playing the appropriate opening or closing animation.
func update_door() -> void:
	if not is_inside_tree() or not is_instance_valid(animation_player):
		return

	if not animation_player.has_animation("open"):
		print("DoorInteract: Warning - AnimationPlayer missing 'open' animation on ", name)
		return

	if open:
		print("DoorInteract: Playing 'open' forward on ", name)
		animation_player.play("open")
	else:
		print("DoorInteract: Playing 'open' backward on ", name)
		animation_player.play_backwards("open")


## Primary interface for player-driven interaction. Bypassed if puzzle-powered.
func interact() -> void:
	if is_powered_door:
		print("DoorInteract: Interaction blocked. ", name, " is locked by mechanism!")
		return

	print("DoorInteract: Player manually interacted with ", name)
	toggle_open()


## Swaps the current [member open] state with a cooldown to prevent animation spam.
## [param _player]: The player character initiating the toggle.
func toggle_open(_player: CharacterBody3D = null) -> void:
	if is_on_cooldown:
		return

	is_on_cooldown = true
	open = not open

	await get_tree().create_timer(1.0).timeout
	is_on_cooldown = false


## Starts auto-close timer when player leaves interaction range.
## [param body]: Physics body leaving the detector area.
func _on_detector_body_exited(body: Node3D) -> void:
	if is_powered_door:
		return

	if open and body.is_in_group("player") and is_instance_valid(timer):
		print("DoorInteract: Player left area. Starting auto-close timer.")
		timer.start()


## Stops auto-close timer if player returns to interaction range.
## [param body]: Physics body entering the detector area.
func _on_detector_body_entered(body: Node3D) -> void:
	if is_powered_door:
		return

	if body.is_in_group("player") and is_instance_valid(timer):
		if not timer.is_stopped():
			timer.stop()


## Closes door once proximity cooldown timer finishes.
func _on_timer_timeout() -> void:
	if is_powered_door:
		return

	if open:
		if not is_on_cooldown:
			is_on_cooldown = true
			open = false
			print("DoorInteract: Auto-close timer finished. Closing.")
			await get_tree().create_timer(1.0).timeout
			is_on_cooldown = false
		elif is_instance_valid(timer):
			timer.start(0.5)


## Setter for [member open] to cleanly trigger animations without recursing.
## [param value]: Target open state.
func _set_open(value: bool) -> void:
	if open == value:
		return
	open = value
	update_door()
