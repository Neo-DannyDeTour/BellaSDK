## Unit and integration tests for destructible wall support graph, baking, debris, and level.
class_name TestWallSupportGraph
extends GutTest

## Directory containing the destructible wall module assets.
const WALL_DIR: String = "res://interactables/destructible_wall/"

## Resource path to the baked 2m x 3m destructible concrete wall data.
const BAKED_DATA_PATH: String = WALL_DIR + "models/wall_panel_2x3_data.tres"

## Scene path to the runtime destructible wall panel prefab.
const PANEL_SCENE_PATH: String = WALL_DIR + "destructible_wall_panel.tscn"

## Script path to the DebrisBudget autoload singleton.
const DEBRIS_BUDGET_PATH: String = "res://core/debris_budget.gd"

## Scene path to the destructible wall testbed level.
const TEST_LEVEL_PATH: String = "res://levels/test_destructible_wall.tscn"

## Shader uniform name for per-panel RG8 surface damage mask texture.
const PARAM_DAMAGE_MASK: StringName = &"damage_mask"

## Shader uniform name toggling surface POM crater rendering.
const PARAM_HAS_SURFACE_DAMAGE: StringName = &"has_surface_damage"

## Shader uniform name tracking active rebar blast count.
const PARAM_BLAST_COUNT: StringName = &"blast_count"

## Shader uniform name tracking rebar blast origin and radius array.
const PARAM_BLAST_POINTS: StringName = &"blast_points"

## Shader uniform name tracking rebar blast push direction and amplitude array.
const PARAM_BLAST_DIRS: StringName = &"blast_dirs"


## Clears active debris from the DebrisBudget autoload before each test.
func before_each() -> void:
	print("TestWallSupportGraph: Setting up test environment.")
	var budget: Node = get_node_or_null("/root/DebrisBudget")
	if is_instance_valid(budget):
		budget.call(&"clear_all")


## Clears spawned debris and flushes deferred frees after each test.
func after_each() -> void:
	print("TestWallSupportGraph: Tearing down test environment.")
	var budget: Node = get_node_or_null("/root/DebrisBudget")
	if is_instance_valid(budget):
		budget.call(&"clear_all")
	await get_tree().process_frame


## Verifies 64-chunk bitmask helpers and absence of bit-63 sign extension.
func test_bitmask_helpers_and_64_chunk_cap() -> void:
	assert_eq(WallPanelData.all_chunks_mask(-1), 0, "Negative count mask must be 0.")
	assert_eq(WallPanelData.all_chunks_mask(0), 0, "Zero count mask must be 0.")
	assert_eq(WallPanelData.all_chunks_mask(1), 1, "Single chunk mask must be 1.")
	assert_eq(
		WallPanelData.all_chunks_mask(42), (1 << 42) - 1, "42-chunk mask must match (1 << 42) - 1."
	)
	assert_eq(WallPanelData.all_chunks_mask(64), -1, "64-chunk mask must equal -1.")
	assert_eq(WallPanelData.all_chunks_mask(65), -1, "Counts above 64 must clamp to -1.")

	assert_eq(WallPanelData.bit_for_chunk(-1), 0, "Negative chunk index bit must be 0.")
	assert_eq(WallPanelData.bit_for_chunk(64), 0, "Out-of-range chunk 64 bit must be 0.")
	assert_eq(WallPanelData.bit_for_chunk(0), 1, "Chunk 0 bit must equal 1.")

	var bit63: int = WallPanelData.bit_for_chunk(63)
	assert_ne(bit63, 0, "Chunk 63 bit must be non-zero.")
	assert_true(WallPanelData.is_chunk_set(bit63, 63), "Bit 63 must register as set.")
	assert_false(WallPanelData.is_chunk_set(bit63, -1), "Out-of-bounds -1 must read false.")
	assert_false(WallPanelData.is_chunk_set(bit63, 64), "Out-of-bounds 64 must read false.")

	var low_bits: int = WallPanelData.bit_for_chunk(0) | WallPanelData.bit_for_chunk(31)
	assert_eq(
		WallPanelData.mask_low_u32(low_bits), 0x80000001, "Low u32 must preserve bits 0 and 31."
	)
	assert_eq(WallPanelData.mask_high_u32(low_bits), 0, "High u32 must be 0 for low-only bits.")

	var high_bits: int = WallPanelData.bit_for_chunk(32) | bit63
	assert_eq(WallPanelData.mask_low_u32(high_bits), 0, "Low u32 must be 0 for high-only bits.")
	assert_eq(
		WallPanelData.mask_high_u32(high_bits),
		0x80000001,
		"High u32 must mask bit 63 without sign extension."
	)
	assert_eq(
		WallPanelData.mask_high_u32(bit63),
		0x80000000,
		"Bit 63 alone must yield unsigned 0x80000000."
	)

	var mixed_bits: int = low_bits | high_bits
	assert_eq(WallPanelData.mask_low_u32(mixed_bits), 0x80000001, "Mixed low u32 mismatch.")
	assert_eq(WallPanelData.mask_high_u32(mixed_bits), 0x80000001, "Mixed high u32 mismatch.")

	var full_mask: int = WallPanelData.all_chunks_mask(64)
	assert_eq(
		WallPanelData.mask_low_u32(full_mask),
		0xFFFFFFFF,
		"Full 64-bit mask low u32 must be 0xFFFFFFFF."
	)
	assert_eq(
		WallPanelData.mask_high_u32(full_mask),
		0xFFFFFFFF,
		"Full 64-bit mask high u32 must be 0xFFFFFFFF."
	)


