extends MainLoop


func _process(_delta: float) -> bool:
	print("--- GOTHIC ARCH TEST READY ---")
	var tscn: PackedScene = (
		ResourceLoader.load("res://props/gothic_arch/gothic_arch.tscn") as PackedScene
	)
	assert(tscn != null)
	var inst: Node = tscn.instantiate()
	assert(inst != null)

	var mesh_inst: MeshInstance3D = inst.get_node("ArchMesh") as MeshInstance3D
	assert(mesh_inst != null)
	print("Instantiated GothicArch successfully. Tris: ", mesh_inst.mesh.get_faces().size() / 3)

	var mat: ShaderMaterial = mesh_inst.material_override as ShaderMaterial
	assert(mat != null)
	print("Material shader: ", mat.shader.resource_path)

	var albedo: Texture2D = mat.get_shader_parameter(&"albedo_texture") as Texture2D
	var orm: Texture2D = mat.get_shader_parameter(&"orm_texture") as Texture2D
	var normal: Texture2D = mat.get_shader_parameter(&"normal_texture") as Texture2D
	print("Textures: albedo=", albedo != null, " orm=", orm != null, " normal=", normal != null)
	assert(albedo != null and orm != null and normal != null)

	var left_col: CollisionShape3D = inst.get_node("LeftPillarCol") as CollisionShape3D
	var right_col: CollisionShape3D = inst.get_node("RightPillarCol") as CollisionShape3D
	var top_col: CollisionShape3D = inst.get_node("TopLintelCol") as CollisionShape3D
	assert(left_col != null and right_col != null and top_col != null)
	print("Colliders verified.")

	inst.free()
	print("--- GOTHIC ARCH PASSED ---")
	return true
