class_name ChunkDebugHud
extends Control
## Event-driven 2D minimap HUD visualizing active chunks, saved deltas,
## roaming entities in [member dynamic_container], and player grid coordinates.

## Minimum chunk grid coordinate along X and Z axes.
const GRID_MIN: int = -10

## Maximum chunk grid coordinate along X and Z axes.
const GRID_MAX: int = 9

## Pixel width and height of each chunk cell on the minimap.
const CELL_SIZE: float = 12.0

## Pixel spacing between adjacent chunk cells on the minimap.
const CELL_GAP: float = 2.0

## Top-left screen margin offset in pixels for the minimap grid.
const HUD_OFFSET: Vector2 = Vector2(16.0, 16.0)

## World-space width and depth of a single chunk in meters.
const CHUNK_SIZE: float = 250.0

## Radius in pixels of roaming entity dots on the minimap.
const ROAMER_RADIUS: float = 3.0

## Radius in pixels of the player coordinate marker on the minimap.
const PLAYER_RADIUS: float = 4.5

## Squared search radius (50m) for selecting nearby test entities.
const INTERACT_RADIUS_SQ: float = 2500.0

## World X-axis offset applied when teleporting a roamer across chunk borders.
const ROAMER_DISPLACE_X: float = 300.0

## Fill color for unloaded chunk cells.
const COLOR_INACTIVE: Color = Color(0.16, 0.16, 0.18, 0.85)

## Fill color for currently loaded and active chunk cells.
const COLOR_ACTIVE: Color = Color(0.2, 0.75, 0.35, 0.9)

## Border color highlighting chunks with persisted state deltas.
const COLOR_DELTA_OUTLINE: Color = Color(1.0, 0.55, 0.1, 1.0)

## Marker color for roaming entities parented to [member dynamic_container].
const COLOR_ROAMER: Color = Color(0.1, 0.9, 1.0, 1.0)

## Marker color for the player's current chunk cell.
const COLOR_PLAYER: Color = Color(1.0, 1.0, 1.0, 1.0)

## Scene group identifying player entities.
const GROUP_PLAYER: StringName = &"player"

## Scene group identifying destructible static test crates.
const GROUP_CRATE: StringName = &"test_crate"

## Sentinel payload indicating an entity was destroyed.
const DELTA_FREED: StringName = &"freed"

## Deferred method name used to schedule HUD redraws after scene tree mutations.
const METHOD_REDRAW: StringName = &"queue_redraw"

## Target chunk manager providing chunk states and deltas.
@export var chunk_manager: ChunkManager

## Dynamic container hosting persistent roaming entities.
@export var dynamic_container: Node3D

## Cached player coordinate updated on boundary crossings.
var _player_coord: Vector2i = Vector2i.ZERO


## Validates dependencies, disables frame polling, and connects event triggers.
func _ready() -> void:
	assert(chunk_manager != null, "ChunkDebugHud requires chunk_manager assigned.")
	assert(dynamic_container != null, "ChunkDebugHud requires dynamic_container assigned.")
	set_process(false)
	set_physics_process(false)
	Utilities.safe_connect(Events.player_chunk_changed, _on_player_chunk_changed)
	Utilities.safe_connect(Events.chunk_entity_mutated, _on_chunk_entity_mutated)
	Utilities.safe_connect(chunk_manager.child_entered_tree, _on_chunk_tree_changed)
	Utilities.safe_connect(chunk_manager.child_exiting_tree, _on_chunk_tree_changed)


## Disconnects global and node signals upon exiting the scene tree.
func _exit_tree() -> void:
	if Events.player_chunk_changed.is_connected(_on_player_chunk_changed):
		Events.player_chunk_changed.disconnect(_on_player_chunk_changed)
	if Events.chunk_entity_mutated.is_connected(_on_chunk_entity_mutated):
		Events.chunk_entity_mutated.disconnect(_on_chunk_entity_mutated)
	if is_instance_valid(chunk_manager):
		if chunk_manager.child_entered_tree.is_connected(_on_chunk_tree_changed):
			chunk_manager.child_entered_tree.disconnect(_on_chunk_tree_changed)
		if chunk_manager.child_exiting_tree.is_connected(_on_chunk_tree_changed):
			chunk_manager.child_exiting_tree.disconnect(_on_chunk_tree_changed)


## Handles discrete debug keys: Key 1 destroys nearest crate, Key 2 teleports roamer.
func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_1:
		_destroy_nearest_crate()
	elif key_event.keycode == KEY_2:
		_displace_nearest_roamer()


