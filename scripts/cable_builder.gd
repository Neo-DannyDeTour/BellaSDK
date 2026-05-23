@tool
extends Node
class_name CableBuilder_Component

@export var path_node: Path3D
@export var mesh_node: MeshInstance3D
@export var collision_node: CollisionShape3D


func _ready() -> void:
	# Make the shapes unique so multiple ropes don't break each other
	if mesh_node and mesh_node.mesh:
		mesh_node.mesh = mesh_node.mesh.duplicate()
	if collision_node and collision_node.shape:
		collision_node.shape = collision_node.shape.duplicate()

	build_cable()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		build_cable()


func build_cable() -> void:
	if not path_node or not path_node.curve or path_node.curve.get_point_count() < 2:
		return
	if not mesh_node or not collision_node:
		return

	# The foolproof 2-point lock
	while path_node.curve.get_point_count() > 2:
		path_node.curve.remove_point(path_node.curve.get_point_count() - 1)

	# Math & World Space Conversion
	var start_pos := path_node.to_global(path_node.curve.get_point_position(0))
	var end_pos := path_node.to_global(path_node.curve.get_point_position(path_node.curve.get_point_count() - 1))

	var distance := start_pos.distance_to(end_pos)
	var center := start_pos.lerp(end_pos, 0.5)
	var direction := (end_pos - start_pos).normalized()

	# Size
	if mesh_node.mesh:
		mesh_node.mesh.height = distance
	if collision_node.shape:
		collision_node.shape.height = distance

	# Position & Rotation
	mesh_node.global_position = center
	var up_vector := Vector3.UP
	if abs(direction.y) > 0.99:
		up_vector = Vector3.RIGHT

	mesh_node.look_at(end_pos, up_vector)
	mesh_node.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	collision_node.global_transform = mesh_node.global_transform
