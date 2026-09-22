## Procedural multi-floor generator generating rooms, walls, and CSG stairs.
class_name ProceduralBlockout
extends Node3D

## Emitted by [method generate_level] when layout is built with [param grid].
signal generation_completed(grid: Dictionary)

## Layout voxel types representing rooms, corridors, stairs, and walls.
enum CellType {
	EMPTY = 0,
	ROOM = 1,
	CORRIDOR = 2,
	STAIRS = 3,
	WALL = 4,
}

## Structural geometry templates available for procedural room footprints.
enum RoomShape {
	RECTANGLE = 0,
	L_SHAPE = 1,
	T_SHAPE = 2,
	CROSS = 3,
}

@export_group("GridMap Nodes")
## Target [GridMap] node populated with procedural floor and wall tiles.
@export var grid_map: GridMap

## Player character node repositioned to the initial room floor.
@export var player: CharacterBody3D

@export_group("MeshLibrary Indices")
## Item ID in [MeshLibrary] for [constant CellType.ROOM] floor tiles.
@export var room_tile_id: int = 0

## Item ID in [MeshLibrary] for [constant CellType.CORRIDOR] floor tiles.
@export var corridor_tile_id: int = 1

## Item ID in [MeshLibrary] for [constant CellType.WALL] boundary blocks.
@export var wall_tile_id: int = 3

@export_group("Floor Layout")
## Total number of vertical floor levels generated along the Y axis.
@export var floor_count: int = 3

## Grid cell height spacing between adjacent floor levels.
@export var floor_height_cells: int = 3

## Height in grid cells for perimeter walls enclosing rooms and corridors.
@export var wall_height: int = 3

## Horizontal dimensions in cells defining the boundary on each floor level.
@export var floor_size: Vector2i = Vector2i(48, 48)

## Target count of distinct room shapes attempted on each floor level.
@export var rooms_per_floor: int = 6

## Minimum width and depth in cells for room footprint calculations.
@export var min_room_size: int = 4

## Maximum width and depth in cells for room footprint calculations.
@export var max_room_size: int = 10

## Physical world scale in meters representing one grid cell unit.
@export var cell_size: float = 2.0

## Length in grid cells for vertical stairwells bridging floors.
@export var stair_length_cells: int = 3

## Internal map of [Vector3i] grid coordinates to [constant CellType] values.
var _grid: Dictionary = {}

## Tracks placed room cell arrays grouped by their vertical floor index.
var _rooms_by_floor: Array[Array] = []

## Container node hosting spawned [ProceduralStairsCSG] instances.
var _stairs_container: Node3D


## Initializes generator references, cleans prior children, and builds level.
func _ready() -> void:
	print("ProceduralBlockout: Initializing generator.")
	if not is_instance_valid(grid_map):
		grid_map = get_node_or_null("GridMap") as GridMap
	if not is_instance_valid(player):
		player = get_node_or_null("Player") as CharacterBody3D

	_ensure_stairs_container()
	generate_level()


## Executes full generation pipeline across floors and emits signal.
func generate_level() -> void:
	print("ProceduralBlockout: Starting level generation pipeline.")
	_grid.clear()
	_rooms_by_floor.clear()
	_clear_stairs()

	for floor_idx: int in range(floor_count):
		print("ProceduralBlockout: Generating floor index %d." % floor_idx)
		var rooms: Array[Array] = _generate_floor_rooms(floor_idx)
		_rooms_by_floor.append(rooms)
		_connect_floor_rooms(rooms, floor_idx)

	for floor_idx: int in range(floor_count - 1):
		print("ProceduralBlockout: Linking floor %d to %d." % [floor_idx, floor_idx + 1])
		_connect_floors(_rooms_by_floor[floor_idx], _rooms_by_floor[floor_idx + 1], floor_idx)

	_generate_walls()
	_build_gridmap()
	_place_player_at_start()

	print("ProceduralBlockout: Generation finished with %d cells." % _grid.size())
	generation_completed.emit(_grid)


## Spawns randomized shaped rooms for a specific [param floor_index].
func _generate_floor_rooms(floor_index: int) -> Array[Array]:
	print("ProceduralBlockout: Generating room layouts on floor %d." % floor_index)
	var placed_rooms: Array[Array] = []
	var max_attempts: int = rooms_per_floor * 10
	var grid_y: int = floor_index * floor_height_cells

	for attempt: int in range(max_attempts):
		if placed_rooms.size() >= rooms_per_floor:
			break

		var shape_type: RoomShape = randi() % 4 as RoomShape
		var rw: int = randi_range(min_room_size, max_room_size)
		var rd: int = randi_range(min_room_size, max_room_size)
		var rx: int = randi_range(3, floor_size.x - rw - stair_length_cells - 3)
		var rz: int = randi_range(3, floor_size.y - rd - 3)

		var origin: Vector3i = Vector3i(rx, grid_y, rz)
		var candidate_cells: Array[Vector3i] = _create_room_cells(
			origin, Vector2i(rw, rd), shape_type
		)

		if _can_place_room(candidate_cells):
			for cell: Vector3i in candidate_cells:
				_grid[cell] = CellType.ROOM
			placed_rooms.append(candidate_cells)

	return placed_rooms


