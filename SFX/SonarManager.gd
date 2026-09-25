## Manages spatial navigation sonar pings and categorized audio cues for accessibility.
#class_name SonarManager
extends Node

## Emitted when a sonar scan finishes scanning the surroundings with target count.
signal on_scan_completed(targets_found: int)

## Maximum concurrent [AudioStreamPlayer3D] pooled for echo playback.
const MAX_AUDIO_PLAYERS: int = 16

## Dedicated audio bus name for accessibility sound effects.
const SFX_BUS_NAME: StringName = &"AccesibilitySFX"

## Minimum spatial distance squared (1.0m) to filter duplicate level instances.
const SPATIAL_DEDUPLICATION_THRESHOLD_SQ: float = 1.0

@export_category("Sonar Audio Streams")

## Sound played centered on the player when triggering a ping scan.
@export var ping_emitter_sound: AudioStream

## Audio stream used for interactable physical objects.
@export var interactable_echo_sound: AudioStream

## Audio stream used for navigational waypoints and exit routes.
@export var waypoint_echo_sound: AudioStream

## Audio stream used for environmental hazards, enemies, or drop-offs.
@export var hazard_echo_sound: AudioStream

@export_category("Sonar Tuning")

## Maximum scan radius in meters.
@export var scan_radius: float = 25.0

## Speed of virtual sound wave in meters per second for staggered playback.
@export var wave_speed: float = 40.0

## Minimum time in seconds between consecutive echoes to prevent audio clutter.
@export var min_cue_separation: float = 0.05

## Maximum number of targets audible in a single scan.
@export var max_audible_targets: int = 8

## Collision mask used for physics raycast occlusion detection.
@export_flags_3d_physics var occlusion_collision_mask: int = 1

## Dedicated [AudioStreamPlayer] for the outgoing local ping chime.
var _local_ping_player: AudioStreamPlayer = AudioStreamPlayer.new()

## Pool of recycled [AudioStreamPlayer3D] nodes to prevent runtime allocations.
var _player_pool: Array[AudioStreamPlayer3D] = []

## Internal counter tracking active players inside the object pool.
var _pool_index: int = 0

## Incremental ID tracking active sweeps to cancel stale timers on rapid pings.
var _current_sweep_id: int = 0


## Initializes audio player pool and connects to global event dispatcher.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("SonarManager: Initializing spatial audio pool.")
	_setup_audio_nodes()

	if has_node("/root/Events"):
		var events_node: Node = get_node("/root/Events")
		if events_node.has_signal("sonar_ping_requested"):
			Utilities.safe_connect(events_node.sonar_ping_requested, trigger_sonar)
			print("SonarManager: Hooked to Events.sonar_ping_requested.")


