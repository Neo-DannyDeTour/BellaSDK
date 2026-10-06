## Hazard volume resetting player transform to checkpoint upon collision.
class_name Killfield
extends Area3D

## Vertical offset applied to respawn position above ground level.
@export var spawn_height_offset: float = 1.0


## Connects entry signal to collision response callback on scene initialization.
func _ready() -> void:
	print("Killfield: _ready() called. Connecting body_entered signal.")
	body_entered.connect(_on_body_entered)


## Teleports player body back to last checkpoint upon hazard boundary entry.
func _on_body_entered(body: Node3D) -> void:
	print("Killfield: _on_body_entered() triggered by node: ", body.name)
	if body.name == "Player" or body.is_in_group(&"Player"):
		if "noclip" in body and bool(body.get(&"noclip")) == true:
			return

		if SaveManager.last_checkpoint_pos != Vector3.ZERO:
			var safe_drop_position: Vector3 = (
				SaveManager.last_checkpoint_pos + Vector3(0.0, spawn_height_offset, 0.0)
			)

			if body.has_method(&"teleport_to"):
				body.call(&"teleport_to", safe_drop_position, 0.2)
			else:
				push_warning("Killfield: Player missing 'teleport_to' function!")