## Assembles cell offsets for [param shape] around [param origin].
func _create_room_cells(origin: Vector3i, size: Vector2i, shape: RoomShape) -> Array[Vector3i]:
	print("ProceduralBlockout: Assembling cells for room shape %d." % shape)
	var cells: Array[Vector3i] = []

	match shape:
		RoomShape.RECTANGLE:
			for x: int in range(size.x):
				for z: int in range(size.y):
					cells.append(origin + Vector3i(x, 0, z))

		RoomShape.L_SHAPE:
			var split_x: int = maxi(2, floori(float(size.x) / 2.0))
			var split_z: int = maxi(2, floori(float(size.y) / 2.0))
			for x: int in range(size.x):
				for z: int in range(size.y):
					if x < split_x or z < split_z:
						cells.append(origin + Vector3i(x, 0, z))

		RoomShape.T_SHAPE:
			var bar_depth: int = maxi(2, floori(float(size.y) / 3.0))
			var stem_w: int = maxi(2, floori(float(size.x) / 3.0))
			var stem_start: int = floori(float(size.x - stem_w) / 2.0)
			for x: int in range(size.x):
				for z: int in range(size.y):
					var in_bar: bool = z < bar_depth
					var in_stem: bool = x >= stem_start and x < stem_start + stem_w
					if in_bar or in_stem:
						cells.append(origin + Vector3i(x, 0, z))

		RoomShape.CROSS:
			var arm_x: int = maxi(2, floori(float(size.x) / 3.0))
			var arm_z: int = maxi(2, floori(float(size.y) / 3.0))
			var start_x: int = floori(float(size.x - arm_x) / 2.0)
			var start_z: int = floori(float(size.y - arm_z) / 2.0)
			for x: int in range(size.x):
				for z: int in range(size.y):
					var in_horiz: bool = z >= start_z and z < start_z + arm_z
					var in_vert: bool = x >= start_x and x < start_x + arm_x
					if in_horiz or in_vert:
						cells.append(origin + Vector3i(x, 0, z))

	return cells


## Evaluates if [param cells] can fit without overlapping occupied grid space.
func _can_place_room(cells: Array[Vector3i]) -> bool:
	print("ProceduralBlockout: Verifying bounds clearance for candidate room.")
	for cell: Vector3i in cells:
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				var neighbor: Vector3i = cell + Vector3i(dx, 0, dz)
				if _grid.has(neighbor):
					return false
	return true


## Connects [param start] and [param end] points with corridor cells.
func _carve_corridor(start: Vector3i, end: Vector3i) -> void:
	print("ProceduralBlockout: Carving corridor from %s to %s." % [start, end])
	var curr: Vector3i = start
	while curr.x != end.x:
		curr.x += 1 if end.x > curr.x else -1
		if not _grid.has(curr):
			_grid[curr] = CellType.CORRIDOR

	while curr.z != end.z:
		curr.z += 1 if end.z > curr.z else -1
		if not _grid.has(curr):
			_grid[curr] = CellType.CORRIDOR


## Connects adjacent rooms on [param floor_index] via carved corridors.
func _connect_floor_rooms(floor_rooms: Array[Array], floor_index: int) -> void:
	print("ProceduralBlockout: Linking rooms on floor %d." % floor_index)
	if floor_rooms.size() < 2:
		return

	for i: int in range(floor_rooms.size()):
		var room_a: Array = floor_rooms[i]
		var room_b: Array = floor_rooms[(i + 1) % floor_rooms.size()]
		var center_a: Vector3i = room_a[floori(float(room_a.size()) / 2.0)]
		var center_b: Vector3i = room_b[floori(float(room_b.size()) / 2.0)]
		_carve_corridor(center_a, center_b)


## Spawns [ProceduralStairsCSG] with flat landings and vertical clearance.
func _connect_floors(
	floor_a_rooms: Array[Array], floor_b_rooms: Array[Array], floor_index: int
) -> void:
	print("ProceduralBlockout: Connecting stairwell for floor %d." % floor_index)
	if floor_a_rooms.is_empty() or floor_b_rooms.is_empty():
		return

	var lower_room: Array = floor_a_rooms[floor_a_rooms.size() - 1]
	var upper_room: Array = floor_b_rooms[0]

	var lower_y: int = floor_index * floor_height_cells
	var lower_room_center: Vector3i = lower_room[floori(float(lower_room.size()) / 2.0)]
	var upper_room_center: Vector3i = upper_room[floori(float(upper_room.size()) / 2.0)]

	var stair_run_start: Vector3i = Vector3i(lower_room_center.x + 2, lower_y, lower_room_center.z)

	var bottom_landing: Vector3i = stair_run_start + Vector3i(-1, 0, 0)
	_grid[bottom_landing] = CellType.CORRIDOR
	_carve_corridor(lower_room_center, bottom_landing)

	for dx: int in range(stair_length_cells):
		for dy: int in range(floor_height_cells + wall_height + 1):
			var shaft_cell: Vector3i = stair_run_start + Vector3i(dx, dy, 0)
			_grid[shaft_cell] = CellType.STAIRS

	var top_landing: Vector3i = (
		stair_run_start + Vector3i(stair_length_cells, floor_height_cells, 0)
	)
	_grid[top_landing] = CellType.CORRIDOR
	for dy: int in range(1, wall_height + 1):
		_grid[top_landing + Vector3i(0, dy, 0)] = CellType.EMPTY

	_carve_corridor(top_landing, upper_room_center)
	_spawn_csg_stairs(stair_run_start)


