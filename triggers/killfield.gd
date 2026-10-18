@tool
## Hazard volume resetting player transform to checkpoint upon collision.
##
## [Killfield] detects player entry, verifies noclip status, and relocates
## the character back to the last recorded checkpoint position.
class_name Killfield
extends BaseTriggerArea3D

@export_group("Hazard")
## Vertical offset applied to respawn position above ground level.
@export var spawn_height_offset: float = 1.0


## Initializes trigger settings and prepares hazard collision response.
func _ready() -> void:
	print("Killfield: _ready() called. Connecting body_entered signal.")
	trigger_once = false
	if trigger_text == "TRIGGER":
		trigger_text = "KILLFIELD"
	super._ready()


## Logs body detection and forwards to base player verification logic.
func _on_body_entered(body: Node3D) -> void:
	if is_instance_valid(body):
		print("Killfield: _on_body_entered() triggered by node: ", body.name)
	super._on_body_entered(body)


## Teleports player body back to last checkpoint upon hazard boundary entry.
func _on_player_entered(player: Node3D) -> void:
	if "noclip" in player and player.get(&"noclip") == true:
		return

	if SaveManager.last_checkpoint_pos != Vector3.ZERO:
		var safe_drop_position: Vector3 = (
			SaveManager.last_checkpoint_pos + Vector3(0.0, spawn_height_offset, 0.0)
		)

		if player.has_method(&"teleport_to"):
			player.call(&"teleport_to", safe_drop_position, 0.2)
		else:
			push_warning("Killfield: Player missing 'teleport_to' function!")
