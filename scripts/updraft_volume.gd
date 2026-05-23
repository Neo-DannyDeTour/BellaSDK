extends Area3D

# Expose the strength so you can have gentle vents and massive launch pads!
@export var lift_strength: float = 12.0


func _ready() -> void:
	$MeshInstance3D.hide()


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_updraft"):
		body.enter_updraft(lift_strength)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_updraft"):
		body.exit_updraft()
