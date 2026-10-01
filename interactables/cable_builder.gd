@tool
## Constructs a straight 3D cable between the endpoints of a [Path3D] curve.
class_name CableBuilderComponent
extends Node

## Curve defining the start and end points of the cable.
@export var path_node: Path3D

## Cylindrical mesh instance representing the visual cable.
@export var mesh_node: MeshInstance3D

## Collision shape matching the physical volume of the cable.
@export var collision_node: CollisionShape3D


## Initializes unique mesh and collision resources and builds cable.
func _ready() -> void:
	print("CableBuilderComponent: Initializing cable geometry on: ", name)
	if is_instance_valid(mesh_node) and mesh_node.mesh != null:
		if not mesh_node.mesh.resource_local_to_scene:
			mesh_node.mesh = mesh_node.mesh.duplicate()
			mesh_node.mesh.resource_local_to_scene = true
	if is_instance_valid(collision_node) and collision_node.shape != null:
		if not collision_node.shape.resource_local_to_scene:
			collision_node.shape = collision_node.shape.duplicate()
			collision_node.shape.resource_local_to_scene = true
	build_cable()


## Rebuilds cable geometry in editor when modified.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		build_cable()


## Computes cable transform, height, and collision to bridge endpoints.
func build_cable() -> void:
	print("CableBuilderComponent: build_cable() recalculating geometry.")
	if not is_instance_valid(path_node) or path_node.curve == null:
		return
	if path_node.curve.get_point_count() < 2:
		return
	if not is_instance_valid(mesh_node) or not is_instance_valid(collision_node):
		return

	while path_node.curve.get_point_count() > 2:
		path_node.curve.remove_point(path_node.curve.get_point_count() - 1)

	var start_pos: Vector3 = path_node.to_global(path_node.curve.get_point_position(0))
	var end_idx: int = path_node.curve.get_point_count() - 1
	var end_pos: Vector3 = path_node.to_global(path_node.curve.get_point_position(end_idx))

	var distance: float = start_pos.distance_to(end_pos)
	var center: Vector3 = MathUtils.get_midpoint(start_pos, end_pos)
	var direction: Vector3 = (end_pos - start_pos).normalized()

	if mesh_node.mesh is CylinderMesh:
		(mesh_node.mesh as CylinderMesh).height = distance
	elif mesh_node.mesh != null and &"height" in mesh_node.mesh:
		mesh_node.mesh.set(&"height", distance)

	if collision_node.shape is CylinderShape3D:
		(collision_node.shape as CylinderShape3D).height = distance
	elif collision_node.shape != null and &"height" in collision_node.shape:
		collision_node.shape.set(&"height", distance)

	mesh_node.global_position = center
	var up_vector: Vector3 = Vector3.UP
	if absf(direction.y) > 0.99:
		up_vector = Vector3.RIGHT

	mesh_node.look_at(end_pos, up_vector)
	mesh_node.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	collision_node.global_transform = mesh_node.global_transform