## Verifies synthetic support graph BFS retention, bridge cuts, sorted islands, and total loss.
func test_synthetic_support_graph_bfs() -> void:
	var dual_adj: Array[PackedInt32Array] = [
		PackedInt32Array([1]),
		PackedInt32Array([0, 2]),
		PackedInt32Array([1, 3]),
		PackedInt32Array([2, 4]),
		PackedInt32Array([3])
	]
	var dual_anchors: int = WallPanelData.bit_for_chunk(0) | WallPanelData.bit_for_chunk(4)
	var dual_data: WallPanelData = _build_synthetic_panel(5, dual_adj, dual_anchors)

	assert_eq(
		dual_data.find_supported_mask(0),
		WallPanelData.all_chunks_mask(5),
		"All 5 chunks must be supported initially."
	)

	var mid_cut: int = WallPanelData.bit_for_chunk(2)
	var expected_dual: int = (
		WallPanelData.bit_for_chunk(0)
		| WallPanelData.bit_for_chunk(1)
		| WallPanelData.bit_for_chunk(3)
		| WallPanelData.bit_for_chunk(4)
	)
	assert_eq(
		dual_data.find_supported_mask(mid_cut),
		expected_dual,
		"Top and bottom anchors must retain both halves after middle cut."
	)
	assert_eq(
		dual_data.find_disconnected_islands(mid_cut).size(),
		0,
		"Dual-anchored halves must yield zero islands."
	)

	var cut_top_anchor: int = WallPanelData.bit_for_chunk(0) | mid_cut
	var half_supported: int = WallPanelData.bit_for_chunk(3) | WallPanelData.bit_for_chunk(4)
	assert_eq(
		dual_data.find_supported_mask(cut_top_anchor),
		half_supported,
		"Removing top anchor must leave only bottom-anchored chunks supported."
	)
	var single_islands: Array[PackedInt32Array] = dual_data.find_disconnected_islands(
		cut_top_anchor
	)
	assert_eq(single_islands.size(), 1, "Chunk 1 must detach as one island.")
	assert_eq(single_islands[0], PackedInt32Array([1]), "Detached island must equal [1].")

	var branch_adj: Array[PackedInt32Array] = [
		PackedInt32Array([1]),
		PackedInt32Array([0, 2, 4]),
		PackedInt32Array([1, 3]),
		PackedInt32Array([2]),
		PackedInt32Array([1, 5]),
		PackedInt32Array([4])
	]
	var branch_data: WallPanelData = _build_synthetic_panel(
		6, branch_adj, WallPanelData.bit_for_chunk(0)
	)
	var leaf_cut: int = WallPanelData.bit_for_chunk(3)
	assert_eq(
		branch_data.find_disconnected_islands(leaf_cut).size(),
		0,
		"Removing leaf chunk 3 must keep all neighbors supported."
	)

	var bridge_cut: int = WallPanelData.bit_for_chunk(1)
	assert_eq(
		branch_data.find_supported_mask(bridge_cut),
		WallPanelData.bit_for_chunk(0),
		"Cutting bridge chunk 1 must leave only anchor 0 supported."
	)
	var multi_islands: Array[PackedInt32Array] = branch_data.find_disconnected_islands(bridge_cut)
	assert_eq(multi_islands.size(), 2, "Bridge cut must create two disconnected islands.")
	var has_pair_a: bool = false
	var has_pair_b: bool = false
	for island: PackedInt32Array in multi_islands:
		for k: int in range(island.size() - 1):
			assert_lt(island[k], island[k + 1], "Island indices must be sorted ascending.")
		if island == PackedInt32Array([2, 3]):
			has_pair_a = true
		elif island == PackedInt32Array([4, 5]):
			has_pair_b = true
	assert_true(has_pair_a, "Disconnected islands must include sorted [2, 3].")
	assert_true(has_pair_b, "Disconnected islands must include sorted [4, 5].")

	var all_removed: int = WallPanelData.all_chunks_mask(6)
	assert_eq(branch_data.find_supported_mask(all_removed), 0, "Full removal leaves 0 supported.")
	assert_eq(
		branch_data.find_disconnected_islands(all_removed).size(),
		0,
		"Full removal leaves 0 disconnected islands."
	)
	assert_eq(
		branch_data.find_nearest_remaining_chunk(Vector3.ZERO, all_removed),
		-1,
		"Full removal returns -1 for nearest remaining chunk."
	)


