class_name TestPlayer
extends CharacterBody3D
## Test harness controller providing boost locomotion and discrete key actions
## to verify chunk prop mutations (Key 1) and roamer displacement (Key 2).

## Standard horizontal movement speed in meters per second.
const SPEED_NORMAL: float = 15.0

## Boosted horizontal movement speed when holding Shift (crosses 250m in ~3.1s).
const SPEED_BOOST: float = 80.0

## Squared search radius (50m) for selecting nearby test entities.
const INTERACT_RADIUS_SQ: float = 2500.0

## World X-axis offset applied when teleporting a roamer across chunk borders.
const ROAMER_DISPLACE_X: float = 300.0

## World-space width and depth of a single chunk in meters.
const CHUNK_SIZE: float = 250.0

## Input action constant for moving left.
const INPUT_LEFT: StringName = &"ui_left"

## Input action constant for moving right.
const INPUT_RIGHT: StringName = &"ui_right"

## Input action constant for moving forward.
const INPUT_UP: StringName = &"ui_up"

## Input action constant for moving backward.
const INPUT_DOWN: StringName = &"ui_down"

## Scene group identifying destructible static test crates.
const GROUP_CRATE: StringName = &"test_crate"

## Sentinel payload indicating an entity was destroyed.
const DELTA_FREED: StringName = &"freed"

## Scene container hosting extracted roaming entities across chunk unloads.
@export var dynamic_container: Node3D

## Component tracking current chunk and boundary transitions.
@onready var _tracker: PlayerChunkTracker = $PlayerChunkTracker as PlayerChunkTracker


## Validates required dependencies, sets physics layers, and configures loop states.
func _ready() -> void:
	assert(dynamic_container != null, "TestPlayer requires dynamic_container assigned.")
	assert(_tracker != null, "TestPlayer requires a PlayerChunkTracker child node.")
	set_process(false)
	set_physics_process(true)
	collision_layer = CollisionLayers.MASK_PLAYER
	collision_mask = CollisionLayers.MASK_ENVIRONMENT


## Moves player along the XZ plane using standard or Shift-boosted speed.
func _physics_process(_delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(INPUT_LEFT, INPUT_RIGHT, INPUT_UP, INPUT_DOWN)
	var speed: float = SPEED_NORMAL
	if Input.is_key_pressed(KEY_SHIFT):
		speed = SPEED_BOOST
	velocity.x = input_dir.x * speed
	velocity.y = 0.0
	velocity.z = input_dir.y * speed
	move_and_slide()


## Handles discrete debug keys: Key 1 destroys nearest crate, Key 2 teleports roamer.
func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_1:
		_destroy_nearest_crate()
	elif key_event.keycode == KEY_2:
		_displace_nearest_roamer()


## Finds closest crate in [constant GROUP_CRATE], records freed delta, and frees it.
func _destroy_nearest_crate() -> void:
	var crates: Array[Node] = get_tree().get_nodes_in_group(GROUP_CRATE)
	var best_crate: Node3D = null
	var best_dist_sq: float = INTERACT_RADIUS_SQ
	var player_pos: Vector3 = global_position

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
	var player_pos: Vector3 = global_position

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
