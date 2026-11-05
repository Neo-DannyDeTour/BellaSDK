# class_name SensorTurret
extends Node3D

## Turret sensor that tracks the player at 60 FPS and updates dual-ray cover,
## tagged prop proximity, distance, and elevation readouts on a 4 Hz timer.

## Group used to auto-locate the player if not assigned in the Inspector.
const GROUP_PLAYER: StringName = &"player"
## Group used to locate tagged props for proximity evaluation.
const GROUP_TAGGED_PROP: StringName = &"tagged_prop"
## Metadata key checked on raycast colliders for cover identification.
const META_PROP_TAG: StringName = &"prop_tag"
## Script property name checked as fallback for cover identification.
const PROP_TAG_PROPERTY: StringName = &"prop_tag"
## Script property name checked on tagged props for bounding volume size.
const PROP_SIZE_PROPERTY: StringName = &"size"
## Default fallback tag when an untagged geometry collider blocks line of sight.
const DEFAULT_COVER_TAG: StringName = &"cover"
## Vertical offset from player feet origin to pelvis target.
const PELVIS_OFFSET: Vector3 = Vector3(0.0, 0.7, 0.0)
## Fallback vertical offset from player feet origin to head target.
const HEAD_FALLBACK_OFFSET: Vector3 = Vector3(0.0, 1.6, 0.0)
## Minimum ray distance from turret head to ignore self-podium occlusion.
const SELF_CLEARANCE_DIST: float = 0.65
## Maximum iterative ray steps when bypassing turret podium geometry.
const MAX_RAY_HOPS: int = 3
## Distance threshold in meters for "close" classification.
const DIST_CLOSE: float = 5.0
## Distance threshold in meters for "medium" vs "far away" classification.
const DIST_MEDIUM: float = 15.0
## Vertical delta threshold in meters for "above" or "below" classification.
const ELEVATION_THRESHOLD: float = 1.5
## Physics mask covering Layer 1 (Environment), Layer 2 (Player), Layer 3 (Interactive).
const RAY_COLLISION_MASK: int = CollisionLayers.MASK_SOLID_WORLD | CollisionLayers.MASK_PLAYER

## Player root entity to track and evaluate.
@export var player: Node3D:
	set(value):
		player = value
		_player_head = null
## Maximum spherical distance in meters for tracking and scanning.
@export var detection_range: float = 25.0:
	set(value):
		detection_range = maxf(value, 0.1)
		_range_sq = detection_range * detection_range
## Distance in meters from a tagged prop surface within which the player counts as "near".
@export var near_prop_distance: float = 2.5
## Interval in seconds between sensory scan evaluations.
@export var scan_interval: float = 0.25

## Cached squared detection range to prevent per-frame square root operations.
var _range_sq: float = 625.0
## Whether the player is currently inside active sensory range.
var _in_range: bool = false
## Deduplication cache key preventing redundant console prints.
var _last_state_key: String = ""
## Cached reference to player head or camera node.
var _player_head: Node3D

## Turret rotating head tracking the target.
@onready var _head: Node3D = $Head as Node3D
## Raycast node used for on-demand obstacle sampling.
@onready var _ray: RayCast3D = $RayCast3D as RayCast3D
## 3D text label displaying sensory readouts.
@onready var _label: Label3D = $Label3D as Label3D
## Throttled timer triggering 4 Hz sensory sweeps.
@onready var _scan_timer: Timer = $ScanTimer as Timer


## Validates child nodes, configures physics raycast and 4 Hz scan timer.
func _ready() -> void:
	if not is_instance_valid(player):
		player = NodeQuery.get_single_node_in_group(get_tree(), GROUP_PLAYER) as Node3D

	assert(is_instance_valid(_head), "SensorTurret requires a Head Node3D child.")
	assert(is_instance_valid(_ray), "SensorTurret requires a RayCast3D child.")
	assert(is_instance_valid(_label), "SensorTurret requires a Label3D child.")
	assert(is_instance_valid(_scan_timer), "SensorTurret requires a ScanTimer child.")

	_range_sq = detection_range * detection_range

	_ray.enabled = false
	_ray.collision_mask = RAY_COLLISION_MASK
	_ray.hit_from_inside = false

	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.text = tr("Idle")

	_scan_timer.wait_time = scan_interval
	_scan_timer.one_shot = false
	Utilities.safe_connect(_scan_timer.timeout, _on_scan_timer_timeout)
	_scan_timer.start()

	set_physics_process(false)


