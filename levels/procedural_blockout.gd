## Procedural multi-floor generator generating rooms, walls, roofs, and parkour structures.
class_name ProceduralBlockout
extends Node3D

## Emitted by [method generate_level] when layout is built with [param grid].
signal generation_completed(grid: Dictionary)

## Layout voxel types representing rooms, corridors, stairs, walls, and structures.
enum CellType {
	EMPTY = 0,
	ROOM = 1,
	CORRIDOR = 2,
	STAIRS = 3,
	WALL = 4,
	LANDING_PAD = 5,
	CROUCH_DUCT = 6,
	VAULT_OBSTACLE = 7,
}

## Structural geometry templates available for procedural room footprints.
enum RoomShape {
	RECTANGLE = 0,
	L_SHAPE = 1,
	T_SHAPE = 2,
	CROSS = 3,
	RADIAL = 4,
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

@export_group("Architectural Features")
## Toggles generation of solid roofs and ceilings above interior spaces.
@export var enable_roofs_and_ceilings: bool = true

## Ratio of radial/octagonal rooms generated versus standard shapes (0.0 to 1.0).
@export_range(0.0, 1.0, 0.05) var radial_room_ratio: float = 0.25

## Enables nested "room within a room" spatial structures in large halls.
@export var enable_nested_rooms: bool = true

## Enables window cutouts and skylight openings in walls and roofs.
@export var enable_fenestration: bool = true

@export_group("Parkour Traversal Metrics")
## Enables placement of parkour traversal elements (vaults, monkey bars, etc).
@export var enable_parkour_elements: bool = true

## Maximum horizontal sprint-jump gap distance in meters.
@export var sprint_jump_max_distance: float = 6.0

## Height clearance in meters for crouch crawlspaces and ductwork.
@export var crouch_clearance_height: float = 1.1

## Height range in meters for vaultable half-height obstacles and sills.
@export var vault_obstacle_height: float = 1.0

## Internal map of [Vector3i] grid coordinates to [constant CellType] values.
var _grid: Dictionary = {}

## Tracks placed room cell arrays grouped by their vertical floor index.
var _rooms_by_floor: Array[Array] = []

## Container node hosting spawned [ProceduralStairsCSG] instances.
var _stairs_container: Node3D

## Container node hosting generated ceiling and roof geometry.
var _ceiling_container: Node3D

## Container node hosting parkour geometry and [MonkeyBarVolume] nodes.
var _parkour_container: Node3D

## Container node hosting nested room inner volumes.
var _nested_container: Node3D


## Initializes generator references, cleans prior children, and builds level.
func _ready() -> void:
	print("ProceduralBlockout: Initializing generator.")
	if not is_instance_valid(grid_map):
		grid_map = get_node_or_null("GridMap") as GridMap
	if not is_instance_valid(player):
		player = get_node_or_null("Player") as CharacterBody3D

	_ensure_containers()
	generate_level()


## Executes full generation pipeline across floors and emits signal.
func generate_level() -> void:
	print("ProceduralBlockout: Starting level generation pipeline.")
	_grid.clear()
	_rooms_by_floor.clear()
	_clear_generated_containers()

	for floor_idx: int in range(floor_count):
		print("ProceduralBlockout: Generating floor index %d." % floor_idx)
		var rooms: Array[Array] = _generate_floor_rooms(floor_idx)
		_rooms_by_floor.append(rooms)

		if enable_nested_rooms:
			_generate_nested_rooms_for_floor(rooms, floor_idx)

		_connect_floor_rooms(rooms, floor_idx)

	for floor_idx: int in range(floor_count - 1):
		print("ProceduralBlockout: Linking floor %d to %d." % [floor_idx, floor_idx + 1])
		_connect_floors(_rooms_by_floor[floor_idx], _rooms_by_floor[floor_idx + 1], floor_idx)

	_generate_walls()

	if enable_roofs_and_ceilings:
		_generate_ceilings_and_roofs()

	if enable_parkour_elements:
		_generate_parkour_elements()

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