## Validates baked 2x3 wall panel data resource structure, graph symmetry, and meshes.
func test_baked_wall_panel_2x3_data() -> void:
	var res: Resource = ResourceLoader.load(BAKED_DATA_PATH)
	var data: WallPanelData = res as WallPanelData
	assert_not_null(data, "Baked wall_panel_2x3_data.tres must load as WallPanelData.")
	if not is_instance_valid(data):
		return

	assert_true(data.is_valid(), "Baked WallPanelData must report is_valid() == true.")
	assert_eq(data.chunk_count, 42, "Baked wall panel must contain exactly 42 chunks.")

	var anchor_count: int = 0
	for i: int in range(data.chunk_count):
		if WallPanelData.is_chunk_set(data.anchor_mask, i):
			anchor_count += 1
	assert_eq(anchor_count, 7, "Baked anchor_mask must have exactly 7 anchor bits set.")

	assert_eq(data.adjacency.size(), 42, "Adjacency list must contain 42 rows.")
	for i: int in range(data.adjacency.size()):
		var row: PackedInt32Array = data.adjacency[i]
		assert_false(row.has(i), "Adjacency must not contain self-loops.")
		for k: int in range(row.size()):
			var neighbor: int = row[k]
			assert_gte(neighbor, 0, "Neighbor index must be >= 0.")
			assert_lt(neighbor, 42, "Neighbor index must be < 42.")
			if k + 1 < row.size():
				assert_lt(row[k], row[k + 1], "Adjacency row must be sorted and unique.")
			assert_true(
				data.adjacency[neighbor].has(i), "Adjacency must be symmetric across every edge."
			)

	assert_eq(
		data.find_supported_mask(0),
		WallPanelData.all_chunks_mask(42),
		"All 42 baked chunks must be reachable from anchors with 0 removals."
	)

	assert_not_null(data.merged_mesh, "Baked merged_mesh must not be null.")
	if is_instance_valid(data.merged_mesh):
		assert_eq(
			data.merged_mesh.get_surface_count(),
			2,
			"Baked merged_mesh must have 2 surfaces (outer and inner)."
		)
		for surf_idx: int in range(data.merged_mesh.get_surface_count()):
			var fmt: int = data.merged_mesh.surface_get_format(surf_idx)
			assert_ne(
				fmt & Mesh.ARRAY_FORMAT_CUSTOM0,
				0,
				"Merged mesh surface must include ARRAY_FORMAT_CUSTOM0."
			)
			var arrays: Array = data.merged_mesh.surface_get_arrays(surf_idx)
			assert_gt(
				arrays.size(), Mesh.ARRAY_CUSTOM0, "Surface arrays must cover ARRAY_CUSTOM0 slot."
			)
			assert_not_null(arrays[Mesh.ARRAY_CUSTOM0], "ARRAY_CUSTOM0 buffer must exist.")

	assert_not_null(data.rebar_mesh, "Baked rebar_mesh must not be null.")
	assert_not_null(data.rebar_shape, "Baked rebar_shape must not be null.")
	assert_eq(data.chunk_shapes.size(), 42, "chunk_shapes must have 42 entries.")
	assert_eq(data.chunk_meshes.size(), 42, "chunk_meshes must have 42 entries.")
	assert_eq(data.chunk_centroids.size(), 42, "chunk_centroids must have 42 entries.")
	assert_eq(data.chunk_volumes.size(), 42, "chunk_volumes must have 42 entries.")
	for i: int in range(42):
		assert_not_null(data.chunk_shapes[i], "Each chunk shape must be non-null.")
		if is_instance_valid(data.chunk_shapes[i]):
			assert_gte(data.chunk_shapes[i].points.size(), 4, "Chunk shape needs >= 4 points.")
		assert_not_null(data.chunk_meshes[i], "Each chunk mesh must be non-null.")
		if is_instance_valid(data.chunk_meshes[i]):
			assert_gt(
				data.chunk_meshes[i].get_surface_count(),
				0,
				"Each chunk mesh must contain at least 1 surface."
			)
		assert_gt(data.chunk_volumes[i], 0.0, "Each chunk volume must be positive.")


