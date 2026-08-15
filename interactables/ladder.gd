@tool
## A physics volume that triggers the player's climbing locomotion state.
##
## Features an editor-only debug mesh and directional arrow to help level designers visually
## align the climbing surface correctly against walls.
class_name Ladder
extends Area3D

## The physical dimensions of the climbing trigger volume.
@export var ladder_size: Vector3 = Vector3(2.2, 5.0, 0.5):
	set(value):
		ladder_size = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_visuals()

## An editor-only mesh indicating the "front" or mountable face of the ladder.
@onready var arrow: MeshInstance3D = $Arrow


## Hides editor helpers and meshes when entering play mode.
func _ready() -> void:
	if Engine.is_editor_hint():
		# We are in the editor. Apply the sizes.
		_update_visuals()
	else:
		if is_instance_valid(arrow):
			arrow.hide()
		# We are actually playing the game. Hide the mesh as usual.
		if has_node("MeshInstance3D"):
			get_node("MeshInstance3D").hide()


## Synchronizes the collision box and editor debug mesh sizes to match the inspector settings.
func _update_visuals() -> void:
	# Update the collision box size safely
	if has_node("CollisionShape3D"):
		var col_shape: Shape3D = get_node("CollisionShape3D").get("shape") as Shape3D
		if col_shape is BoxShape3D:
			col_shape.size = ladder_size

	# Update the mesh block size safely
	if has_node("MeshInstance3D"):
		var mesh_shape: Mesh = get_node("MeshInstance3D").get("mesh") as Mesh
		if mesh_shape is BoxMesh:
			mesh_shape.size = ladder_size


## Checks if the entering body supports ladder climbing and triggers its mount logic.
## [param body]: The 3D physics body entering the trigger.
func _on_body_entered(body: Node3D) -> void:
	# Ignore collisions while we are just editing the level
	if Engine.is_editor_hint():
		return

	if body.has_method("enter_ladder"):
		print("LadderArea: '", body.name, "' has entered the ladder trigger.")
		body.call("enter_ladder", self)


## Notifies the climbing body to detach and return to normal locomotion.
## [param body]: The 3D physics body exiting the trigger.
func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.has_method("exit_ladder"):
		print("LadderArea: '", body.name, "' has exited the ladder trigger.")
		body.call("exit_ladder", self)
