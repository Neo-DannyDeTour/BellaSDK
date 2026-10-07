@tool
## Physics trigger volume attaching the [Player] to ladder climbing locomotion.
class_name Ladder
extends Area3D

## Physical dimensions of the ladder interaction box and visual bounds.
@export var ladder_size: Vector3 = Vector3(2.2, 5.0, 0.5):
	set(value):
		ladder_size = value
		if is_inside_tree():
			_update_visuals()

## Editor-only mesh indicating the mountable face of the ladder.
@onready var arrow: MeshInstance3D = (
	get_node_or_null("Arrow") if get_node_or_null("Arrow") is MeshInstance3D else null
)


## Initializes collision signals, runtime visibility, and visual box sizing.
func _ready() -> void:
	print("Ladder: Initializing ladder trigger at: ", global_position)
	_update_visuals()

	if not Engine.is_editor_hint():
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)
		if not body_exited.is_connected(_on_body_exited):
			body_exited.connect(_on_body_exited)

		if is_instance_valid(arrow):
			arrow.hide()
		if has_node("MeshInstance3D"):
			var mesh_node: Node3D = (
				get_node("MeshInstance3D") if get_node("MeshInstance3D") is Node3D else null
			)
			if is_instance_valid(mesh_node):
				mesh_node.hide()


## Resizes the collision box and editor debug mesh to match inspector bounds.
func _update_visuals() -> void:
	print("Ladder: Updating visuals and collision shapes to size: ", ladder_size)
	if has_node("CollisionShape3D"):
		var col_node: CollisionShape3D = (
			get_node("CollisionShape3D")
			if get_node("CollisionShape3D") is CollisionShape3D
			else null
		)
		if is_instance_valid(col_node) and col_node.shape is BoxShape3D:
			if Engine.is_editor_hint() and not col_node.shape.resource_local_to_scene:
				col_node.shape = col_node.shape.duplicate()
			(col_node.shape as BoxShape3D).size = ladder_size

	if has_node("MeshInstance3D"):
		var mesh_node: MeshInstance3D = (
			get_node("MeshInstance3D") if get_node("MeshInstance3D") is MeshInstance3D else null
		)
		if is_instance_valid(mesh_node) and mesh_node.mesh is BoxMesh:
			if Engine.is_editor_hint() and not mesh_node.mesh.resource_local_to_scene:
				mesh_node.mesh = mesh_node.mesh.duplicate()
			(mesh_node.mesh as BoxMesh).size = ladder_size


## Handles body entry, logging detection and calling [method Player.enter_ladder].
## [param body] The physics body entering the trigger bounds.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	print("LadderArea: Physics body entered trigger: '", body.name, "'")

	if body.has_method("enter_ladder"):
		print("LadderArea: '", body.name, "' has entered the ladder trigger.")
		body.call("enter_ladder", self)


## Disengages climbing routine when a body steps outside trigger bounds.
## [param body] The physics body exiting the trigger bounds.
func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	print("LadderArea: Physics body exited trigger: '", body.name, "'")

	if body.has_method("exit_ladder"):
		print("LadderArea: '", body.name, "' has exited the ladder trigger.")
		body.call("exit_ladder", self)
