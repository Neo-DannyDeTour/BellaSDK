## Headless CLI runner baking the 2x3m destructible wall panel data resource.
class_name BakeWallPanel
extends SceneTree

## Base directory containing wall panel model assets.
const MODELS_DIR: String = "res://interactables/destructible_wall/models/"

## Source fractured wall panel GLB asset path.
const SOURCE_GLB_PATH: String = MODELS_DIR + "wall_panel_2x3.glb"

## Destination baked [WallPanelData] resource path.
const OUTPUT_DATA_PATH: String = MODELS_DIR + "wall_panel_2x3_data.tres"


## Executes [method WallPanelBaker.bake_from_glb], verifies the saved output, and exits.
func _initialize() -> void:
	var data: WallPanelData = WallPanelBaker.bake_from_glb(SOURCE_GLB_PATH, OUTPUT_DATA_PATH)
	if data == null or not data.is_valid():
		push_error("BakeWallPanel: Baking failed or produced invalid WallPanelData.")
		quit(1)
		return

	var reloaded: WallPanelData = (
		ResourceLoader.load(OUTPUT_DATA_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as WallPanelData
	)
	if reloaded == null or not reloaded.is_valid():
		push_error("BakeWallPanel: Failed to reload valid WallPanelData from ", OUTPUT_DATA_PATH)
		quit(1)
		return

	if not _verify_baked_data(reloaded):
		quit(1)
		return

	quit(0)


## Verifies connectivity, rebar collision shape, adjacency, and CUSTOM0 IDs on [param data].
func _verify_baked_data(data: WallPanelData) -> bool:
	if data.rebar_mesh == null or data.rebar_shape == null:
		push_error("BakeWallPanel: Missing rebar_mesh or rebar_shape.")
		return false

	var all_mask: int = WallPanelData.all_chunks_mask(data.chunk_count)
	var supported: int = data.find_supported_mask(0)
	if supported != all_mask:
		push_error(
			"BakeWallPanel: Disconnected chunks detected. supported=",
			supported,
			" expected=",
			all_mask
		)
		return false

	for i: int in range(data.chunk_count):
		var c_mesh: ArrayMesh = data.chunk_meshes[i]
		if c_mesh.get_surface_count() != 2:
			push_error("BakeWallPanel: Chunk ", i, " does not have 2 surfaces.")
			return false
		for cs_idx: int in range(2):
			if (c_mesh.surface_get_format(cs_idx) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0:
				push_error("BakeWallPanel: Chunk mesh ", i, " unexpectedly has CUSTOM0.")
				return false
		var neighbors: PackedInt32Array = data.adjacency[i]
		var prev_nb: int = -1
		for nb: int in neighbors:
			if nb <= prev_nb or nb >= data.chunk_count or nb == i:
				push_error("BakeWallPanel: Invalid/unsorted adjacency for chunk ", i)
				return false
			if not (i in data.adjacency[nb]):
				push_error("BakeWallPanel: Asymmetric adjacency between ", i, " and ", nb)
				return false
			prev_nb = nb

	var seen_mask: int = 0
	for surf_idx: int in range(2):
		var fmt: int = data.merged_mesh.surface_get_format(surf_idx)
		if (fmt & Mesh.ARRAY_FORMAT_CUSTOM0) == 0:
			push_error("BakeWallPanel: Missing ARRAY_FORMAT_CUSTOM0 on surface ", surf_idx)
			return false
		var arrays: Array = data.merged_mesh.surface_get_arrays(surf_idx)
		var raw_custom: Variant = (
			arrays[Mesh.ARRAY_CUSTOM0] if arrays.size() > Mesh.ARRAY_CUSTOM0 else null
		)
		if not (raw_custom is PackedFloat32Array):
			push_error("BakeWallPanel: CUSTOM0 is not PackedFloat32Array on surface ", surf_idx)
			return false
		var custom_arr: PackedFloat32Array = raw_custom
		if custom_arr.is_empty():
			push_error("BakeWallPanel: CUSTOM0 is empty on surface ", surf_idx)
			return false
		for cid_val: float in custom_arr:
			var cid: int = roundi(cid_val)
			if cid < 0 or cid >= data.chunk_count or not is_equal_approx(cid_val, float(cid)):
				push_error("BakeWallPanel: Invalid CUSTOM0 chunk id ", cid_val)
				return false
			seen_mask |= WallPanelData.bit_for_chunk(cid)

	if seen_mask != all_mask:
		push_error("BakeWallPanel: Not all chunks represented in merged_mesh CUSTOM0.")
		return false

	print("BakeWallPanel: Verification passed for ", OUTPUT_DATA_PATH)
	return true
