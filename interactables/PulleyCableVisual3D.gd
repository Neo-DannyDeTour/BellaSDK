@tool
class_name PulleyCableVisual3D
extends Node3D

@export_category("Connections")
## The fixed point above the cart (e.g., the pulley wheel)
@export var overhead_anchor: Node3D
@export var cart: Node3D

@export_category("Visuals")
## A MeshInstance3D containing a standard CylinderMesh
@export var cable_mesh: MeshInstance3D


func _ready() -> void:
	if not Engine.is_editor_hint():
		print("PulleyCableVisual3D: Initializing optimized straight cable.")

	if not is_instance_valid(cable_mesh):
		printerr("PulleyCableVisual3D: Error - Missing cable_mesh instance!")


func _process(_delta: float) -> void:
	if (
		is_instance_valid(overhead_anchor)
		and is_instance_valid(cart)
		and is_instance_valid(cable_mesh)
	):
		_stretch_cable_to_fit()


func _stretch_cable_to_fit() -> void:
	var top_pos: Vector3 = overhead_anchor.global_position
	var bottom_pos: Vector3 = cart.global_position
	var distance: float = top_pos.distance_to(bottom_pos)

	# 1. Position the center of the cylinder perfectly between the anchor and cart
	cable_mesh.global_position = top_pos.lerp(bottom_pos, 0.5)

	# Prevent math errors if the nodes are exactly on top of each other
	if distance > 0.001 and not top_pos.is_equal_approx(bottom_pos):
		# 2. Point the node toward the cart
		var up_vector: Vector3 = Vector3.UP

		# If the cable is pointing perfectly straight up or down, the standard UP vector
		# causes a cross-product error in look_at(). We switch to RIGHT to fix this.
		if abs(top_pos.direction_to(bottom_pos).y) > 0.999:
			up_vector = Vector3.RIGHT

		cable_mesh.look_at(bottom_pos, up_vector)

		# A standard CylinderMesh extends along the Y-axis.
		# look_at() aligns the -Z axis, so we rotate 90 degrees to snap it into place.
		cable_mesh.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	# 3. Scale the cylinder to match the exact distance.
	# A default CylinderMesh is exactly 2.0 meters tall, so we divide the distance by 2.0.
	cable_mesh.scale = Vector3(1.0, distance / 2.0, 1.0)