## Rotates turret head at 60 FPS only while player is within detection_range.
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		set_physics_process(false)
		return

	var target_pos: Vector3 = _get_head_world_pos(player.global_position)
	var diff: Vector3 = target_pos - _head.global_position
	if diff.length_squared() > 0.0001 and absf(diff.normalized().dot(Vector3.UP)) < 0.999:
		_head.look_at(target_pos, Vector3.UP)


## Evaluates range, dual-ray cover, distance band, and elevation at 4 Hz.
func _on_scan_timer_timeout() -> void:
	if not is_instance_valid(player):
		return

	var player_pos: Vector3 = player.global_position
	var dist_sq: float = global_position.distance_squared_to(player_pos)

	if dist_sq > _range_sq:
		if _in_range:
			_in_range = false
			set_physics_process(false)
			_label.text = tr("Out of range")
			_last_state_key = "out_of_range"
			print("SensorTurret: Player out of range")
		return

	if not _in_range:
		_in_range = true
		set_physics_process(true)

	var dist: float = sqrt(dist_sq)
	var dist_band: String = _get_distance_band(dist)
	var elev_band: String = _get_elevation_band(player_pos.y - global_position.y)
	var pelvis_pos: Vector3 = player_pos + PELVIS_OFFSET
	var head_pos: Vector3 = _get_head_world_pos(player_pos)
	var cover_text: String = _evaluate_cover(player_pos, pelvis_pos, head_pos)

	_label.text = "%s\n%.1fm (%s)\n%s" % [cover_text, dist, dist_band, elev_band]

	var state_key: String = "%s|%s|%s" % [cover_text, dist_band, elev_band]
	if state_key != _last_state_key:
		_last_state_key = state_key
		print(
			"SensorTurret: Sense -> %s | %.1fm (%s) | %s" % [cover_text, dist, dist_band, elev_band]
		)


## Resolves world position of player head using node reference or fallback offset.
func _get_head_world_pos(player_pos: Vector3) -> Vector3:
	if not is_instance_valid(_player_head) and is_instance_valid(player):
		_player_head = _find_player_head(player)
	if is_instance_valid(_player_head):
		return _player_head.global_position
	return player_pos + HEAD_FALLBACK_OFFSET


## Automatically inspects [param target_player] hierarchy to locate head or camera node.
func _find_player_head(target_player: Node3D) -> Node3D:
	if not is_instance_valid(target_player):
		return null
	var named_head: Node = target_player.get_node_or_null("Head")
	if is_instance_valid(named_head) and named_head is Node3D:
		return named_head as Node3D
	var camera_child: Node = NodeQuery.find_first_child_of_type(target_player, Camera3D)
	if is_instance_valid(camera_child) and camera_child is Node3D:
		return camera_child as Node3D
	return null