## Executes active sonar sweep centered on origin node using [method Utilities.delay_call].
## [param origin_node] Node representing player or camera origin.
func trigger_sonar(origin_node: Node3D) -> void:
	if not is_instance_valid(origin_node):
		print("SonarManager: Invalid origin node passed to trigger_sonar.")
		return

	_current_sweep_id += 1
	var active_sweep_id: int = _current_sweep_id

	print("SonarManager: Ping triggered at: ", origin_node.global_position)
	if _local_ping_player.stream != null:
		_local_ping_player.play()

	var target_viewport: Viewport = origin_node.get_viewport()
	var origin_pos: Vector3 = origin_node.global_position
	var forward_dir: Vector3 = -origin_node.global_transform.basis.z.normalized()
	var space_state: PhysicsDirectSpaceState3D = origin_node.get_world_3d().direct_space_state

	var query_groups: Array[StringName] = [
		&"hazard", &"waypoint", &"interactables", &"interactable", &"props"
	]

	var tree: SceneTree = get_tree()
	if tree == null:
		return

	# Step 1: Collect canonical roots keyed by unique instance ID
	var unique_targets: Dictionary = {}
	for group_name: StringName in query_groups:
		for item: Node in tree.get_nodes_in_group(group_name):
			if not is_instance_valid(item):
				continue

			if item.get_viewport() != target_viewport:
				continue

			var node_3d: Node3D = null
			if item is Node3D:
				node_3d = item as Node3D
			elif item.get_parent() is Node3D:
				node_3d = item.get_parent() as Node3D

			if not is_instance_valid(node_3d) or node_3d == origin_node:
				continue

			var root_target: Node3D = _resolve_interactable_root(node_3d)
			if is_instance_valid(root_target) and root_target != origin_node:
				var root_id: int = root_target.get_instance_id()
				if not unique_targets.has(root_id):
					unique_targets[root_id] = root_target

	# Step 2: Strip child nodes, hidden objects, and co-located duplicate instances
	var candidate_nodes: Array[Node3D] = []
	var seen_positions: Array[Vector3] = []

	for root_id: int in unique_targets:
		var node: Node3D = unique_targets[root_id] as Node3D

		if not node.is_visible_in_tree():
			continue
		if "is_held" in node and node.get("is_held") == true:
			continue
		if "holder" in node and is_instance_valid(node.get("holder")):
			continue

		var is_child_of_another: bool = false
		for other_id: int in unique_targets:
			if root_id != other_id:
				var other: Node3D = unique_targets[other_id] as Node3D
				if is_instance_valid(other) and other.is_ancestor_of(node):
					is_child_of_another = true
					break

		if is_child_of_another:
			continue

		var is_spatial_duplicate: bool = false
		for seen_pos: Vector3 in seen_positions:
			if (
				seen_pos.distance_squared_to(node.global_position)
				< SPATIAL_DEDUPLICATION_THRESHOLD_SQ
			):
				is_spatial_duplicate = true
				break

		if not is_spatial_duplicate:
			seen_positions.append(node.global_position)
			candidate_nodes.append(node)

	# Step 3: Occlusion and priority ranking via Utilities.raycast_3d
	var targets_to_ping: Array[Dictionary] = []
	for target_3d: Node3D in candidate_nodes:
		var dist: float = origin_pos.distance_to(target_3d.global_position)
		if dist <= scan_radius:
			var priority: int = _get_target_priority(target_3d)
			var is_occluded: bool = _check_occlusion(space_state, origin_pos, target_3d)
			targets_to_ping.append(
				{
					"node": target_3d,
					"distance": dist,
					"priority": priority,
					"is_occluded": is_occluded
				}
			)

	targets_to_ping.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if (a["priority"] as int) != (b["priority"] as int):
				return (a["priority"] as int) < (b["priority"] as int)
			return (a["distance"] as float) < (b["distance"] as float)
	)

	if targets_to_ping.size() > max_audible_targets:
		targets_to_ping = targets_to_ping.slice(0, max_audible_targets)

	targets_to_ping.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (a["distance"] as float) < (b["distance"] as float)
	)

	var last_scheduled_time: float = 0.0
	for target_data: Dictionary in targets_to_ping:
		var target_node: Node3D = target_data["node"] as Node3D
		var distance: float = target_data["distance"] as float
		var is_occluded: bool = target_data["is_occluded"] as bool
		var natural_delay: float = distance / wave_speed
		var scheduled_delay: float = maxf(natural_delay, last_scheduled_time + min_cue_separation)
		last_scheduled_time = scheduled_delay

		Utilities.delay_call(
			self,
			scheduled_delay,
			_play_target_echo.bind(
				active_sweep_id, origin_pos, forward_dir, target_node, is_occluded
			)
		)

	on_scan_completed.emit(targets_to_ping.size())


## Configures local ping player and pre-allocates 3D player pool.
func _setup_audio_nodes() -> void:
	print("SonarManager: Configuring audio bus routing and pooling.")
	var resolved_bus: StringName = SFX_BUS_NAME
	if AudioServer.get_bus_index(resolved_bus) == -1:
		resolved_bus = &"AccessibilitySFX"
		if AudioServer.get_bus_index(resolved_bus) == -1:
			resolved_bus = &"Master"

	_local_ping_player.bus = resolved_bus
	if ping_emitter_sound != null:
		_local_ping_player.stream = ping_emitter_sound
	add_child(_local_ping_player)

	for i: int in range(MAX_AUDIO_PLAYERS):
		var player_3d: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player_3d.bus = resolved_bus
		player_3d.max_distance = scan_radius
		player_3d.attenuation_model = (AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE)
		player_3d.unit_size = 3.0
		add_child(player_3d)
		_player_pool.append(player_3d)


