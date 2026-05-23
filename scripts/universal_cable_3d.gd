@tool
extends Path3D
class_name UniversalCable3D  # <-- This puts it in your "Add Node" menu!


func _ready() -> void:
	if not curve:
		curve = Curve3D.new()
		curve.add_point(Vector3.ZERO)
		curve.add_point(Vector3(0, -3.0, 0))

	# --- NEW: THE RESOURCE DECOUPLER ---
	# Forces Godot to make this curve completely unique so ropes don't share dots!
	curve = curve.duplicate()

	# Hook directly into Godot's curve editor
	if not curve.changed.is_connected(_update_cable):
		curve.changed.connect(_update_cable)

	_update_cable()


func _update_cable() -> void:
	if not curve or curve.get_point_count() < 2:
		return

	# 1. The Foolproof 2-Point Lock
	while curve.get_point_count() > 2:
		curve.remove_point(curve.get_point_count() - 1)

	# 2. AUTO-FINDER: Automatically searches its children for a Mesh and Collision!
	var mesh_node := _get_first_node_of_type(self, "MeshInstance3D")
	var col_node := _get_first_node_of_type(self, "CollisionShape3D")

	# 3. Math (Global space ensures it works perfectly no matter how you arrange the child nodes)
	var global_start := to_global(curve.get_point_position(0))
	var global_end := to_global(curve.get_point_position(1))

	var distance := global_start.distance_to(global_end)
	var global_center := global_start.lerp(global_end, 0.5)
	var direction := (global_end - global_start).normalized()

	var up_vector := Vector3.UP
	if abs(direction.y) > 0.99:
		up_vector = Vector3.RIGHT

	# 4. Shape the Mesh
	if mesh_node:
		if not mesh_node.mesh is CylinderMesh:
			mesh_node.mesh = CylinderMesh.new()
		mesh_node.mesh.height = distance
		mesh_node.mesh.top_radius = 0.05  # Rope thickness
		mesh_node.mesh.bottom_radius = 0.05

		mesh_node.global_position = global_center
		mesh_node.look_at(global_end, up_vector)
		mesh_node.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	# 5. Shape the Collision to match exactly
	if col_node:
		if not col_node.shape is CylinderShape3D:
			col_node.shape = CylinderShape3D.new()
		col_node.shape.height = distance
		col_node.shape.radius = 0.05

		if mesh_node:
			col_node.global_transform = mesh_node.global_transform


# The Secret Sauce: Recursively digs through children to find what it needs
func _get_first_node_of_type(parent: Node, type_name: String) -> Node:
	for child in parent.get_children():
		if child.is_class(type_name):
			return child
		var found := _get_first_node_of_type(child, type_name)
		if found:
			return found
	return null