## Evaluates dual-ray occlusion and tagged prop proximity to produce tactical cover readout.
func _evaluate_cover(player_pos: Vector3, pelvis_pos: Vector3, head_pos: Vector3) -> String:
	var pelvis_tag: StringName = _probe_tag(pelvis_pos)
	var head_tag: StringName = _probe_tag(head_pos)
	var near_tag: StringName = _find_nearest_tagged_prop(player_pos)

	var pelvis_blocked: bool = pelvis_tag != &""
	var head_blocked: bool = head_tag != &""

	if pelvis_blocked and head_blocked:
		var full_tag: StringName = _select_best_tag(pelvis_tag, head_tag, near_tag)
		var phrase_key: StringName = StringName("behind_" + String(full_tag).replace(" ", "_"))
		var localized_phrase: String = tr(phrase_key)
		if localized_phrase != String(phrase_key):
			return localized_phrase
		return tr("behind %s") % tr(String(full_tag))

	if pelvis_blocked or head_blocked:
		var raw_tag: StringName = pelvis_tag if pelvis_blocked else head_tag
		var partial_tag: StringName = _select_best_tag(raw_tag, &"", near_tag)
		var tag_str: String = String(partial_tag).replace(" ", "_")
		if partial_tag != DEFAULT_COVER_TAG:
			var near_part_key: StringName = StringName("near_partially_behind_" + tag_str)
			var localized_near_part: String = tr(near_part_key)
			if localized_near_part != String(near_part_key):
				return localized_near_part
			return tr("near %s, partially behind") % tr(String(partial_tag))
		var part_key: StringName = StringName("partially_behind_" + tag_str)
		var localized_part: String = tr(part_key)
		if localized_part != String(part_key):
			return localized_part
		return tr("partially behind %s") % tr(String(partial_tag))

	if near_tag != &"":
		var near_tag_str: String = String(near_tag).replace(" ", "_")
		var near_exp_key: StringName = StringName("near_exposed_" + near_tag_str)
		var localized_near_exp: String = tr(near_exp_key)
		if localized_near_exp != String(near_exp_key):
			return localized_near_exp
		return tr("near %s, exposed") % tr(String(near_tag))

	return tr("exposed")


## Prioritizes specific prop tags over the generic fallback cover tag.
func _select_best_tag(
	primary: StringName, secondary: StringName, near_tag: StringName
) -> StringName:
	if primary != &"" and primary != DEFAULT_COVER_TAG:
		return primary
	if secondary != &"" and secondary != DEFAULT_COVER_TAG:
		return secondary
	if near_tag != &"":
		return near_tag
	if primary != &"":
		return primary
	if secondary != &"":
		return secondary
	return DEFAULT_COVER_TAG


## Finds closest node tag in [const GROUP_TAGGED_PROP] within [member near_prop_distance].
func _find_nearest_tagged_prop(player_pos: Vector3) -> StringName:
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree):
		return &""

	var props: Array[Node] = tree.get_nodes_in_group(GROUP_TAGGED_PROP)
	var best_tag: StringName = &""
	var best_dist_sq: float = INF

	for node: Node in props:
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var prop_3d: Node3D = node as Node3D
		if not prop_3d.is_visible_in_tree():
			continue

		var prop_radius: float = _get_prop_effective_radius(prop_3d)
		var max_dist: float = near_prop_distance + prop_radius
		var dist_sq: float = prop_3d.global_position.distance_squared_to(player_pos)
		if dist_sq <= (max_dist * max_dist) and dist_sq < best_dist_sq:
			var tag: StringName = _extract_prop_tag(prop_3d)
			if tag != &"":
				best_dist_sq = dist_sq
				best_tag = tag

	return best_tag


## Estimates horizontal bounding radius of [param prop_node] from its size property.
func _get_prop_effective_radius(prop_node: Node3D) -> float:
	var size_val: Variant = prop_node.get(PROP_SIZE_PROPERTY)
	if size_val is Vector3:
		var s: Vector3 = size_val
		var sc: Vector3 = prop_node.global_transform.basis.get_scale()
		return maxf(s.x * absf(sc.x), s.z * absf(sc.z)) * 0.5
	return 0.5


