@tool
## Pre-baked destructible wall panel geometry, adjacency graph, and chunk collision shapes.
class_name WallPanelData
extends Resource

## Maximum number of chunks supported by the 64-bit visibility bitmask.
const MAX_CHUNKS: int = 64

## Full local bounding box dimensions of the intact wall panel in meters.
@export var panel_size: Vector3 = Vector3(2.0, 3.0, 0.25)

## Combined concrete mesh with outer (0) and inner (1) surfaces and chunk IDs in CUSTOM0.
@export var merged_mesh: ArrayMesh = null

## Exposed internal steel reinforcement bar mesh.
@export var rebar_mesh: ArrayMesh = null

## Static trimesh collision shape generated from [member rebar_mesh].
@export var rebar_shape: ConcavePolygonShape3D = null

## Total number of destructible concrete chunks stored in this panel resource.
@export var chunk_count: int = 0

## Deterministically sorted node names for each concrete chunk.
@export var chunk_names: PackedStringArray = PackedStringArray()

## Volume-weighted local centroids (true centers of mass) for each chunk.
@export var chunk_centroids: PackedVector3Array = PackedVector3Array()

## Positive volume in cubic meters for each concrete chunk.
@export var chunk_volumes: PackedFloat32Array = PackedFloat32Array()

## Centroid-centered convex collision shapes indexed by chunk ID.
@export var chunk_shapes: Array[ConvexPolygonShape3D] = []

## Centroid-centered two-surface debris meshes indexed by chunk ID.
@export var chunk_meshes: Array[ArrayMesh] = []

## Symmetric, ascending-sorted neighbor index arrays for each chunk.
@export var adjacency: Array[PackedInt32Array] = []

## 64-bit bitmask identifying structurally anchored chunks.
@export var anchor_mask: int = 0


## Returns a bitmask with the lowest [param count] chunk bits set.
static func all_chunks_mask(count: int) -> int:
	if count <= 0:
		return 0
	if count >= MAX_CHUNKS:
		return -1
	if count == 63:
		return 0x7FFFFFFFFFFFFFFF
	return (1 << count) - 1


## Returns the single-bit 64-bit mask for [param index], or 0 if out of bounds.
static func bit_for_chunk(index: int) -> int:
	if index < 0 or index >= MAX_CHUNKS:
		return 0
	return 1 << index


## Returns true when [param index] is valid and its bit is set in [param mask].
static func is_chunk_set(mask: int, index: int) -> bool:
	if index < 0 or index >= MAX_CHUNKS:
		return false
	return (mask & (1 << index)) != 0


## Returns the unsigned lower 32 bits of [param mask] for shader uniform upload.
static func mask_low_u32(mask: int) -> int:
	return mask & 0xFFFFFFFF


## Returns the unsigned upper 32 bits of [param mask] without sign extension.
static func mask_high_u32(mask: int) -> int:
	return (mask >> 32) & 0xFFFFFFFF


## Validates structural integrity and array alignment of this baked panel resource.
func is_valid() -> bool:
	if chunk_count <= 0 or chunk_count > MAX_CHUNKS:
		return false
	if panel_size.x <= 0.0 or panel_size.y <= 0.0 or panel_size.z <= 0.0:
		return false
	if merged_mesh == null or merged_mesh.get_surface_count() < 2:
		return false
	if rebar_mesh != null and rebar_shape == null:
		return false
	if chunk_names.size() != chunk_count:
		return false
	if chunk_centroids.size() != chunk_count:
		return false
	if chunk_volumes.size() != chunk_count:
		return false
	if chunk_shapes.size() != chunk_count:
		return false
	if chunk_meshes.size() != chunk_count:
		return false
	if adjacency.size() != chunk_count:
		return false
	for i: int in range(chunk_count):
		if chunk_shapes[i] == null or chunk_meshes[i] == null:
			return false
	return true


## Computes the bitmask of remaining chunks reachable from remaining anchors.
func find_supported_mask(removed_mask: int) -> int:
	var count: int = mini(chunk_count, MAX_CHUNKS)
	if count <= 0 or adjacency.size() < count:
		return 0
	var remaining: int = all_chunks_mask(count) & (~removed_mask)
	var supported: int = anchor_mask & remaining
	if supported == 0:
		return 0

	var queue: PackedInt32Array = PackedInt32Array()
	for i: int in range(count):
		if (supported & (1 << i)) != 0:
			queue.append(i)

	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		var neighbors: PackedInt32Array = adjacency[current]
		for neighbor: int in neighbors:
			if neighbor < 0 or neighbor >= count:
				continue
			var neighbor_bit: int = 1 << neighbor
			if (remaining & neighbor_bit) != 0 and (supported & neighbor_bit) == 0:
				supported |= neighbor_bit
				queue.append(neighbor)
	return supported


## Finds connected components of unsupported remaining chunks, each sorted ascending.
func find_disconnected_islands(removed_mask: int) -> Array[PackedInt32Array]:
	var islands: Array[PackedInt32Array] = []
	var count: int = mini(chunk_count, MAX_CHUNKS)
	if count <= 0 or adjacency.size() < count:
		return islands

	var remaining: int = all_chunks_mask(count) & (~removed_mask)
	var supported: int = find_supported_mask(removed_mask)
	var unsupported: int = remaining & (~supported)
	if unsupported == 0:
		return islands

	var visited: int = 0
	for start: int in range(count):
		var start_bit: int = 1 << start
		if (unsupported & start_bit) == 0 or (visited & start_bit) != 0:
			continue

		var component: PackedInt32Array = PackedInt32Array()
		visited |= start_bit
		component.append(start)

		var head: int = 0
		while head < component.size():
			var current: int = component[head]
			head += 1
			var neighbors: PackedInt32Array = adjacency[current]
			for neighbor: int in neighbors:
				if neighbor < 0 or neighbor >= count:
					continue
				var neighbor_bit: int = 1 << neighbor
				if (unsupported & neighbor_bit) != 0 and (visited & neighbor_bit) == 0:
					visited |= neighbor_bit
					component.append(neighbor)

		component.sort()
		islands.append(component)

	return islands


## Finds the remaining chunk index closest to [param local_pos], or -1 if none remain.
func find_nearest_remaining_chunk(local_pos: Vector3, removed_mask: int) -> int:
	var count: int = mini(chunk_count, mini(chunk_centroids.size(), MAX_CHUNKS))
	var remaining: int = all_chunks_mask(count) & (~removed_mask)
	if remaining == 0:
		return -1

	var best_idx: int = -1
	var best_dist_sq: float = INF
	for i: int in range(count):
		if (remaining & (1 << i)) == 0:
			continue
		var dist_sq: float = chunk_centroids[i].distance_squared_to(local_pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_idx = i
	return best_idx


## Returns remaining chunk indices whose centroids lie within [param radius] of center.
func find_chunks_in_radius(
	local_center: Vector3, radius: float, removed_mask: int
) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if radius < 0.0:
		return result
	var count: int = mini(chunk_count, mini(chunk_centroids.size(), MAX_CHUNKS))
	var remaining: int = all_chunks_mask(count) & (~removed_mask)
	if remaining == 0:
		return result

	var radius_sq: float = radius * radius
	for i: int in range(count):
		if (remaining & (1 << i)) == 0:
			continue
		if chunk_centroids[i].distance_squared_to(local_center) <= radius_sq:
			result.append(i)
	return result
