@tool
# class_name GothicArchPostImport
extends EditorScenePostImport

## Post-import harness for gothic_arch.glb: builds StaticBody3D root, 3x BoxShape3D
## colliders, shared ShaderMaterial (.tres), and binds gothic_arch_prop.gd.

## Filename for the custom Gothic stone spatial shader.
const SHADER_FILE: String = "gothic_arch_stone.gdshader"

## Filename for the runtime instance controller script.
const PROP_SCRIPT_FILE: String = "gothic_arch_prop.gd"

## Filename for the shared shader material resource.
const MAT_FILE: String = "gothic_arch_mat.tres"

## Filename for the baked albedo texture map.
const ALBEDO_FILE: String = "arch_albedo.png"

## Filename for the baked ORM packed texture map.
const ORM_FILE: String = "arch_orm.png"

## Filename for the baked OpenGL normal texture map.
const NORMAL_FILE: String = "arch_normal.png"

## Texture uniform parameter name for Albedo.
const PARAM_ALBEDO: StringName = &"albedo_texture"

## Texture uniform parameter name for ORM.
const PARAM_ORM: StringName = &"orm_texture"

## Texture uniform parameter name for Normal.
const PARAM_NORMAL: StringName = &"normal_texture"

## Property name for the arch mesh reference on the instance controller.
const PROP_ARCH_MESH: StringName = &"arch_mesh"

## Box collider dimensions for the left and right arch pillars.
const PILLAR_SIZE: Vector3 = Vector3(0.6, 3.55, 0.8)

## Box collider center position for the left arch pillar.
const LEFT_PILLAR_POS: Vector3 = Vector3(-1.2, 1.775, 0.0)

## Box collider center position for the right arch pillar.
const RIGHT_PILLAR_POS: Vector3 = Vector3(1.2, 1.775, 0.0)

## Box collider dimensions for the top arch lintel.
const LINTEL_SIZE: Vector3 = Vector3(3.0, 0.45, 0.8)

## Box collider center position for the top arch lintel.
const LINTEL_POS: Vector3 = Vector3(0.0, 3.775, 0.0)


## Intercepts imported GLB scene, replaces root with [StaticBody3D], and binds assets.
func _post_import(scene: Node) -> Object:
	var base_dir: String = get_source_file().get_base_dir()
	var found_mesh: MeshInstance3D = _find_mesh_instance(scene)
	assert(found_mesh != null, "GothicArchPostImport: ArchMesh not found in GLB.")

	var static_root: StaticBody3D = StaticBody3D.new()
	static_root.name = "GothicArch"
	static_root.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	static_root.collision_mask = CollisionLayers.MASK_NONE

	if found_mesh.get_parent() != null:
		found_mesh.owner = null
		found_mesh.get_parent().remove_child(found_mesh)
	static_root.add_child(found_mesh)
	found_mesh.name = "ArchMesh"
	found_mesh.owner = static_root
	found_mesh.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	found_mesh.material_override = _get_or_create_material(base_dir)

	_add_box_collider(static_root, "LeftPillarCol", PILLAR_SIZE, LEFT_PILLAR_POS)
	_add_box_collider(static_root, "RightPillarCol", PILLAR_SIZE, RIGHT_PILLAR_POS)
	_add_box_collider(static_root, "TopLintelCol", LINTEL_SIZE, LINTEL_POS)

	var prop_script_path: String = base_dir.path_join(PROP_SCRIPT_FILE)
	if ResourceLoader.exists(prop_script_path):
		# shortcut: editor-time ResourceLoader for dynamic sibling path, preload not valid
		var prop_script: Script = ResourceLoader.load(prop_script_path) as Script
		if prop_script != null:
			static_root.set_script(prop_script)
			static_root.set(PROP_ARCH_MESH, found_mesh)

	scene.free()
	print("[GothicArchPostImport] Configured GothicArch StaticBody3D and 3x BoxShape3D.")
	return static_root


## Recursively locates the first [MeshInstance3D] inside the imported [param node] tree.
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var result: MeshInstance3D = _find_mesh_instance(child)
		if result != null:
			return result
	return null


## Loads or builds a shared [ShaderMaterial] saved at [param base_dir] to prevent duplicates.
func _get_or_create_material(base_dir: String) -> ShaderMaterial:
	var mat_path: String = base_dir.path_join(MAT_FILE)
	var mat: ShaderMaterial = null
	if ResourceLoader.exists(mat_path):
		mat = ResourceLoader.load(mat_path) as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()

	var shader_path: String = base_dir.path_join(SHADER_FILE)
	if ResourceLoader.exists(shader_path):
		var shader: Shader = ResourceLoader.load(shader_path) as Shader
		mat.shader = shader

	_bind_texture_param(mat, PARAM_ALBEDO, base_dir.path_join(ALBEDO_FILE))
	_bind_texture_param(mat, PARAM_ORM, base_dir.path_join(ORM_FILE))
	_bind_texture_param(mat, PARAM_NORMAL, base_dir.path_join(NORMAL_FILE))

	ResourceSaver.save(mat, mat_path)
	return mat


## Assigns a [Texture2D] at [param tex_path] to [param param_name] on [param mat].
func _bind_texture_param(mat: ShaderMaterial, param_name: StringName, tex_path: String) -> void:
	if ResourceLoader.exists(tex_path):
		var tex: Texture2D = ResourceLoader.load(tex_path) as Texture2D
		if tex != null:
			mat.set_shader_parameter(param_name, tex)


## Creates a [CollisionShape3D] with a [BoxShape3D] and binds owner to [param root].
func _add_box_collider(
	root: StaticBody3D, col_name: String, box_size: Vector3, box_pos: Vector3
) -> void:
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = col_name
	var box: BoxShape3D = BoxShape3D.new()
	box.size = box_size
	col.shape = box
	col.position = box_pos
	root.add_child(col)
	col.owner = root