## Validates DebrisBudget FIFO eviction cap when registering more bodies than max_debris.
func test_debris_budget_fifo_eviction() -> void:
	var script_res: Resource = ResourceLoader.load(DEBRIS_BUDGET_PATH)
	var budget_script: GDScript = script_res as GDScript
	assert_not_null(budget_script, "debris_budget.gd must load as GDScript.")
	if not is_instance_valid(budget_script):
		return

	var new_obj: Object = budget_script.new()
	var budget: Node = new_obj as Node
	assert_not_null(budget, "DebrisBudget must instantiate as Node.")
	if not is_instance_valid(budget):
		return
	add_child_autoqfree(budget)
	budget.set(&"max_debris", 4)

	var bodies: Array[RigidBody3D] = []
	for i: int in range(6):
		var body: RigidBody3D = RigidBody3D.new()
		body.name = "DummyDebris_%d" % i
		add_child_autoqfree(body)
		bodies.append(body)
		budget.call(&"register_debris", body)

	assert_true(bodies[0].is_queued_for_deletion(), "Oldest debris 0 must be evicted first.")
	assert_true(bodies[1].is_queued_for_deletion(), "Second oldest debris 1 must be evicted.")

	await get_tree().process_frame

	assert_false(is_instance_valid(bodies[0]), "Evicted debris 0 must be freed.")
	assert_false(is_instance_valid(bodies[1]), "Evicted debris 1 must be freed.")
	assert_true(is_instance_valid(bodies[2]), "Debris 2 must remain active.")
	assert_true(is_instance_valid(bodies[5]), "Newest debris 5 must remain active.")

	var raw_count: Variant = budget.call(&"get_active_count")
	var active_count: int = raw_count if raw_count is int else 999
	assert_lte(active_count, 4, "Active debris count must not exceed max_debris = 4.")
	assert_eq(active_count, 4, "Active debris count should equal max_debris = 4.")


