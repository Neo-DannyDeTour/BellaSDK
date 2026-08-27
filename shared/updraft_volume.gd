## An Area3D volume that applies an upward lift force to entities passing through it.
##
## Detects players and triggers their internal updraft state.
class_name UpdraftVolume
extends Area3D

## The vertical force applied to entities entering the updraft.
@export var lift_strength: float = 12.0


## Initializes the node by hiding the debug mesh. Called when the node enters the scene tree.
func _ready() -> void:
	$MeshInstance3D.hide()


## Called when a [Node3D] body enters the updraft area. Applies lift if the body supports it.
##
## @param body The physics body that entered the [Area3D].
func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_updraft"):
		# Procedurally find the top of this specific vent volume
		var top_height: float = global_position.y

		for child: Node in get_children():
			if child is CollisionShape3D and child.shape != null:
				if child.shape is BoxShape3D:
					top_height = child.global_position.y + (child.shape.size.y / 2.0)
				elif child.shape is CylinderShape3D:
					top_height = child.global_position.y + (child.shape.height / 2.0)
				break

		# Pass BOTH the strength and the top boundary to the player!
		body.enter_updraft(lift_strength, top_height)


## Called when a [Node3D] body exits the updraft area. Removes lift if the body supports it.
##
## @param body The physics body that exited the [Area3D].
func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_updraft"):
		body.exit_updraft()
