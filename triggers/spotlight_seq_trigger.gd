## A trigger volume that plays an animation sequence when entered by a character.
##
## [SpotlightSeqTrigger] is designed to detect [CharacterBody3D] nodes
## and play a one-shot lighting sequence via an [AnimationPlayer].
class_name SpotlightSeqTrigger
extends Area3D

## The animation player responsible for executing the sequence.
@export var sequence_player: AnimationPlayer

## Internal flag ensuring the sequence only triggers once.
var has_triggered: bool = false


## Connects the entry signal on node creation.
## Lifecycle trigger: _ready.
## Returns void.
func _ready() -> void:
	body_entered.connect(_on_body_entered)


## Checks if the entering body is a valid character and plays the sequence.
## [param body] The [Node3D] that entered the trigger area.
## Returns void.
func _on_body_entered(body: Node3D) -> void:
	if has_triggered:
		return

	# Check if the thing entering the trigger is the player.
	# Since your player is a CharacterBody3D, this is the safest check.
	if body is CharacterBody3D:
		has_triggered = true

		if sequence_player:
			sequence_player.play("turn_off_lights")
		else:
			push_error("SequenceTrigger: No AnimationPlayer assigned!")