		var shape_type: RoomShape = _select_room_shape()
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


## Selects a [enum RoomShape] considering Inspector radial preferences.
func _select_room_shape() -> RoomShape:
	print("ProceduralBlockout: Selecting room shape with radial ratio.")
	if randf() < radial_room_ratio:
		return RoomShape.RADIAL
	var standard_shapes: Array[RoomShape] = [
		RoomShape.RECTANGLE, RoomShape.L_SHAPE, RoomShape.T_SHAPE, RoomShape.CROSS
	]
	return standard_shapes[randi() % standard_shapes.size()]


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

		RoomShape.RADIAL:
			var radius: float = float(mini(size.x, size.y)) * 0.5
			var center_x: float = float(origin.x) + float(size.x) * 0.5
			var center_z: float = float(origin.z) + float(size.y) * 0.5
			for x: int in range(size.x):
				for z: int in range(size.y):
					var px: float = float(origin.x + x) + 0.5
					var pz: float = float(origin.z + z) + 0.5
					var dx: float = px - center_x
					var dz: float = pz - center_z
					var dist_sq: float = dx * dx + dz * dz
					if dist_sq <= radius * radius:
						cells.append(origin + Vector3i(x, 0, z))

	return cells


## Generates secondary inner freestanding rooms ("room within a room").
func _generate_nested_rooms_for_floor(rooms: Array[Array], floor_idx: int) -> void:
	print("ProceduralBlockout: Generating nested inner rooms on floor %d." % floor_idx)
	for room_cells in rooms:
		if room_cells.size() < 25:
			continue

		var min_x: int = 99999
		var max_x: int = -99999
		var min_z: int = 99999
		var max_z: int = -99999
		var grid_y: int = floor_idx * floor_height_cells

		for cell: Vector3i in room_cells:
			min_x = mini(min_x, cell.x)
			max_x = maxi(max_x, cell.x)
			min_z = mini(min_z, cell.z)
			max_z = maxi(max_z, cell.z)

		var room_w: int = max_x - min_x + 1
		var room_d: int = max_z - min_z + 1

		if room_w >= 6 and room_d >= 6:
			var inner_min_x: int = min_x + 2
			var inner_max_x: int = max_x - 2
			var inner_min_z: int = min_z + 2
			var inner_max_z: int = max_z - 2

			_spawn_nested_inner_box(
				inner_min_x, inner_max_x, inner_min_z, inner_max_z, grid_y
			)


## Instantiates CSG geometry for an inner freestanding room booth/pavilion.
func _spawn_nested_inner_box(
	min_x: int, max_x: int, min_z: int, max_z: int, grid_y: int
) -> void:
	print("ProceduralBlockout: Spawning nested pavilion inner room structure.")
	_ensure_containers()

	var start_world: Vector3 = grid_to_world(Vector3i(min_x, grid_y, min_z))
	var end_world: Vector3 = grid_to_world(Vector3i(max_x + 1, grid_y, max_z + 1))
	var box_size: Vector3 = Vector3(
		end_world.x - start_world.x,
		float(wall_height - 1) * cell_size,
		end_world.z - start_world.z
	)
	var box_center: Vector3 = (
		start_world + Vector3(box_size.x * 0.5, box_size.y * 0.5, box_size.z * 0.5)
	)

	var outer_box: CSGBox3D = CSGBox3D.new()
	outer_box.size = box_size
	outer_box.position = box_center
	outer_box.use_collision = true
	outer_box.collision_layer = 1
	outer_box.collision_mask = 0

	var inner_box: CSGBox3D = CSGBox3D.new()
	inner_box.size = box_size - Vector3(0.4, 0.0, 0.4)
	inner_box.operation = CSGShape3D.OPERATION_SUBTRACTION

	var doorway: CSGBox3D = CSGBox3D.new()
	doorway.size = Vector3(1.2, 2.2, 0.8)
	doorway.position = Vector3(0.0, -box_size.y * 0.5 + 1.1, box_size.z * 0.5)
	doorway.operation = CSGShape3D.OPERATION_SUBTRACTION

	outer_box.add_child(inner_box)
	outer_box.add_child(doorway)
	_nested_container.add_child(outer_box)


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


## Generates solid roof and ceiling geometry above all interior room cells.
func _generate_ceilings_and_roofs() -> void:
	print("ProceduralBlockout: Building room roof and ceiling enclosure geometry.")
	_ensure_containers()