## Ascends node hierarchy to find canonical root [Node3D] representing interactable entity.
## [param node] Target node detected via group query.
## [return] Highest root [Node3D] representing interactable asset.
func _resolve_interactable_root(node: Node3D) -> Node3D:
	if not is_instance_valid(node):
		return null

	var candidate: Node3D = node
	var current: Node = node
	var tree: SceneTree = get_tree()
	var scene_root: Node = tree.root if tree != null else null
	var curr_scene: Node = tree.current_scene if tree != null else null

	while is_instance_valid(current) and current != scene_root:
		if current == curr_scene:
			break

		if current is Node3D:
			var curr_3d: Node3D = current as Node3D
			if curr_3d is PickableObject:
				return curr_3d
			if curr_3d.has_node("InteractComponent") or curr_3d.has_node("TTSInteractComponent"):
				candidate = curr_3d
			elif curr_3d is CollisionObject3D:
				candidate = curr_3d

		current = current.get_parent()

	return candidate


## Calculates integer priority rank for audio filtering.
## [param target_node] Evaluated node.
## [return] Priority rank from 0 (highest) to 2 (lowest).
func _get_target_priority(target_node: Node3D) -> int:
	if target_node.is_in_group(&"hazard"):
		return 0
	if target_node.is_in_group(&"waypoint"):
		return 1
	return 2


## Casts physics ray using [method Utilities.raycast_3d] to verify line of sight.
## [param space_state] Direct 3D physics space state.
## [param origin_pos] Origin coordinates of ping.
## [param target_node] Destination target node.
## [return] True if an occluding collider intercepts ray.
func _check_occlusion(
	space_state: PhysicsDirectSpaceState3D, origin_pos: Vector3, target_node: Node3D
) -> bool:
	var exclude: Array[RID] = []
	if target_node is CollisionObject3D:
		exclude.append((target_node as CollisionObject3D).get_rid())

	var result: Dictionary = Utilities.raycast_3d(
		space_state, origin_pos, target_node.global_position, occlusion_collision_mask, exclude
	)
	return not result.is_empty()


## Resolves audio stream based on group membership.
## [param target_node] Target node.
## [return] Matching [AudioStream] or null if unassigned.
func _resolve_target_stream(target_node: Node3D) -> AudioStream:
	if target_node.is_in_group(&"hazard") and hazard_echo_sound != null:
		return hazard_echo_sound
	if target_node.is_in_group(&"waypoint") and waypoint_echo_sound != null:
		return waypoint_echo_sound
	return interactable_echo_sound


## Plays spatialized 3D echo at target location with spectral attenuation.
## [param sweep_id] Token tracking active sweep instance.
## [param player_pos] Global position of listener.
## [param forward_dir] Forward vector of listener.
## [param target_node] Destination node receiving echo.
## [param is_occluded] Whether line of sight is obstructed.
func _play_target_echo(
	sweep_id: int, player_pos: Vector3, forward_dir: Vector3, target_node: Node3D, is_occluded: bool
) -> void:
	if sweep_id != _current_sweep_id:
		return

	if not is_instance_valid(target_node):
		return

	var stream_to_play: AudioStream = _resolve_target_stream(target_node)
	if stream_to_play == null:
		return

	var player_3d: AudioStreamPlayer3D = _player_pool[_pool_index]
	_pool_index = (_pool_index + 1) % MAX_AUDIO_PLAYERS

	if player_3d.playing:
		player_3d.stop()

	player_3d.global_position = target_node.global_position
	player_3d.stream = stream_to_play

	var height_diff: float = target_node.global_position.y - player_pos.y
	var elevation_factor: float = clampf(height_diff / 4.0, -0.3, 0.3)
	var final_pitch: float = 1.0 + elevation_factor
	var final_volume_db: float = 0.0

	var to_target: Vector3 = (target_node.global_position - player_pos).normalized()
	var dot: float = forward_dir.dot(to_target)
	if dot < 0.0:
		final_pitch *= lerpf(0.85, 1.0, dot + 1.0)
		final_volume_db -= lerpf(4.0, 0.0, dot + 1.0)

	if is_occluded:
		final_volume_db -= 6.0
		final_pitch *= 0.8

	player_3d.pitch_scale = clampf(final_pitch, 0.5, 2.0)
	player_3d.volume_db = final_volume_db

	print(
		"SonarManager: Echoing ",
		target_node.name,
		" | Pitch: ",
		player_3d.pitch_scale,
		" | Vol: ",
		player_3d.volume_db,
		"dB | Occluded: ",
		is_occluded
	)
	player_3d.play()
