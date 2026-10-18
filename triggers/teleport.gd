## A volume that instantly moves the player to a connected portal node.
##
## Facilitates instant relocation from this [Area3D] to the assigned [member connect_portal].
class_name Teleport
extends Area3D

## The target portal [Area3D] to teleport the player to.
@export_category("Portal References")
@export var connect_portal: Area3D

## The audio player for the teleportation sound effect.
@export var portal_sound: AudioStreamPlayer


## Connects the entry signal. Called when the node enters the scene tree.
func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	if portal_sound == null:
		portal_sound = get_node_or_null("AudioStreamPlayer") as AudioStreamPlayer


## Triggers the teleport action if the player enters the volume.
## [param body] The physics body that entered the [Area3D].
func _on_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body):
		return

	if not body.name.begins_with("Player") and not body.is_in_group("player"):
		return

	print("Portal triggered: Player detected, starting teleport sequence.")

	if is_instance_valid(connect_portal):
		var destination: Vector3 = connect_portal.global_position
		body.global_position = destination
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