	var ceiling_cells: Dictionary = {}
	for cell: Vector3i in _grid:
		var type: int = _grid[cell]
		if type == CellType.ROOM or type == CellType.CORRIDOR:
			var roof_coord: Vector3i = cell + Vector3i(0, wall_height, 0)
			ceiling_cells[roof_coord] = true

	for roof_coord: Vector3i in ceiling_cells:
		if enable_fenestration and randf() < 0.08:
			_spawn_skylight_opening(roof_coord)
		else:
			_spawn_ceiling_tile(roof_coord)


## Spawns a solid CSG ceiling block for a roof coordinate.
func _spawn_ceiling_tile(coord: Vector3i) -> void:
	print("ProceduralBlockout: Spawning ceiling tile at %s." % coord)
	var tile: CSGBox3D = CSGBox3D.new()
	tile.size = Vector3(cell_size, 0.2, cell_size)
	var pos: Vector3 = grid_to_world(coord)
	pos.y -= 0.1
	tile.position = pos
	tile.use_collision = true
	tile.collision_layer = 1
	tile.collision_mask = 0
	_ceiling_container.add_child(tile)


## Spawns an angled skylight window framing cutout in the roof.
func _spawn_skylight_opening(coord: Vector3i) -> void:
	print("ProceduralBlockout: Spawning skylight cutout at %s." % coord)
	var skylight_frame: CSGBox3D = CSGBox3D.new()
	skylight_frame.size = Vector3(cell_size, 0.4, cell_size)
	var pos: Vector3 = grid_to_world(coord)
	skylight_frame.position = pos
	skylight_frame.use_collision = true
	skylight_frame.collision_layer = 1
	skylight_frame.collision_mask = 0

	var cutout: CSGBox3D = CSGBox3D.new()
	cutout.size = Vector3(cell_size * 0.7, 0.6, cell_size * 0.7)
	cutout.operation = CSGShape3D.OPERATION_SUBTRACTION
	skylight_frame.add_child(cutout)

	_ceiling_container.add_child(skylight_frame)


## Places parkour structures (crouch crawlspaces, vault sills, gaps, monkey bars).
func _generate_parkour_elements() -> void:
	print("ProceduralBlockout: Placing parkour traversal structures across level.")
	_ensure_containers()

	var room_centers: Array[Vector3i] = []
	for room_cells in _rooms_by_floor:
		for room in room_cells:
			if not room.is_empty():
				room_centers.append(room[floori(float(room.size()) / 2.0)])

	for i: int in range(room_centers.size()):
		var center: Vector3i = room_centers[i]

		if i % 4 == 0:
			_spawn_crouch_crawlspace(center)

		if i % 3 == 0:
			_spawn_vault_obstacle_and_sills(center)

		if i % 2 == 0:
			_spawn_monkey_bar_traversal(center)

		if i % 5 == 0 and i + 1 < room_centers.size():
			_spawn_sprint_jump_chasm(center, room_centers[i + 1])


## Spawns a low crouch crawlspace / duct structure with proper clearance.
func _spawn_crouch_crawlspace(origin: Vector3i) -> void:
	print("ProceduralBlockout: Spawning crouch duct at %s." % origin)
	var duct: CSGBox3D = CSGBox3D.new()
	duct.size = Vector3(cell_size * 2.0, crouch_clearance_height + 0.2, cell_size * 1.5)
	var world_pos: Vector3 = grid_to_world(origin) + Vector3(0.0, duct.size.y * 0.5, 0.0)
	duct.position = world_pos
	duct.use_collision = true
	duct.collision_layer = 1
	duct.collision_mask = 0

	var tunnel_cut: CSGBox3D = CSGBox3D.new()
	tunnel_cut.size = Vector3(cell_size * 2.2, crouch_clearance_height, cell_size * 1.1)
	tunnel_cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	duct.add_child(tunnel_cut)

