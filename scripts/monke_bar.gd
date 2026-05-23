extends Area3D


func _ready() -> void:
	$MeshInstance3D.hide()


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_available_monkey_bar"):
		body.set_available_monkey_bar(self)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_available_monkey_bar"):
		body.clear_available_monkey_bar(self)
