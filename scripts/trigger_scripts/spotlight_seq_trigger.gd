extends Area3D

@export var sequence_player: AnimationPlayer
var has_triggered: bool = false


func _ready() -> void:
	# Connect the signal through code so you don't have to use the node menu
	body_entered.connect(_on_body_entered)


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
