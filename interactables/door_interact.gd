## A door node supporting manual interactions, proximity detection, and puzzle power systems.
##
## Manages states. Can act as a manual door or a locked puzzle element depending
## on the presence of a child [PowerComponent].
class_name DoorInteract
extends Node3D

## The total amount of power required to activate this door. Exposed here so level designers don't
## have to dig into child nodes.
@export var required_power: int = 1

## Determines if the door is currently open. Changing this automatically updates animations.
@export var open: bool = false:
	set(v):
		if v != open:
			open = v
			if is_inside_tree():
				update_door()

## Flags whether this is a locked puzzle door or a normal proximity/manual door.
var is_powered_door: bool = false

## Prevents the door from being toggled too rapidly by manual interactions.
var is_on_cooldown: bool = false

## The power component handling required and current power logic. Will be null if this is a
## standard manual door.
var power_component: PowerComponent

## The [AnimationPlayer] responsible for the physical movement of the door geometry.
@onready var animation_player: AnimationPlayer = $AnimatableBody3D/AnimationPlayer

## The [Timer] used to automatically close the door after a player leaves the detector area.
@onready var timer: Timer = $Timer


## Initializes the door, checks for a linked [PowerComponent], and connects required power signals.
func _ready() -> void:
	# 1. Dynamically check for the component
	power_component = get_node_or_null("PowerComponent") as PowerComponent

	if is_instance_valid(power_component):
		is_powered_door = true

		# 2. Pass the designer's chosen number down to the component!
		power_component.required_power = self.required_power

		# 3. Connect the signals
		power_component.powered_on.connect(_on_powered_on)
		power_component.powered_off.connect(_on_powered_off)

	if open:
		update_door()


# --- PUZZLE LOGIC ---


## Triggered by the [PowerComponent] when the required threshold is met. Opens the door.
func _on_powered_on() -> void:
	print("PoweredDoor: PowerComponent reached full power. Opening.")
	open = true


## Triggered by the [PowerComponent] when power falls below the required threshold. Closes the door.
func _on_powered_off() -> void:
	print("PoweredDoor: PowerComponent lost full power. Closing.")
	open = false


# --- ANIMATION LOGIC ---


## Resolves visual state by playing the appropriate opening or closing animation.
func update_door() -> void:
	if not is_node_ready():
		await ready

	if open:
		print("PoweredDoor: Playing 'open' animation.")
		if animation_player.current_animation != "open":
			animation_player.play("open")
	else:
		print("PoweredDoor: Playing close animation (open backwards).")
		if (
			animation_player.current_animation != "open"
			or animation_player.current_animation_position > 0.0
		):
			animation_player.play_backwards("open")


# --- MANUAL INTERACT LOGIC ---


## Primary interface for player-driven interaction. Bypassed if the door is powered by a puzzle.
func interact() -> void:
	if is_powered_door:
		print("PoweredDoor: Interaction blocked. This door is locked by a mechanism!")
		return

	print("PoweredDoor: Player manually interacted with the door.")
	toggle_open()


## Swaps the current [member open] state, with a built-in cooldown to prevent animation spam.
## [param _player]: The player character initiating the toggle.
func toggle_open(_player: CharacterBody3D = null) -> void:
	if is_on_cooldown:
		return

	is_on_cooldown = true
	open = not open

	await get_tree().create_timer(1.0).timeout
	is_on_cooldown = false


# --- DETECTOR LOGIC ---


## Starts the auto-close timer when a player walks out of the interaction range.
## [param body]: The physics node leaving the trigger area.
func _on_detector_body_exited(body: Node3D) -> void:
	if is_powered_door:
		return

	if open and body.is_in_group("player"):
		print("PoweredDoor: Player exited proximity area. Starting auto-close timer.")
		timer.start()


## Stops the auto-close timer if a player steps back into the interaction range.
## [param body]: The physics node entering the trigger area.
func _on_detector_body_entered(body: Node3D) -> void:
	if is_powered_door:
		return

	if body.is_in_group("player"):
		print("PoweredDoor: Player entered proximity area.")
		if not timer.is_stopped():
			timer.stop()


## Closes the door once the proximity cooldown timer expires, unless interrupted.
func _on_timer_timeout() -> void:
	if is_powered_door:
		return

	if open:
		if not is_on_cooldown:
			is_on_cooldown = true
			open = false
			print("PoweredDoor: Auto-close timer finished. Closing.")

			await get_tree().create_timer(1.0).timeout
			is_on_cooldown = false
		else:
			timer.start(0.5)
