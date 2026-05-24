extends Area3D

@export var spawn_height_offset: float = 1.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.name == "Player" or body.is_in_group("Player"):
		if "noclip" in body and body.noclip == true:
			return

		if SaveSystem.last_checkpoint_pos != Vector3.ZERO:
			var safe_drop_position := (
				SaveSystem.last_checkpoint_pos + Vector3(0, spawn_height_offset, 0)
			)

			# Trigger the player's internal teleport and glue them for 0.2 seconds
			if body.has_method("teleport_to"):
				body.teleport_to(safe_drop_position, 0.2)
			else:
				push_warning("Killfield: Player missing 'teleport_to' function!")
