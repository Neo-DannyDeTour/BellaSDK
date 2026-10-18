@tool
## Generates a cylindrical cable mesh and collision along a 2-point [Path3D].
class_name UniversalCable3D
extends Path3D


## Initializes default curve points, duplicates resource, and hooks updates.
func _ready() -> void:
	if not curve:
		curve = Curve3D.new()
		curve.add_point(Vector3.ZERO)
		curve.add_point(Vector3(0.0, -3.0, 0.0))

	curve = curve.duplicate()

	if not curve.changed.is_connected(_update_cable):
		curve.changed.connect(_update_cable)

	_update_cable()


## Recomputes transform and dimensions for child mesh and collision shape.
func _update_cable() -> void:
	if not curve or curve.get_point_count() < 2:
		return

	while curve.get_point_count() > 2:
		curve.remove_point(curve.get_point_count() - 1)

	var mesh_node: MeshInstance3D = _find_mesh_instance(self)
	var col_node: CollisionShape3D = _find_collision_shape(self)

	var global_start: Vector3 = to_global(curve.get_point_position(0))
	var global_end: Vector3 = to_global(curve.get_point_position(1))

	var distance: float = global_start.distance_to(global_end)
	var span_xform: Transform3D = MathUtils.calculate_cylinder_span_transform(
		global_start, global_end
	)

	if mesh_node:
		var cyl_mesh: CylinderMesh = mesh_node.mesh as CylinderMesh
		if not cyl_mesh:
			cyl_mesh = CylinderMesh.new()
			mesh_node.mesh = cyl_mesh

		cyl_mesh.height = distance
		cyl_mesh.top_radius = 0.05
		cyl_mesh.bottom_radius = 0.05
		mesh_node.global_transform = span_xform

	if col_node:
		var cyl_shape: CylinderShape3D = col_node.shape as CylinderShape3D
		if not cyl_shape:
			cyl_shape = CylinderShape3D.new()
			col_node.shape = cyl_shape

		cyl_shape.height = distance
		cyl_shape.radius = 0.05
		col_node.global_transform = span_xform


## Traverses descendants recursively to locate the first [MeshInstance3D].
func _find_mesh_instance(parent: Node) -> MeshInstance3D:
	return NodeQuery.find_first_child_of_type(parent, MeshInstance3D) as MeshInstance3D


## Traverses descendants recursively to locate the first [CollisionShape3D].
func _find_collision_shape(parent: Node) -> CollisionShape3D:
	return NodeQuery.find_first_child_of_type(parent, CollisionShape3D) as CollisionShape3D
