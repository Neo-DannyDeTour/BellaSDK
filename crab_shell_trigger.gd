extends Area3D
class_name CrabShellTrigger

## Node reference to the CrabShell that should be activated by this volume.
@export var linked_shell: CrabShell


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		print("Trigger volume activated: Character detected, launching shell.")
		if linked_shell:
			linked_shell.trigger_drop()
		queue_free()
