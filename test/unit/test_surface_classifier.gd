## Unit test suite validating [SurfaceClassifier] group, metadata, material, and name fallbacks.
class_name TestSurfaceClassifier
extends GutTest


## Verifies direct collider node groups map to the expected [enum SurfaceClassifier.SurfaceType].
func test_collider_groups() -> void:
	var groups: Dictionary[StringName, SurfaceClassifier.SurfaceType] = {
		&"wood": SurfaceClassifier.SurfaceType.WOOD,
		&"metal": SurfaceClassifier.SurfaceType.METAL,
		&"concrete": SurfaceClassifier.SurfaceType.CONCRETE,
		&"stone": SurfaceClassifier.SurfaceType.CONCRETE,
		&"brick": SurfaceClassifier.SurfaceType.CONCRETE,
		&"dirt": SurfaceClassifier.SurfaceType.DIRT,
		&"soil": SurfaceClassifier.SurfaceType.DIRT,
		&"wet_dirt": SurfaceClassifier.SurfaceType.DIRT,
		&"glass": SurfaceClassifier.SurfaceType.GLASS,
	}
	for group_name: StringName in groups:
		var body: StaticBody3D = StaticBody3D.new()
		body.add_to_group(group_name)
		add_child_autofree(body)
		assert_eq(
			SurfaceClassifier.classify(body),
			groups[group_name],
			"Group '%s' should classify accurately." % String(group_name)
		)


## Verifies parent node groups apply when the collider itself has no group.
func test_parent_group_fallback() -> void:
	var parent: Node3D = Node3D.new()
	parent.add_to_group(&"metal")
	var collider: StaticBody3D = StaticBody3D.new()
	parent.add_child(collider)
	add_child_autofree(parent)

	assert_eq(
		SurfaceClassifier.classify(collider),
		SurfaceClassifier.SurfaceType.METAL,
		"Parent group should classify child collider."
	)


## Verifies metadata surface_type supports String, StringName, int enum, and safe invalid inputs.
func test_metadata_surface_type() -> void:
	var str_body: StaticBody3D = StaticBody3D.new()
	str_body.set_meta(&"surface_type", "Wood")
	add_child_autofree(str_body)
	assert_eq(SurfaceClassifier.classify(str_body), SurfaceClassifier.SurfaceType.WOOD)

	var sn_body: StaticBody3D = StaticBody3D.new()
	sn_body.set_meta(&"surface_type", &"wet_dirt")
	add_child_autofree(sn_body)
	assert_eq(SurfaceClassifier.classify(sn_body), SurfaceClassifier.SurfaceType.DIRT)

	var int_body: StaticBody3D = StaticBody3D.new()
	int_body.set_meta(&"surface_type", SurfaceClassifier.SurfaceType.GLASS)
	add_child_autofree(int_body)
	assert_eq(SurfaceClassifier.classify(int_body), SurfaceClassifier.SurfaceType.GLASS)

	var parent_meta: Node3D = Node3D.new()
	parent_meta.set_meta(&"surface_type", "metal")
	var child_body: StaticBody3D = StaticBody3D.new()
	parent_meta.add_child(child_body)
	add_child_autofree(parent_meta)
	assert_eq(SurfaceClassifier.classify(child_body), SurfaceClassifier.SurfaceType.METAL)

	var bad_int_body: StaticBody3D = StaticBody3D.new()
	bad_int_body.name = "WoodenCrate"
	bad_int_body.set_meta(&"surface_type", 99)
	add_child_autofree(bad_int_body)
	assert_eq(
		SurfaceClassifier.classify(bad_int_body),
		SurfaceClassifier.SurfaceType.WOOD,
		"Out-of-range int metadata should safely fall through to name."
	)

	var bad_type_body: StaticBody3D = StaticBody3D.new()
	bad_type_body.set_meta(&"surface_type", Vector3.ONE)
	add_child_autofree(bad_type_body)
	assert_eq(
		SurfaceClassifier.classify(bad_type_body),
		SurfaceClassifier.SurfaceType.CONCRETE,
		"Unsupported metadata Variant type should fall back to concrete."
	)


## Verifies group priority beats metadata and metadata priority beats node name.
func test_precedence_order() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "DirtMound"
	body.set_meta(&"surface_type", "glass")
	body.add_to_group(&"metal")
	add_child_autofree(body)
	assert_eq(
		SurfaceClassifier.classify(body),
		SurfaceClassifier.SurfaceType.METAL,
		"Group must take precedence over metadata and name."
	)

	var meta_wins: StaticBody3D = StaticBody3D.new()
	meta_wins.name = "SteelGirder"
	meta_wins.set_meta(&"surface_type", "wood")
	add_child_autofree(meta_wins)
	assert_eq(
		SurfaceClassifier.classify(meta_wins),
		SurfaceClassifier.SurfaceType.WOOD,
		"Metadata must take precedence over node name."
	)