	_parkour_container.add_child(duct)


## Spawns half-height vault obstacles (0.8m–1.4m) and window sills.
func _spawn_vault_obstacle_and_sills(origin: Vector3i) -> void:
	print("ProceduralBlockout: Spawning vault obstacle at %s." % origin)
	var wall: CSGBox3D = CSGBox3D.new()
	wall.size = Vector3(cell_size * 1.2, vault_obstacle_height, 0.3)
	var world_pos: Vector3 = (
		grid_to_world(origin) + Vector3(cell_size * 0.5, vault_obstacle_height * 0.5, 0.0)
	)
	wall.position = world_pos
	wall.use_collision = true
	wall.collision_layer = 1
	wall.collision_mask = 0
	_parkour_container.add_child(wall)


## Spawns a [MonkeyBarVolume] instance mounted near ceiling for overhead grab.
func _spawn_monkey_bar_traversal(origin: Vector3i) -> void:
	print("ProceduralBlockout: Spawning overhead monkey bar volume at %s." % origin)
	var monkey_bars: MonkeyBarVolume = MonkeyBarVolume.new()
	monkey_bars.name = "MonkeyBars_%d_%d" % [origin.x, origin.z]
	monkey_bars.size = Vector3(0.8, 0.3, cell_size * 2.5)
	var world_pos: Vector3 = (
		grid_to_world(origin) + Vector3(0.0, float(wall_height) * cell_size - 0.6, 0.0)
	)
	monkey_bars.position = world_pos
	_parkour_container.add_child(monkey_bars)


## Spawns a sprint-jump gap chasm with distinct visual and collision landing pads.
func _spawn_sprint_jump_chasm(start_coord: Vector3i, target_coord: Vector3i) -> void:
	print(
		"ProceduralBlockout: Spawning sprint jump chasm pad between %s and %s."
		% [start_coord, target_coord]
	)
	var landing_pad: CSGBox3D = CSGBox3D.new()
	landing_pad.size = Vector3(cell_size * 1.5, 0.3, cell_size * 1.5)

	var start_world: Vector3 = grid_to_world(start_coord)
	var target_world: Vector3 = grid_to_world(target_coord)
	var gap_dir: Vector3 = (target_world - start_world).normalized()
	var jump_dist: float = minf((target_world - start_world).length(), sprint_jump_max_distance)

	landing_pad.position = start_world + gap_dir * jump_dist + Vector3(0.0, 0.15, 0.0)
	landing_pad.use_collision = true
	landing_pad.collision_layer = 1
	landing_pad.collision_mask = 0

	_parkour_container.add_child(landing_pad)


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


## Ensures all container nodes exist for generated geometry.
func _ensure_containers() -> void:
	print("ProceduralBlockout: Verifying generator container nodes.")
	if not is_instance_valid(_stairs_container):
		_stairs_container = get_node_or_null("StairsContainer") as Node3D
		if not _stairs_container:
			_stairs_container = Node3D.new()
			_stairs_container.name = "StairsContainer"
			add_child(_stairs_container)

	if not is_instance_valid(_ceiling_container):
		_ceiling_container = get_node_or_null("CeilingContainer") as Node3D
		if not _ceiling_container:
			_ceiling_container = Node3D.new()
			_ceiling_container.name = "CeilingContainer"
			add_child(_ceiling_container)

	if not is_instance_valid(_parkour_container):
		_parkour_container = get_node_or_null("ParkourContainer") as Node3D
		if not _parkour_container:
			_parkour_container = Node3D.new()
			_parkour_container.name = "ParkourContainer"
			add_child(_parkour_container)

	if not is_instance_valid(_nested_container):
		_nested_container = get_node_or_null("NestedContainer") as Node3D
		if not _nested_container:
			_nested_container = Node3D.new()
			_nested_container.name = "NestedContainer"
			add_child(_nested_container)


## Clears existing generated node instances prior to layout regeneration.
func _clear_generated_containers() -> void:
	print("ProceduralBlockout: Removing previous generated geometry instances.")
	_ensure_containers()
	for child: Node in _stairs_container.get_children():
		child.queue_free()
	for child: Node in _ceiling_container.get_children():
		child.queue_free()
	for child: Node in _parkour_container.get_children():
		child.queue_free()
	for child: Node in _nested_container.get_children():
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
