@tool
class_name GenerateTestChunks
extends EditorScript
## Editor utility generating 25 test chunk scenes and a shared per-instance tint shader.

## Target directory for generated chunk scenes and shared test resources.
const CHUNK_DIR: String = "res://world/chunks"

## File path for the generated instance-uniform tint shader.
const SHADER_PATH: String = "res://world/chunks/test_chunk_tint.gdshader"

## File path for the shared [ShaderMaterial] assigned to all test geometry.
const MATERIAL_PATH: String = "res://world/chunks/test_chunk_tint_mat.tres"

## Format string for generated chunk scene file paths.
const CHUNK_PATH_FMT: String = "res://world/chunks/chunk_%d_%d.tscn"

## Preloaded [ChunkRoot] script attached to each generated chunk root node.
const CHUNK_ROOT_SCRIPT: Script = preload("res://world/chunk_root.gd")

## Half-extent of the generated test grid (-2 to +2 on X and Z axes = 25 chunks).
const GRID_EXTENT: int = 2

## Per-instance shader uniform key controlling albedo tint color.
const PARAM_TINT: StringName = &"tint_color"

## Group assigned to destructible static test crates.
const GROUP_CRATE: StringName = &"test_crate"

## Group assigned to persistent roaming test entities.
const GROUP_ROAMING: StringName = &"roaming"

## Instance tint color applied to destructible test crates.
const COLOR_CRATE: Color = Color(0.95, 0.65, 0.15)

## Instance tint color applied to roaming test entities.
const COLOR_ROAMER: Color = Color(0.95, 0.2, 0.3)

## Shader source code using an instance uniform to avoid material duplication.
const SHADER_CODE: String = """shader_type spatial;
instance uniform vec3 tint_color : source_color = vec3(1.0);
void fragment() {
	ALBEDO = tint_color;
	ROUGHNESS = 0.85;
}
"""


## Entry point executed via File -> Run in the Godot Editor.
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(CHUNK_DIR)
	var shared_mat: ShaderMaterial = _create_shared_material()

	var slab_mesh: BoxMesh = BoxMesh.new()
	slab_mesh.size = Vector3(246.0, 0.5, 246.0)

	var crate_mesh: BoxMesh = BoxMesh.new()
	crate_mesh.size = Vector3(2.0, 2.0, 2.0)
	var crate_shape: BoxShape3D = BoxShape3D.new()
	crate_shape.size = Vector3(2.0, 2.0, 2.0)

	var roamer_mesh: CapsuleMesh = CapsuleMesh.new()
	roamer_mesh.radius = 0.6
	roamer_mesh.height = 2.0
	var roamer_shape: CapsuleShape3D = CapsuleShape3D.new()
	roamer_shape.radius = 0.6
	roamer_shape.height = 2.0

	var count: int = 0
	for x: int in range(-GRID_EXTENT, GRID_EXTENT + 1):
		for z: int in range(-GRID_EXTENT, GRID_EXTENT + 1):
			_build_chunk_scene(
				Vector2i(x, z),
				shared_mat,
				slab_mesh,
				crate_mesh,
				crate_shape,
				roamer_mesh,
				roamer_shape
			)
			count += 1

	print("Generated ", count, " test chunk scenes in ", CHUNK_DIR)


## Creates and saves the shared [Shader] and [ShaderMaterial] on disk.
func _create_shared_material() -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = SHADER_CODE
	ResourceSaver.save(shader, SHADER_PATH)

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	ResourceSaver.save(mat, MATERIAL_PATH)
	return mat


## Constructs, packs, and saves a single test chunk scene for [param coord].
func _build_chunk_scene(
	coord: Vector2i,
	mat: ShaderMaterial,
	slab_mesh: BoxMesh,
	crate_mesh: BoxMesh,
	crate_shape: BoxShape3D,
	roamer_mesh: CapsuleMesh,
	roamer_shape: CapsuleShape3D
) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	root.set_script(CHUNK_ROOT_SCRIPT)

	var border: MeshInstance3D = MeshInstance3D.new()
	border.name = "BorderMarker"
	border.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	border.mesh = slab_mesh
	border.material_override = mat
	border.position = Vector3(125.0, 0.25, 125.0)
	var hue: float = fposmod(float(coord.x * 3 + coord.y * 7) * 0.13, 1.0)
	var border_color: Color = Color.from_hsv(hue, 0.55, 0.45)
	border.set_instance_shader_parameter(PARAM_TINT, border_color)
	root.add_child(border)
	border.owner = root

	var crate: StaticBody3D = StaticBody3D.new()
	crate.name = "TestCrate"
	crate.collision_layer = CollisionLayers.MASK_INTERACTIVE
	crate.collision_mask = CollisionLayers.MASK_NONE
	crate.position = Vector3(125.0, 1.5, 125.0)
	crate.add_to_group(GROUP_CRATE, true)
	root.add_child(crate)
	crate.owner = root
	crate.unique_name_in_owner = true

	var crate_col: CollisionShape3D = CollisionShape3D.new()
	crate_col.name = "CollisionShape3D"
	crate_col.shape = crate_shape
	crate.add_child(crate_col)
	crate_col.owner = root

	var crate_vis: MeshInstance3D = MeshInstance3D.new()
	crate_vis.name = "MeshInstance3D"
	crate_vis.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	crate_vis.mesh = crate_mesh
	crate_vis.material_override = mat
	crate_vis.set_instance_shader_parameter(PARAM_TINT, COLOR_CRATE)
	crate.add_child(crate_vis)
	crate_vis.owner = root

	var roamer: CharacterBody3D = CharacterBody3D.new()
	roamer.name = "TestRoamer"
	roamer.collision_layer = CollisionLayers.MASK_ENEMIES
	roamer.collision_mask = CollisionLayers.MASK_ENVIRONMENT
	roamer.position = Vector3(132.0, 1.5, 132.0)
	roamer.add_to_group(GROUP_ROAMING, true)
	root.add_child(roamer)
	roamer.owner = root
	roamer.unique_name_in_owner = true

	var roamer_col: CollisionShape3D = CollisionShape3D.new()
	roamer_col.name = "CollisionShape3D"
	roamer_col.shape = roamer_shape
	roamer.add_child(roamer_col)
	roamer_col.owner = root

	var roamer_vis: MeshInstance3D = MeshInstance3D.new()
	roamer_vis.name = "MeshInstance3D"
	roamer_vis.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	roamer_vis.mesh = roamer_mesh
	roamer_vis.material_override = mat
	roamer_vis.set_instance_shader_parameter(PARAM_TINT, COLOR_ROAMER)
	roamer.add_child(roamer_vis)
	roamer_vis.owner = root

	var packed: PackedScene = PackedScene.new()
	var pack_err: Error = packed.pack(root)
	if pack_err == OK:
		var path: String = CHUNK_PATH_FMT % [coord.x, coord.y]
		ResourceSaver.save(packed, path)
	root.free()
