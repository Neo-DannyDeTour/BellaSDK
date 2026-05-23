extends SoftBody3D

@export var bake_action_key := KEY_SPACE
@export var save_path := "res://baked_red_cloth.res"


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == bake_action_key:
			_bake_cloth()


func _bake_cloth() -> void:
	print("Baking cloth simulation...")
	var base_mesh := mesh
	if not base_mesh:
		printerr("No mesh assigned to SoftBody3D!")
		return

	var arrays := base_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

	# Retrieve deformed vertices directly from the physics server
	var phys_rid := get_physics_rid()

	for i in range(verts.size()):
		var global_pos := PhysicsServer3D.soft_body_get_point_global_position(phys_rid, i)
		verts[i] = to_local(global_pos)

	arrays[Mesh.ARRAY_VERTEX] = verts

	# Strip old normals/tangents so SurfaceTool can cleanly regenerate them for the new folds
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null

	var temp_mesh := ArrayMesh.new()
	temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var st := SurfaceTool.new()
	st.create_from(temp_mesh, 0)
	st.generate_normals()
	st.generate_tangents()

	var baked_mesh := st.commit()

	var err := ResourceSaver.save(baked_mesh, save_path)
	if err == OK:
		print("Successfully baked to: ", save_path)
	else:
		printerr("Failed to save mesh. Error code: ", err)
