## A volume that instantly moves the player to a connected portal node.
##
## Facilitates instant relocation from this [Area3D] to the assigned [member connect_portal].
class_name Teleport
extends Area3D

## The target portal [Area3D] to teleport the player to.
@export_category("Portal References")
@export var connect_portal: Area3D

# Highly recommended: Change this node to an AudioStreamPlayer (non-3D) in your scene
# if you want the sound to be heard clearly regardless of player position.
## The audio player for the teleportation sound effect.
@onready var portal_sound: AudioStreamPlayer = $AudioStreamPlayer


## Connects the entry signal.
func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Triggers the teleport action if the player enters the volume.
func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return

	print("Portal triggered: Player detected, starting teleport sequence.")

	if is_instance_valid(connect_portal):
		var destination: Vector3 = connect_portal.global_transform.origin
		body.global_transform.origin = destination
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