## Verifies child and sibling MeshInstance3D material_override and surface material paths classify.
func test_material_resource_path_fallback() -> void:
	var child_override_body: StaticBody3D = StaticBody3D.new()
	var child_mesh: MeshInstance3D = MeshInstance3D.new()
	var wood_mat: StandardMaterial3D = StandardMaterial3D.new()
	wood_mat.resource_path = "res://tests/surface_mock_oak_wood.tres"
	child_mesh.material_override = wood_mat
	child_override_body.add_child(child_mesh)
	add_child_autofree(child_override_body)
	assert_eq(
		SurfaceClassifier.classify(child_override_body),
		SurfaceClassifier.SurfaceType.WOOD,
		"Child MeshInstance3D material_override path should classify."
	)

	var parent_root: Node3D = Node3D.new()
	var sibling_body: StaticBody3D = StaticBody3D.new()
	var sibling_mesh: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	var metal_mat: StandardMaterial3D = StandardMaterial3D.new()
	metal_mat.resource_path = "res://tests/surface_mock_galvanized_steel.tres"
	box_mesh.surface_set_material(0, metal_mat)
	sibling_mesh.mesh = box_mesh
	parent_root.add_child(sibling_body)
	parent_root.add_child(sibling_mesh)
	add_child_autofree(parent_root)
	assert_eq(
		SurfaceClassifier.classify(sibling_body),
		SurfaceClassifier.SurfaceType.METAL,
		"Sibling MeshInstance3D surface material path should classify."
	)


## Verifies lowercase node and parent name substring fallback across all surface types.
func test_node_and_parent_name_fallback() -> void:
	var name_cases: Dictionary[String, SurfaceClassifier.SurfaceType] = {
		"TimberBeam": SurfaceClassifier.SurfaceType.WOOD,
		"BreakableCrate": SurfaceClassifier.SurfaceType.WOOD,
		"OSB_Panel": SurfaceClassifier.SurfaceType.WOOD,
		"Sheet_Metal_Door": SurfaceClassifier.SurfaceType.METAL,
		"SteamPipe": SurfaceClassifier.SurfaceType.METAL,
		"ServiceLadder": SurfaceClassifier.SurfaceType.METAL,
		"MudBank": SurfaceClassifier.SurfaceType.DIRT,
		"GrassTerrain": SurfaceClassifier.SurfaceType.DIRT,
		"SandDune": SurfaceClassifier.SurfaceType.DIRT,
		"WindowPane": SurfaceClassifier.SurfaceType.GLASS,
		"GlassPartition": SurfaceClassifier.SurfaceType.GLASS,
		"BrickFacade": SurfaceClassifier.SurfaceType.CONCRETE,
		"CementPillar": SurfaceClassifier.SurfaceType.CONCRETE,
		"OuterWall": SurfaceClassifier.SurfaceType.CONCRETE,
	}
	for node_name: String in name_cases:
		var body: StaticBody3D = StaticBody3D.new()
		body.name = node_name
		add_child_autofree(body)
		assert_eq(
			SurfaceClassifier.classify(body),
			name_cases[node_name],
			"Node name '%s' should classify accurately." % node_name
		)

	var parent: Node3D = Node3D.new()
	parent.name = "IronGrille"
	var child_collider: StaticBody3D = StaticBody3D.new()
	child_collider.name = "Collider"
	parent.add_child(child_collider)
	add_child_autofree(parent)
	assert_eq(
		SurfaceClassifier.classify(child_collider),
		SurfaceClassifier.SurfaceType.METAL,
		"Parent name substring should classify child collider."
	)


## Verifies null, non-Node objects, and unrecognized names default to CONCRETE.
func test_concrete_default_fallback() -> void:
	assert_eq(SurfaceClassifier.classify(null), SurfaceClassifier.SurfaceType.CONCRETE)

	var plain_obj: RefCounted = RefCounted.new()
	assert_eq(SurfaceClassifier.classify(plain_obj), SurfaceClassifier.SurfaceType.CONCRETE)

	var generic_body: StaticBody3D = StaticBody3D.new()
	generic_body.name = "GenericObstacle"
	add_child_autofree(generic_body)
	assert_eq(SurfaceClassifier.classify(generic_body), SurfaceClassifier.SurfaceType.CONCRETE)