## Renders the 20x20 chunk grid, delta outlines, roamers, and player marker.
func _draw() -> void:
	var cell_vec: Vector2 = Vector2(CELL_SIZE, CELL_SIZE)
	for x: int in range(GRID_MIN, GRID_MAX + 1):
		for y: int in range(GRID_MIN, GRID_MAX + 1):
			var coord: Vector2i = Vector2i(x, y)
			var top_left: Vector2 = _coord_to_pixel(coord)
			var rect: Rect2 = Rect2(top_left, cell_vec)
			var fill: Color = COLOR_INACTIVE
			if chunk_manager.is_chunk_active(coord):
				fill = COLOR_ACTIVE
			draw_rect(rect, fill, true)
			if chunk_manager.has_chunk_delta(coord):
				draw_rect(rect, COLOR_DELTA_OUTLINE, false, 1.5)

	var half_cell: Vector2 = cell_vec * 0.5
	var children: Array[Node] = dynamic_container.get_children()
	for child: Node in children:
		var roamer: Node3D = child as Node3D
		if roamer == null or not is_instance_valid(roamer):
			continue
		var pos: Vector3 = roamer.global_position
		var r_coord: Vector2i = Vector2i(floori(pos.x / CHUNK_SIZE), floori(pos.z / CHUNK_SIZE))
		var center: Vector2 = _coord_to_pixel(r_coord) + half_cell
		draw_circle(center, ROAMER_RADIUS, COLOR_ROAMER)

	var player_center: Vector2 = _coord_to_pixel(_player_coord) + half_cell
	draw_circle(player_center, PLAYER_RADIUS, COLOR_PLAYER)


## Updates cached player coordinate and schedules a redraw.
func _on_player_chunk_changed(coord: Vector2i) -> void:
	_player_coord = coord
	queue_redraw()


## Schedules a redraw when any chunk entity records a mutation delta.
func _on_chunk_entity_mutated(_coord: Vector2i, _entity_id: StringName, _data: Variant) -> void:
	queue_redraw()


## Defers a redraw when chunks attach to or detach from [member chunk_manager].
func _on_chunk_tree_changed(_node: Node) -> void:
	call_deferred(METHOD_REDRAW)


## Finds closest crate in [constant GROUP_CRATE], records freed delta, and frees it.
func _destroy_nearest_crate() -> void:
	var crates: Array[Node] = get_tree().get_nodes_in_group(GROUP_CRATE)
	var best_crate: Node3D = null
	var best_dist_sq: float = INTERACT_RADIUS_SQ
	var player_pos: Vector3 = _get_player_pos()

	for node: Node in crates:
		var crate: Node3D = node as Node3D
		if crate == null or not is_instance_valid(crate):
			continue
		var dist_sq: float = player_pos.distance_squared_to(crate.global_position)
		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			best_crate = crate

	if best_crate == null:
		print("Key 1: No TestCrate within 50m.")
		return

	var chunk_root: ChunkRoot = best_crate.get_parent() as ChunkRoot
	if chunk_root != null:
		chunk_root.report_entity_mutation(best_crate, DELTA_FREED)
	best_crate.queue_free()
	print("Key 1: Destroyed crate ", best_crate.name)


## Teleports closest roamer in [member dynamic_container] +300m on X across border.
func _displace_nearest_roamer() -> void:
	var children: Array[Node] = dynamic_container.get_children()
	var best_roamer: Node3D = null
	var best_dist_sq: float = INTERACT_RADIUS_SQ
	var player_pos: Vector3 = _get_player_pos()

	for child: Node in children:
		var roamer: Node3D = child as Node3D
		if roamer == null or not is_instance_valid(roamer):
			continue
		var dist_sq: float = player_pos.distance_squared_to(roamer.global_position)
		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			best_roamer = roamer

	if best_roamer == null:
		print("Key 2: No roaming entity in dynamic_container within 50m.")
		return

	var new_pos: Vector3 = best_roamer.global_position
	new_pos.x += ROAMER_DISPLACE_X
	best_roamer.global_position = new_pos
	var dest_chunk: Vector2i = Vector2i(
		floori(new_pos.x / CHUNK_SIZE), floori(new_pos.z / CHUNK_SIZE)
	)
	print("Key 2: Displaced ", best_roamer.name, " to chunk ", dest_chunk)


## Finds player position from group [constant GROUP_PLAYER] or active camera.
func _get_player_pos() -> Vector3:
	var player_node: Node = get_tree().get_first_node_in_group(GROUP_PLAYER)
	var player_3d: Node3D = player_node as Node3D
	if player_3d != null:
		return player_3d.global_position
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return Vector3.ZERO


## Converts chunk grid [param coord] into top-left minimap pixel coordinates.
func _coord_to_pixel(coord: Vector2i) -> Vector2:
	var step: float = CELL_SIZE + CELL_GAP
	var gx: float = float(coord.x - GRID_MIN) * step
	var gy: float = float(coord.y - GRID_MIN) * step
	return HUD_OFFSET + Vector2(gx, gy)
