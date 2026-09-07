@tool
## Physics trigger volume that attaches the player character to climbing locomotion.
class_name Ladder
extends Area3D

## Physical dimensions of the ladder interaction box and visual bounds.
@export var ladder_size: Vector3 = Vector3(2.2, 5.0, 0.5):
	set(value):
		ladder_size = value
		if is_inside_tree():
			_update_visuals()

## An editor-only mesh indicating the "front" or mountable face of the ladder.
@onready var arrow: MeshInstance3D = get_node_or_null("Arrow") as MeshInstance3D


## Initializes runtime visibility or applies inspector dimensions to editor gizmos.
func _ready() -> void:
	_update_visuals()

	if not Engine.is_editor_hint():
		if is_instance_valid(arrow):
			arrow.hide()
		if has_node("MeshInstance3D"):
			get_node("MeshInstance3D").hide()


## Resizes the collision box and editor debug mesh to match inspector bounds.
func _update_visuals() -> void:
	if has_node("CollisionShape3D"):
		var col_node: CollisionShape3D = get_node("CollisionShape3D") as CollisionShape3D
		if is_instance_valid(col_node) and col_node.shape is BoxShape3D:
			# Ensure the shape is unique per instance so ladders do not overwrite each other
			if Engine.is_editor_hint() and not col_node.shape.resource_local_to_scene:
				col_node.shape = col_node.shape.duplicate()
			(col_node.shape as BoxShape3D).size = ladder_size

	if has_node("MeshInstance3D"):
		var mesh_node: MeshInstance3D = get_node("MeshInstance3D") as MeshInstance3D
		if is_instance_valid(mesh_node) and mesh_node.mesh is BoxMesh:
			if Engine.is_editor_hint() and not mesh_node.mesh.resource_local_to_scene:
				mesh_node.mesh = mesh_node.mesh.duplicate()
			(mesh_node.mesh as BoxMesh).size = ladder_size


## Triggers climbing entry routine on bodies exposing the ladder interaction API.
## [param body] The physics body entering the trigger bounds.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.has_method("enter_ladder"):
		print("LadderArea: '", body.name, "' has entered the ladder trigger.")
		body.call("enter_ladder", self)


## Disengages climbing routine when a body steps outside trigger bounds.
## [param body] The physics body exiting the trigger bounds.
func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.has_method("exit_ladder"):
		print("LadderArea: '", body.name, "' has exited the ladder trigger.")
		body.call("exit_ladder", self)