## Instantiates a [ProceduralStairsCSG] node aligned to the stair run cells.
func _spawn_csg_stairs(start_coord: Vector3i) -> void:
	print("ProceduralBlockout: Spawning CSG stairs at %s." % start_coord)
	var stairs: ProceduralStairsCSG = ProceduralStairsCSG.new()
	stairs.name = "Stairs_%d_%d" % [start_coord.x, start_coord.y]
	stairs.total_height = float(floor_height_cells) * cell_size
	stairs.total_length = float(stair_length_cells) * cell_size
	stairs.stair_width = cell_size
	stairs.step_count = maxi(6, int(stairs.total_height / 0.25))
	stairs.fill_to_floor = true
	stairs.generate_smooth_ramp = true
	stairs.collision_layer = 1
	stairs.collision_mask = 0

	var origin_world: Vector3 = grid_to_world(start_coord)
	stairs.position = origin_world + Vector3(0.0, 0.0, -cell_size * 0.5)
	_stairs_container.add_child(stairs)


## Detects perimeter edges of rooms and corridors, filling them with wall cells.
func _generate_walls() -> void:
	print("ProceduralBlockout: Calculating boundary wall cells.")
	var wall_positions: Array[Vector3i] = []
	var offsets: Array[Vector3i] = [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
	]

	for cell: Vector3i in _grid:
		var type: int = _grid[cell]
		if type != CellType.ROOM and type != CellType.CORRIDOR:
			continue

		for offset: Vector3i in offsets:
			var neighbor: Vector3i = cell + offset
			if not _grid.has(neighbor):
				for h: int in range(wall_height):
					var wall_cell: Vector3i = neighbor + Vector3i(0, h, 0)
					if not _grid.has(wall_cell):
						wall_positions.append(wall_cell)

	for wall_cell: Vector3i in wall_positions:
		_grid[wall_cell] = CellType.WALL


## Populates [member grid_map] items according to internal cell layout.
func _build_gridmap() -> void:
	print("ProceduralBlockout: Writing layout tiles into GridMap.")
	if not is_instance_valid(grid_map):
		print("ProceduralBlockout: GridMap reference is invalid.")
		return

	grid_map.clear()

	for coord: Vector3i in _grid:
		var cell_type: int = _grid[coord]
		var tile_id: int = -1

		match cell_type:
			CellType.ROOM:
				tile_id = room_tile_id
			CellType.CORRIDOR:
				tile_id = corridor_tile_id
			CellType.WALL:
				tile_id = wall_tile_id

		if tile_id >= 0:
			grid_map.set_cell_item(coord, tile_id)


## Teleports [member player] onto the first available floor room cell.
func _place_player_at_start() -> void:
	print("ProceduralBlockout: Aligning player spawn location.")
	if not is_instance_valid(player) or not is_instance_valid(grid_map):
		return

	for coord: Vector3i in _grid:
		if _grid[coord] == CellType.ROOM and coord.y == 0:
			var spawn_pos: Vector3 = grid_map.map_to_local(coord)
			spawn_pos.y += 1.0
			player.global_position = spawn_pos
			print("ProceduralBlockout: Player placed at %s." % spawn_pos)
			break


## Ensures the container node for procedural stairs exists in scene.
func _ensure_stairs_container() -> void:
	print("ProceduralBlockout: Verifying stairs container node.")
	if not is_instance_valid(_stairs_container):
		_stairs_container = get_node_or_null("StairsContainer") as Node3D
		if not _stairs_container:
			_stairs_container = Node3D.new()
			_stairs_container.name = "StairsContainer"
			add_child(_stairs_container)


## Clears existing stair instances prior to layout regeneration.
func _clear_stairs() -> void:
	print("ProceduralBlockout: Removing previous stair instances.")
	_ensure_stairs_container()
	for child: Node in _stairs_container.get_children():
		child.queue_free()


## Retrieves the [constant CellType] at specified [param coord].
func get_cell(coord: Vector3i) -> int:
	print("ProceduralBlockout: Fetching cell data at %s." % coord)
	return _grid.get(coord, CellType.EMPTY)


## Converts [param grid_pos] cell coordinates to world space [Vector3].
func grid_to_world(grid_pos: Vector3i) -> Vector3:
	print("ProceduralBlockout: Converting %s to world coordinates." % grid_pos)
	return Vector3(
		float(grid_pos.x) * cell_size, float(grid_pos.y) * cell_size, float(grid_pos.z) * cell_size
	)
