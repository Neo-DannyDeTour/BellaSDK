extends Area3D

@export var lift_strength: float = 12.0


func _ready() -> void:
	$MeshInstance3D.hide()


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_updraft"):
		# Procedurally find the top of this specific vent volume
		var top_height: float = global_position.y

		for child in get_children():
			if child is CollisionShape3D and child.shape != null:
				if child.shape is BoxShape3D:
					top_height = child.global_position.y + (child.shape.size.y / 2.0)
				elif child.shape is CylinderShape3D:
					top_height = child.global_position.y + (child.shape.height / 2.0)
				break

		# Pass BOTH the strength and the top boundary to the player!
		body.enter_updraft(lift_strength, top_height)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_updraft"):
		body.exit_updraft()

#extends Area3D
#
## Expose the strength so you can have gentle vents and massive launch pads!
#@export var lift_strength: float = 12.0
#
#
#func _ready() -> void:
#$MeshInstance3D.hide()
#
#
#func _on_body_entered(body: Node3D) -> void:
#if body.has_method("enter_updraft"):
#body.enter_updraft(lift_strength)
#
#
#func _on_body_exited(body: Node3D) -> void:
#if body.has_method("exit_updraft"):
#body.exit_updraft()
