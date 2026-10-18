@tool
## Trigger volume initiating an animation sequence when entered by the player.
##
## [SpotlightSeqTrigger] detects player entry and triggers a lighting sequence
## via the configured [member sequence_player].
class_name SpotlightSeqTrigger
extends BaseTriggerArea3D

@export_group("Sequence")
## The animation player responsible for executing the sequence.
@export var sequence_player: AnimationPlayer


## Initializes default trigger text label for editor visualizer.
func _ready() -> void:
	if trigger_text == "TRIGGER":
		trigger_text = "SPOTLIGHT_SEQ"
	super._ready()


## Plays the configured lighting sequence when a valid player enters.
func _on_player_entered(_player_node: Node3D) -> void:
	print("SpotlightSeqTrigger: Player entered trigger. Executing lighting sequence.")
	if is_instance_valid(sequence_player):
		sequence_player.play("turn_off_lights")
	else:
		push_error("SpotlightSeqTrigger: No AnimationPlayer assigned!")
