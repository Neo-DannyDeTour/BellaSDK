## An Area3D volume that triggers an associated CrabShell on detection.
##
## Drop point logic for crab shell traps.
class_name CrabShellTrigger
extends Area3D

## Node reference to the [CrabShell] that should be activated by this volume.
@export var linked_shell: CrabShell


## Connects the entry signal. Called when the node enters the scene tree.
##
## Lifecycle triggers: Called on `_ready` by engine.
## No parameters.
## Returns: void.
func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Activates the linked shell when a [CharacterBody3D] enters the volume.
##
## Lifecycle triggers: Connected to body_entered signal.
## [param body] The physics body that entered the [Area3D].
## Returns: void.
func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		print("Trigger volume activated: Character detected, launching shell.")
		if is_instance_valid(linked_shell):
			linked_shell.trigger_drop()
		queue_free()