## Casts ray to [param target_world_pos], stepping past immediate turret podium hits.
func _probe_tag(target_world_pos: Vector3) -> StringName:
	var origin: Vector3 = _head.global_position
	var to_target: Vector3 = target_world_pos - origin
	var total_len: float = to_target.length()
	if total_len < 0.05:
		return &""
	var dir: Vector3 = to_target / total_len

	for hop: int in MAX_RAY_HOPS:
		_ray.global_position = origin
		_ray.target_position = _ray.to_local(target_world_pos)
		_ray.force_raycast_update()

		if not _ray.is_colliding():
			return &""

		var collider: Object = _ray.get_collider()
		if not is_instance_valid(collider) or _is_player_collider(collider):
			return &""

		var direct_tag: StringName = _resolve_collider_tag(collider)
		if direct_tag != &"":
			return direct_tag

		var hit_point: Vector3 = _ray.get_collision_point()
		var dist_from_head_sq: float = _head.global_position.distance_squared_to(hit_point)
		if dist_from_head_sq < (SELF_CLEARANCE_DIST * SELF_CLEARANCE_DIST):
			origin = hit_point + dir * 0.15
			if origin.distance_squared_to(target_world_pos) < 0.05:
				return &""
			continue

		var near_hit_tag: StringName = _find_tagged_prop_at_point(hit_point)
		if near_hit_tag != &"":
			return near_hit_tag

		return DEFAULT_COVER_TAG

	return &""


## Checks whether [param collider] belongs to the player entity hierarchy.
func _is_player_collider(collider: Object) -> bool:
	if collider == player:
		return true
	var collider_node: Node = collider as Node
	if is_instance_valid(collider_node):
		if collider_node.is_in_group(GROUP_PLAYER):
			return true
		if NodeQuery.find_ancestor_in_group(collider_node, GROUP_PLAYER) != null:
			return true
	return false


## Extracts prop_tag from [param collider] or its ancestor chain.
func _resolve_collider_tag(collider: Object) -> StringName:
	var direct_tag: StringName = _extract_prop_tag(collider)
	if direct_tag != &"":
		return direct_tag

	var collider_node: Node = collider as Node
	if is_instance_valid(collider_node):
		var current: Node = collider_node.get_parent()
		while is_instance_valid(current):
			var ancestor_tag: StringName = _extract_prop_tag(current)
			if ancestor_tag != &"":
				return ancestor_tag
			current = current.get_parent()

	return &""


## Checks if a ray hit point lies inside or on the surface of any tagged prop.
func _find_tagged_prop_at_point(hit_point: Vector3) -> StringName:
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree):
		return &""

	var props: Array[Node] = tree.get_nodes_in_group(GROUP_TAGGED_PROP)
	for node: Node in props:
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var prop_3d: Node3D = node as Node3D
		var radius: float = _get_prop_effective_radius(prop_3d) + 0.35
		if prop_3d.global_position.distance_squared_to(hit_point) <= (radius * radius):
			var tag: StringName = _extract_prop_tag(prop_3d)
			if tag != &"":
				return tag
	return &""


## Extracts tactical tag from metadata or property on [param target].
func _extract_prop_tag(target: Object) -> StringName:
	if not is_instance_valid(target):
		return &""
	if target.has_meta(META_PROP_TAG):
		var tag_val: Variant = target.get_meta(META_PROP_TAG)
		if tag_val is StringName and tag_val != &"":
			return StringName(String(tag_val).strip_edges())
		if tag_val is String:
			var clean_meta: String = str(tag_val).strip_edges()
			if not clean_meta.is_empty():
				return StringName(clean_meta)

	var prop_val: Variant = target.get(PROP_TAG_PROPERTY)
	if prop_val is StringName and prop_val != &"":
		return StringName(String(prop_val).strip_edges())
	if prop_val is String:
		var clean_prop: String = str(prop_val).strip_edges()
		if not clean_prop.is_empty():
			return StringName(clean_prop)

	return &""


## Maps meter distance to tactical band string.
func _get_distance_band(dist: float) -> String:
	if dist < DIST_CLOSE:
		return tr("close")
	if dist <= DIST_MEDIUM:
		return tr("medium")
	return tr("far away")


## Maps vertical delta in meters to elevation string.
func _get_elevation_band(dy: float) -> String:
	if dy > ELEVATION_THRESHOLD:
		return tr("above")
	if dy < -ELEVATION_THRESHOLD:
		return tr("below")
	return tr("level")