## Validates DestructibleWallPanel idle state, RG8 mask painting, breakage, rebar, impact, blast.
func test_destructible_wall_panel_runtime() -> void:
	var packed: PackedScene = ResourceLoader.load(PANEL_SCENE_PATH) as PackedScene
	assert_not_null(packed, "destructible_wall_panel.tscn must load cleanly.")
	if not is_instance_valid(packed):
		return

	var panel: DestructibleWallPanel = packed.instantiate() as DestructibleWallPanel
	assert_not_null(panel, "Scene root must instantiate as DestructibleWallPanel.")
	if not is_instance_valid(panel):
		return
	add_child_autoqfree(panel)

	assert_false(panel.is_processing(), "Panel must disable _process() when idle.")
	assert_false(panel.is_physics_processing(), "Panel must disable _physics_process() when idle.")

	var wall_mesh: MeshInstance3D = panel.get_node_or_null(^"WallMesh") as MeshInstance3D
	assert_not_null(wall_mesh, "Panel must contain WallMesh child.")
	var initial_outer: Material = wall_mesh.get_active_material(0)
	var initial_inner: Material = wall_mesh.get_active_material(1)

	var front_pos: Vector3 = panel.to_global(Vector3(0.0, 1.5, 0.125))
	var front_dir: Vector3 = (panel.global_transform.basis * Vector3(0.0, 0.0, -1.0)).normalized()
	panel.take_damage(25, front_pos, front_dir)

	var back_pos: Vector3 = panel.to_global(Vector3(0.4, 1.5, -0.125))
	var back_dir: Vector3 = (panel.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	panel.take_damage(25, back_pos, back_dir)

	var unique_outer: Material = wall_mesh.get_active_material(0)
	var unique_inner: Material = wall_mesh.get_active_material(1)
	assert_ne(unique_outer, initial_outer, "Surface 0 material must lazily duplicate on hit.")
	assert_ne(unique_inner, initial_inner, "Surface 1 material must lazily duplicate on hit.")

	var outer_shader: ShaderMaterial = unique_outer as ShaderMaterial
	assert_not_null(outer_shader, "Outer material must be a ShaderMaterial.")
	if is_instance_valid(outer_shader):
		var raw_has_dmg: Variant = outer_shader.get_shader_parameter(PARAM_HAS_SURFACE_DAMAGE)
		var has_dmg: bool = raw_has_dmg if raw_has_dmg is bool else false
		assert_true(has_dmg, "has_surface_damage uniform must enable after hit.")

		var raw_tex: Variant = outer_shader.get_shader_parameter(PARAM_DAMAGE_MASK)
		var mask_tex: ImageTexture = raw_tex if raw_tex is ImageTexture else null
		assert_not_null(mask_tex, "damage_mask uniform must hold an ImageTexture after hit.")
		if is_instance_valid(mask_tex):
			var img: Image = mask_tex.get_image()
			assert_not_null(img, "damage_mask ImageTexture must contain an Image.")
			assert_eq(img.get_format(), Image.FORMAT_RG8, "damage_mask must use RG8 format.")
			var front_px: Color = img.get_pixel(
				clampi(int(0.5 * float(img.get_width())), 0, img.get_width() - 1),
				clampi(int(0.5 * float(img.get_height())), 0, img.get_height() - 1)
			)
			var back_px: Color = img.get_pixel(
				clampi(int(0.7 * float(img.get_width())), 0, img.get_width() - 1),
				clampi(int(0.5 * float(img.get_height())), 0, img.get_height() - 1)
			)
			assert_gt(front_px.r, 0.0, "Front hit must paint non-zero R channel in damage_mask.")
			assert_gt(back_px.g, 0.0, "Back hit must paint non-zero G channel in damage_mask.")

	watch_signals(panel)
	for step_idx: int in range(8):
		if panel.removed_mask != 0:
			break
		panel.take_damage(100, front_pos, front_dir)

	assert_ne(panel.removed_mask, 0, "Repeated take_damage must pop at least one chunk.")
	assert_signal_emitted(panel, "chunk_removed", "Removing a chunk must emit chunk_removed.")
	assert_signal_emitted(panel, "panel_breached", "First chunk removal must emit panel_breached.")
	assert_true(panel.is_breached, "Panel must mark is_breached after first chunk removal.")

	await get_tree().process_frame

	var disabled_found: bool = false
	for child: Node in panel.get_children():
		var col: CollisionShape3D = child as CollisionShape3D
		if is_instance_valid(col) and col.disabled:
			disabled_found = true
			break
	assert_true(disabled_found, "Removed chunk CollisionShape3D must be disabled after flush.")

	var rebar_body: WallRebarBody = panel.get_node_or_null(^"RebarBody") as WallRebarBody
	assert_not_null(rebar_body, "Panel must contain WallRebarBody child named RebarBody.")
	var mask_before_rebar: int = panel.removed_mask
	if is_instance_valid(rebar_body):
		rebar_body.take_damage(500, panel.to_global(Vector3(0.0, 1.5, 0.0)), front_dir)
	assert_eq(
		panel.removed_mask,
		mask_before_rebar,
		"Hitting RebarBody must not damage concrete wall chunks."
	)

	var mask_before_low_impact: int = panel.removed_mask
	var impact_pt: Vector3 = panel.to_global(Vector3(-0.6, 1.5, 0.125))
	panel.apply_impact(impact_pt, panel.impact_momentum_threshold - 1.0)
	assert_eq(
		panel.removed_mask,
		mask_before_low_impact,
		"Impact below momentum threshold must not remove chunks."
	)

	panel.apply_impact(impact_pt, panel.impact_momentum_threshold + 50.0)
	assert_ne(
		panel.removed_mask,
		mask_before_low_impact,
		"Impact above momentum threshold must remove at least one chunk."
	)

	var mask_before_blast: int = panel.removed_mask
	panel.apply_blast(panel.to_global(Vector3(0.55, 1.5, 0.1)), 0.75, 100.0)
	assert_ne(
		panel.removed_mask,
		mask_before_blast,
		"Blast must remove concrete chunks within blast radius."
	)

	var rebar_mesh: MeshInstance3D = (
		panel.get_node_or_null(^"RebarBody/RebarMesh") as MeshInstance3D
	)
	assert_not_null(rebar_mesh, "RebarBody must contain RebarMesh child.")
	if is_instance_valid(rebar_mesh):
		var rebar_mat: ShaderMaterial = rebar_mesh.get_active_material(0) as ShaderMaterial
		assert_not_null(rebar_mat, "RebarMesh must use a ShaderMaterial.")
		if is_instance_valid(rebar_mat):
			var raw_bc: Variant = rebar_mat.get_shader_parameter(PARAM_BLAST_COUNT)
			var blast_cnt: int = raw_bc if raw_bc is int else 0
			assert_gte(blast_cnt, 1, "apply_blast must increment rebar blast_count.")
			var pts_vec: PackedVector4Array = _extract_vec4_array(
				rebar_mat.get_shader_parameter(PARAM_BLAST_POINTS)
			)
			assert_gt(pts_vec.size(), 0, "apply_blast must populate rebar blast_points.")
			if pts_vec.size() > 0:
				assert_gt(pts_vec[0].w, 0.0, "Blast point 0 radius (.w) must be positive.")
			var dirs_vec: PackedVector4Array = _extract_vec4_array(
				rebar_mat.get_shader_parameter(PARAM_BLAST_DIRS)
			)
			assert_gt(dirs_vec.size(), 0, "apply_blast must populate rebar blast_dirs.")
			if dirs_vec.size() > 0:
				assert_gt(dirs_vec[0].w, 0.0, "Blast dir 0 bend amplitude (.w) must be positive.")

	var budget: Node = get_node_or_null("/root/DebrisBudget")
	assert_not_null(budget, "/root/DebrisBudget autoload must exist in scene tree.")
	if is_instance_valid(budget):
		budget.call(&"clear_all")
		await get_tree().process_frame
		await get_tree().process_frame
		var raw_active: Variant = budget.call(&"get_active_count")
		var active_after_clear: int = raw_active if raw_active is int else -1
		assert_eq(active_after_clear, 0, "DebrisBudget must have 0 active bodies after clear.")

	var lingering_debris: int = 0
	for sibling: Node in get_children():
		if sibling is WallDebris:
			lingering_debris += 1
	assert_eq(lingering_debris, 0, "Cleanup must leave zero lingering WallDebris orphans.")


## Validates headless loading and expected node composition of test_destructible_wall.tscn.
func test_destructible_wall_level_scene_loads() -> void:
	var packed: PackedScene = ResourceLoader.load(TEST_LEVEL_PATH) as PackedScene
	assert_not_null(packed, "levels/test_destructible_wall.tscn must load without errors.")
	if not is_instance_valid(packed):
		return

	var level_root: Node = packed.instantiate()
	assert_not_null(level_root, "test_destructible_wall.tscn must instantiate cleanly.")
	if not is_instance_valid(level_root):
		return
	add_child_autoqfree(level_root)
	await get_tree().process_frame

	var player_count: int = 0
	var panel_count: int = 0
	var box_count: int = 0
	var revolver_count: int = 0

	var stack: Array[Node] = [level_root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is Player:
			player_count += 1
		elif current is DestructibleWallPanel:
			panel_count += 1
		elif current is HeavyPickableBox:
			box_count += 1
		elif current is Revolver:
			revolver_count += 1
		for child: Node in current.get_children():
			stack.append(child)

	assert_gte(player_count, 1, "Test level must include a Player.")
	assert_gte(panel_count, 3, "Test level must include 3 DestructibleWallPanel instances.")
	assert_gte(box_count, 1, "Test level must include a HeavyPickableBox.")
	assert_gte(revolver_count, 1, "Test level must include a Revolver.")


## Builds a lightweight synthetic WallPanelData graph for BFS unit testing.
func _build_synthetic_panel(
	count: int, adj_rows: Array[PackedInt32Array], anchors: int
) -> WallPanelData:
	var data: WallPanelData = WallPanelData.new()
	data.chunk_count = count
	data.adjacency = adj_rows
	data.anchor_mask = anchors
	var centroids: PackedVector3Array = PackedVector3Array()
	var volumes: PackedFloat32Array = PackedFloat32Array()
	var names: PackedStringArray = PackedStringArray()
	for i: int in range(count):
		centroids.append(Vector3(float(i), 1.0, 0.0))
		volumes.append(0.1)
		names.append("chunk_%03d" % i)
	data.chunk_centroids = centroids
	data.chunk_volumes = volumes
	data.chunk_names = names
	return data


## Extracts a PackedVector4Array from a PackedVector4Array or Array shader uniform Variant.
func _extract_vec4_array(raw_val: Variant) -> PackedVector4Array:
	if raw_val is PackedVector4Array:
		var packed_arr: PackedVector4Array = raw_val
		return packed_arr
	var out_arr: PackedVector4Array = PackedVector4Array()
	if raw_val is Array:
		var generic_arr: Array = raw_val
		for item: Variant in generic_arr:
			if item is Vector4:
				var vec: Vector4 = item
				out_arr.append(vec)
	return out_arr
