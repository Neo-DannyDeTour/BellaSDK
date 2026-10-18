@tool
## Detection volume that activates an associated shell trap upon entity entry.
## Synchronizes volume bounds with an integrated [EditorTriggerVisualizer].
class_name CrabShellTrigger
extends BaseTriggerArea3D

@export_group("Trap Configuration")
## Target shell node instance activated by this volume via [method trigger_drop].
@export var linked_shell: Node3D


## Initializes default trigger appearance and bounds.
func _ready() -> void:
	if trigger_text == "TRIGGER":
		trigger_text = "CRAB TRAP"
	if trigger_color == Color(0.9, 0.5, 0.1, 0.25):
		trigger_color = Color(0.9, 0.2, 0.2, 0.25)
	if outline_color == Color(1.0, 0.8, 0.3, 0.9):
		outline_color = Color(1.0, 0.4, 0.3, 0.9)
	super._ready()


## Activates linked shell instance when an entity enters volume.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(body):
		return

	if body is CharacterBody3D or _is_player(body):
		print("CrabShellTrigger: Character detected, launching shell.")
		if is_instance_valid(linked_shell):
			if linked_shell.has_method(&"trigger_drop"):
				linked_shell.call(&"trigger_drop")
		queue_free()
