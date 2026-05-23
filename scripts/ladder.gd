@tool
extends Area3D

@onready var arrow: MeshInstance3D = $Arrow

# Updated the default Vector3 to have 0.01 on the Z-axis
@export var ladder_size: Vector3 = Vector3(2.2, 5.0, 0.5):
	set(value):
		ladder_size = value
		_update_visuals()


func _update_visuals() -> void:
	# Update the collision box size safely
	if has_node("CollisionShape3D"):
		var col_shape: Shape3D = $CollisionShape3D.shape
		if col_shape is BoxShape3D:
			col_shape.size = ladder_size

	# Update the mesh block size safely
	if has_node("MeshInstance3D"):
		var mesh_shape: Mesh = $MeshInstance3D.mesh
		if mesh_shape is BoxMesh:
			mesh_shape.size = ladder_size


func _ready() -> void:
	# Engine.is_editor_hint() checks if we are playing the game, or just viewing the editor
	if Engine.is_editor_hint():
		# We are in the editor. Apply the sizes.
		_update_visuals()
	else:
		arrow.hide()
		# We are actually playing the game. Hide the mesh as usual.
		if has_node("MeshInstance3D"):
			$MeshInstance3D.hide()


func _on_body_entered(body: Node3D) -> void:
	# Ignore collisions while we are just editing the level
	if Engine.is_editor_hint():
		return

	if body.has_method("enter_ladder"):
		body.enter_ladder(self)


func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.has_method("exit_ladder"):
		body.exit_ladder(self)
