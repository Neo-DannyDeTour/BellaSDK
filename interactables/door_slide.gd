## A basic sliding door that responds to player proximity using physics triggers.
##
## Automatically manages its own state transitions (opening and closing animations)
## and incorporates logic to handle rapid enter/exit events gracefully.
class_name DoorSlide
extends Node3D

## Indicates whether the door's geometry is currently in motion.
var is_moving: bool = false
## Tracks if the door has reached its fully open state.
var is_open: bool = false
## Caches if the player is currently standing inside the proximity trigger zone.
var player_detected: bool = false
## Flags whether an open command was issued while the door was still closing.
var pending_open: bool = false

## Handles the actual spatial movement of the door meshes.
@onready var anim_player: AnimationPlayer = $Anim
## Delays the door closing automatically if the player steps out of the zone briefly.
@onready var close_timer: Timer = $CloseTimer


## Opens the door if a player steps into the interaction bounds.
## [param body]: The 3D physics node that entered the area.
func _on_detector_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not is_open and not is_moving:
		close_timer.stop()
		open()
		player_detected = true
	elif body.is_in_group("player") and is_moving:
		pending_open = true
		player_detected = true


## Begins the auto-closing sequence once the player leaves the interaction bounds.
## [param body]: The 3D physics node that exited the area.
func _on_detector_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and is_open and not is_moving:
		close_timer.start()
		close()
		player_detected = false
		pending_open = false


## Triggers the animation to open the door, waiting for completion before updating internal states.
func open() -> void:
	is_moving = true
	anim_player.play("Open")
	await anim_player.animation_finished
	is_open = true
	is_moving = false
	print("OPEN")

	if close_timer.time_left > 0:
		pass
	elif close_timer.time_left == 0 and not player_detected:
		close()


## Reverses the animation to close the door, checking for pending reopen requests afterward.
func close() -> void:
	is_moving = true
	anim_player.play_backwards("Open")
	await anim_player.animation_finished
	is_open = false
	is_moving = false
	pending_open = false
	print("CLOSE")

	if pending_open or player_detected:
		open()
		pending_open = false
