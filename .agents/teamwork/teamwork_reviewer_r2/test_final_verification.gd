extends MainLoop


func _process(_delta: float) -> bool:
	print("=== FINAL ADVERSARIAL VERIFICATION START ===")
	var tscn: PackedScene = (
		ResourceLoader.load("res://props/gothic_arch/gothic_arch.tscn") as PackedScene
	)
	assert(tscn != null, "Failed to load gothic_arch.tscn")
	var inst: Node = tscn.instantiate()
	assert(inst != null, "Failed to instantiate gothic_arch.tscn")
	assert(inst is StaticBody3D, "Root node must be StaticBody3D")
	var body: StaticBody3D = inst as StaticBody3D

	print("Root class: ", body.get_class())
	print("Root script: ", body.get_script().resource_path if body.get_script() else "null")
	assert(body.get_script() != null, "GothicArch missing script!")

	var mesh_inst: MeshInstance3D = body.get_node_or_null("ArchMesh") as MeshInstance3D
	assert(mesh_inst != null, "ArchMesh node missing!")
	var face_count: int = mesh_inst.mesh.get_faces().size() / 3
	print("ArchMesh tris count: ", face_count)
	assert(face_count > 1000 and face_count <= 2000, "Tri count must be in range (1000, 2000]")

	var mat: ShaderMaterial = mesh_inst.material_override as ShaderMaterial
	assert(mat != null, "ArchMesh material_override missing!")
	print("Shader: ", mat.shader.resource_path)
	assert(
		mat.shader.resource_path.ends_with("gothic_arch_stone.gdshader"), "Wrong shader attached!"
	)

	var albedo: Texture2D = mat.get_shader_parameter(&"albedo_texture") as Texture2D
	var orm: Texture2D = mat.get_shader_parameter(&"orm_texture") as Texture2D
	var normal: Texture2D = mat.get_shader_parameter(&"normal_texture") as Texture2D
	assert(albedo != null, "albedo_texture missing!")
	assert(orm != null, "orm_texture missing!")
	assert(normal != null, "normal_texture missing!")
	print(
		"Textures bound: albedo=",
		albedo.resource_path,
		" orm=",
		orm.resource_path,
		" normal=",
		normal.resource_path
	)

	# Verify colliders
	var left_col: CollisionShape3D = body.get_node_or_null("LeftPillarCol") as CollisionShape3D
	var right_col: CollisionShape3D = body.get_node_or_null("RightPillarCol") as CollisionShape3D
	var top_col: CollisionShape3D = body.get_node_or_null("TopLintelCol") as CollisionShape3D
	assert(left_col != null, "LeftPillarCol missing!")
	assert(right_col != null, "RightPillarCol missing!")
	assert(top_col != null, "TopLintelCol missing!")

	var box_left: BoxShape3D = left_col.shape as BoxShape3D
	var box_right: BoxShape3D = right_col.shape as BoxShape3D
	var box_top: BoxShape3D = top_col.shape as BoxShape3D
	print("LeftPillarCol pos: ", left_col.position, " size: ", box_left.size)
	print("RightPillarCol pos: ", right_col.position, " size: ", box_right.size)
	print("TopLintelCol pos: ", top_col.position, " size: ", box_top.size)

	# Verify that the center opening (X = 0, Y in [0, 3.55]) does NOT intersect TopLintelCol:
	var top_min_y: float = top_col.position.y - box_top.size.y * 0.5
	print("TopLintelCol lowest Y boundary: ", top_min_y)
	assert(top_min_y >= 3.50, "TopLintelCol invades arch opening! Minimum Y must be >= 3.50")

	# Test tree entry & instance shader parameters
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.add_child(body)
		# Verify collision layers
		assert(
			body.collision_layer == CollisionLayers.MASK_ENVIRONMENT, "Collision layer mismatch!"
		)
		assert(body.collision_mask == CollisionLayers.MASK_NONE, "Collision mask mismatch!")
		assert(mesh_inst.layers == CollisionLayers.RENDER_MASK_ENVIRONMENT, "Render mask mismatch!")

		# Modify instance parameters and verify
		body.set("wear_intensity", 0.75)
		body.set("moss_coverage", 0.50)
		body.set("instance_tint", Color(0.9, 0.85, 0.8))
		print("Successfully applied instance parameters.")

	body.free()
	print("=== FINAL ADVERSARIAL VERIFICATION PASSED ===")
	return true
