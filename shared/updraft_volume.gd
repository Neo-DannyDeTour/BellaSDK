## Area3D volume that applies an upward lift force to entities passing through.
class_name UpdraftVolume
extends Area3D

## The vertical force applied to entities entering the updraft.
@export var lift_strength: float = 12.0


## Initializes the node by hiding the debug mesh on ready.
func _ready() -> void:
	print("UpdraftVolume: Initializing on: ", name)
	var debug_mesh: Node3D = get_node_or_null("MeshInstance3D") as Node3D
	if is_instance_valid(debug_mesh):
		debug_mesh.hide()


## Detects entering bodies and triggers their [method enter_updraft].
func _on_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body):
		return

	if body.has_method("enter_updraft"):
		print("UpdraftVolume: Entity entered updraft: ", body.name)
		var top_height: float = global_position.y

		for child: Node in get_children():
			if child is CollisionShape3D:
				var col_shape: CollisionShape3D = child as CollisionShape3D
				if not is_instance_valid(col_shape.shape):
					continue

				if col_shape.shape is BoxShape3D:
					var box: BoxShape3D = col_shape.shape as BoxShape3D
					top_height = col_shape.global_position.y + (box.size.y * 0.5)
					break
				elif col_shape.shape is CylinderShape3D:
					var cyl: CylinderShape3D = col_shape.shape as CylinderShape3D
					top_height = col_shape.global_position.y + (cyl.height * 0.5)
					break

		body.call("enter_updraft", lift_strength, top_height)


## Detects exiting bodies and triggers their [method exit_updraft].
func _on_body_exited(body: Node3D) -> void:
	if not is_instance_valid(body):
		return

	if body.has_method("exit_updraft"):
		print("UpdraftVolume: Entity exited updraft: ", body.name)
		body.call("exit_updraft")
