## A specialized [SoftBody3D] utility that bakes its current simulation state into a static mesh.
##
## Captures the deformed vertices from the physics server and generates a new [ArrayMesh]
## saved to the specified file path, useful for creating static draped cloth props.
class_name ClothBaker
extends SoftBody3D

## The physical keyboard key used to trigger the cloth bake.
@export var bake_action_key: int = KEY_SPACE
## The file path where the baked cloth mesh will be saved.
@export var save_path: String = "res://baked_red_cloth.res"


## Listens for the assigned bake action key to trigger the mesh baking process.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == bake_action_key:
			_bake_cloth()


## Extracts deformed vertices from the physics server and generates a new [ArrayMesh].
func _bake_cloth() -> void:
	print("Baking cloth simulation...")
	var base_mesh: ArrayMesh = mesh as ArrayMesh
	if not base_mesh:
		printerr("No mesh assigned to SoftBody3D or not ArrayMesh!")
		return

	var arrays: Array = base_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

	# Retrieve deformed vertices directly from the physics server
	var phys_rid: RID = get_physics_rid()

	for i: int in range(verts.size()):
		var global_pos: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(phys_rid, i)
		verts[i] = to_local(global_pos)

	arrays[Mesh.ARRAY_VERTEX] = verts

	# Strip old normals/tangents so SurfaceTool can cleanly regenerate them for the new folds
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null

	var temp_mesh: ArrayMesh = ArrayMesh.new()
	temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var st: SurfaceTool = SurfaceTool.new()
	st.create_from(temp_mesh, 0)
	st.generate_normals()
	st.generate_tangents()

	var baked_mesh: ArrayMesh = st.commit()

	var err: Error = ResourceSaver.save(baked_mesh, save_path)
	if err == OK:
		print("Successfully baked to: ", save_path)
	else:
		printerr("Failed to save mesh. Error code: ", err)
