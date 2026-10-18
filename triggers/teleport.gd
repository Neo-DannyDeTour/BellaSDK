@tool
## A volume that instantly moves the player to a connected portal node.
##
## Facilitates instant relocation from this [Area3D] to the assigned [member connect_portal].
class_name Teleport
extends BaseTriggerArea3D

## The target portal [Area3D] to teleport the player to.
@export_category("Portal References")
@export var connect_portal: Area3D

## The audio player for the teleportation sound effect.
@export var portal_sound: AudioStreamPlayer


## Configures default trigger properties allowing continuous portal re-entry.
func _init() -> void:
	trigger_once = false


## Prepares audio player references and initializes base trigger bounds.
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	if portal_sound == null:
		portal_sound = get_node_or_null("AudioStreamPlayer") as AudioStreamPlayer


## Triggers the teleport action when the player enters the volume.
func _on_player_entered(player: Node3D) -> void:
	print("Portal triggered: Player detected, starting teleport sequence.")

	if is_instance_valid(connect_portal):
		var destination: Vector3 = connect_portal.global_position
		player.global_position = destination
		print("Portal executing: Player transformed to destination.")

		_play_portal_sounds()
	else:
		print("Portal executing: Warning - No connect_portal assigned.")


## Plays the portal sound effect if valid.
func _play_portal_sounds() -> void:
	if not is_instance_valid(portal_sound):
		print("Portal executing: Warning - No portal_sound node found.")
		return

	print("Portal executing: Playing random portal stream.")
	portal_sound.play()
