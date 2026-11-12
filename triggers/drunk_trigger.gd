@tool
## Trigger volume activating or clearing screen drunk distortion and camera sway.
class_name DrunkTrigger
extends BaseTriggerArea3D

@export_group("Drunk Effect Settings")
## Target normalized drunk intensity reached on player entry [0.0, 1.0].
@export_range(0.0, 1.0, 0.05) var target_intensity: float = 1.0

## Duration in seconds to transition to [member target_intensity].
@export var transition_duration: float = 0.8

## If true, clears the drunk effect back to 0.0 when the player exits the volume.
@export var revert_on_exit: bool = true

## Duration in seconds to revert back to 0.0 when exiting the volume.
@export var exit_duration: float = 1.0


## Initializes default trigger text label for editor visualizer.
func _ready() -> void:
	if trigger_text == "TRIGGER":
		trigger_text = "DRUNK TRIGGER"
	super._ready()


## Dispatches drunk intensity transition on player entry.
func _on_player_entered(player_node: Node3D) -> void:
	print("DrunkTrigger: Player entered -> ", player_node.name, " (target: ", target_intensity, ")")
	if Events.has_signal(&"drunk_intensity_changed"):
		Events.drunk_intensity_changed.emit(target_intensity, transition_duration)


## Reverts drunk intensity on player exit if [member revert_on_exit] is true.
func _on_player_exited(player_node: Node3D) -> void:
	print("DrunkTrigger: Player exited -> ", player_node.name)
	if revert_on_exit and Events.has_signal(&"drunk_intensity_changed"):
		Events.drunk_intensity_changed.emit(0.0, exit_duration)
