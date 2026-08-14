@tool
## A utility component that constructs a straight 3D cable connecting two points.
##
## Automatically updates a mesh and collision shape to stretch between the endpoints
## of a provided [Path3D] curve. Only the first and last points of the curve are used.
class_name CableBuilderComponent
extends Node

## The curve defining the start and end points of the cable.
@export var path_node: Path3D
## The cylindrical mesh representing the visual cable.
@export var mesh_node: MeshInstance3D
## The collision shape matching the physical presence of the cable.
@export var collision_node: CollisionShape3D


## Duplicates mesh and collision resources to ensure modifications are isolated per instance.
func _ready() -> void:
	# Make the shapes unique so multiple ropes don't break each other
	if mesh_node and mesh_node.mesh:
		mesh_node.mesh = mesh_node.mesh.duplicate()
	if collision_node and collision_node.shape:
		collision_node.shape = collision_node.shape.duplicate()

	build_cable()


## Updates the cable geometry while running in the editor to provide real-time feedback.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		build_cable()


## Recalculates and applies the position, rotation, and height of the mesh and collision shapes.
func build_cable() -> void:
	if not path_node or not path_node.curve or path_node.curve.get_point_count() < 2:
		return
	if not mesh_node or not collision_node:
		return

	# The foolproof 2-point lock
	while path_node.curve.get_point_count() > 2:
		path_node.curve.remove_point(path_node.curve.get_point_count() - 1)

	# Math & World Space Conversion
	var start_pos: Vector3 = path_node.to_global(path_node.curve.get_point_position(0))
	var end_pos: Vector3 = path_node.to_global(
		path_node.curve.get_point_position(path_node.curve.get_point_count() - 1)
	)

	var distance: float = start_pos.distance_to(end_pos)
	var center: Vector3 = start_pos.lerp(end_pos, 0.5)
	var direction: Vector3 = (end_pos - start_pos).normalized()

	# Size
	if mesh_node.mesh:
		mesh_node.mesh.height = distance
	if collision_node.shape:
		collision_node.shape.height = distance

	# Position & Rotation
	mesh_node.global_position = center
	var up_vector: Vector3 = Vector3.UP
	if abs(direction.y) > 0.99:
		up_vector = Vector3.RIGHT

	mesh_node.look_at(end_pos, up_vector)
	mesh_node.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	collision_node.global_transform = mesh_node.global_transform
