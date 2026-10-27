## Unit test suite validating RaftPlatform scene instantiation, geometry, and buoyancy probes.
extends GutTest

const RAFT_SCENE: PackedScene = preload("res://interactables/raft_platform.tscn")

## Instance of RaftPlatform under test.
var _raft: RaftPlatform = null


## Instantiates fresh RaftPlatform scene for each test.
func before_each() -> void:
	print("Setting up RaftPlatform test instance.")
	var node: Node = RAFT_SCENE.instantiate()
	if node is RaftPlatform:
		_raft = node as RaftPlatform
	add_child_autofree(_raft)


## Cleans up RaftPlatform reference after each test.
func after_each() -> void:
	print("Tearing down RaftPlatform test instance.")
	_raft = null


## Verifies scene instantiates as RaftPlatform with correct physical defaults.
func test_raft_physical_properties() -> void:
	print("Testing RaftPlatform physical configuration.")
	assert_not_null(_raft, "RaftPlatform scene should instantiate cleanly.")
	assert_eq(_raft.mass, 60.0, "Raft mass should default to 60.0kg.")
	assert_false(
		_raft.lock_on_player_stand, "Raft should not lock static when player stands on it."
	)
	assert_eq(
		_raft.hold_distance_offset, -1.6, "Hold distance offset should be -1.6 for large raft."
	)
	assert_eq(_raft.max_detach_distance, 3.6, "Max detach distance should be 3.6m.")
	assert_eq(
		_raft.center_of_mass,
		Vector3(0.0, -0.35, 0.0),
		"Center of mass should be lowered for stability."
	)


## Verifies that four buoyancy probes exist at barrel locations.
func test_buoyancy_probes() -> void:
	print("Testing RaftPlatform buoyancy probes.")
	var probe_container: Node3D = _raft.probe_container
	assert_not_null(probe_container, "ProbeContainer should be valid.")

	var probes: Array[Node] = probe_container.get_children()
	assert_eq(probes.size(), 4, "Raft must have exactly 4 buoyancy probes.")

	var probe_fl: Marker3D = probe_container.get_node_or_null("Marker3D") as Marker3D
	var probe_bl: Marker3D = probe_container.get_node_or_null("Marker3D2") as Marker3D
	var probe_fr: Marker3D = probe_container.get_node_or_null("Marker3D3") as Marker3D
	var probe_br: Marker3D = probe_container.get_node_or_null("Marker3D4") as Marker3D

	assert_not_null(probe_fl, "Front-left probe should exist.")
	assert_not_null(probe_bl, "Back-left probe should exist.")
	assert_not_null(probe_fr, "Front-right probe should exist.")
	assert_not_null(probe_br, "Back-right probe should exist.")

	assert_almost_eq(probe_fl.position.x, -0.85, 0.05, "FL probe X should match barrel.")
	assert_almost_eq(probe_fl.position.z, -1.1, 0.05, "FL probe Z should match barrel.")
	assert_almost_eq(probe_br.position.x, 0.85, 0.05, "BR probe X should match barrel.")
	assert_almost_eq(probe_br.position.z, 1.1, 0.05, "BR probe Z should match barrel.")


## Verifies platform deck and barrel dimensions.
func test_platform_and_barrel_geometry() -> void:
	print("Testing platform dimensions and barrel layout.")
	var deck_col: CollisionShape3D = _raft.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_not_null(deck_col, "Deck collision shape should exist.")
	assert_true(deck_col.shape is BoxShape3D, "Deck collision shape should be a BoxShape3D.")

	var box_shape: BoxShape3D = deck_col.shape as BoxShape3D
	assert_eq(box_shape.size.x, 2.5, "Deck width must be 2.5m.")
	assert_eq(box_shape.size.z, 4.0, "Deck length must be 4.0m.")

	var barrel_fl_col: CollisionShape3D = (
		_raft.get_node_or_null("CollisionShape_FL") as CollisionShape3D
	)
	assert_not_null(barrel_fl_col, "FL barrel collision shape should exist.")
	assert_true(
		barrel_fl_col.shape is CylinderShape3D, "Barrel collision should be CylinderShape3D."
	)

	var cyl_shape: CylinderShape3D = barrel_fl_col.shape as CylinderShape3D
	assert_almost_eq(cyl_shape.radius, 0.35, 0.01, "Barrel radius should be 0.35m.")
	assert_almost_eq(cyl_shape.height, 1.2, 0.01, "Barrel length should be 1.2m.")


## Verifies that initial underwater placement wakes up buoyancy state.
func test_initial_underwater_overlap() -> void:
	print("Testing initial underwater overlap detection.")
	var water_packed: PackedScene = load("res://environment/water_body.tscn") as PackedScene
	var water_instance: Node = water_packed.instantiate()
	var water_mesh: MeshInstance3D = water_instance as MeshInstance3D
	water_mesh.set(&"water_size", Vector3(10.0, 10.0, 10.0))
	add_child_autofree(water_mesh)
	water_mesh.global_position = Vector3(0.0, 0.0, 0.0)

	_raft.global_position = Vector3(0.0, -1.0, 0.0)
	_raft.call(&"_check_initial_water_overlap_deferred")

	assert_true(_raft.is_in_water, "Raft placed underwater should activate is_in_water.")
	assert_eq(_raft.current_water_node, water_mesh, "Raft should bind current water body.")
	assert_false(_raft.sleeping, "Raft should awaken from physics sleep when submerged.")
