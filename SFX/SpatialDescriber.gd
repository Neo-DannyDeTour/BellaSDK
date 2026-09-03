## Global autoload responsible for generating Text-to-Speech spatial descriptions.
##
## [SpatialDescriber] acts as an accessibility layer that translates the 3D positions
## of surrounding objects into conversational, directional language and routes it
## to the [TTSManager].
## It gathers interactable objects within the active player [Camera3D] frustum,
## eliminates duplicate node representations, verifies line-of-sight with raycasts,
## groups identical items into clusters, and prioritizes items from nearest
## in front to peripheral to far away.
extends Node

## Emitted when an environment description string has been generated.
## [param description_text] The formatted spoken summary string.
signal on_description_generated(description_text: String)

@export_category("Spatial Description Tuning")
## Maximum search radius in meters around the origin node.
@export var description_radius: float = 12.0

## Distance threshold in meters separating immediate foreground from far objects.
@export var nearby_distance_threshold: float = 4.0

## Maximum distance in meters between identical items to be grouped together.
@export var cluster_distance_threshold: float = 2.5

## Distance threshold squared (0.25m / 50cm) to merge duplicate collision proxies.
@export var spatial_deduplication_threshold_sq: float = 0.25

## Maximum number of distinct item clusters announced per sweep.
@export var max_announced_clusters: int = 4

## Collision mask used to filter out occluded items from narration.
@export_flags_3d_physics var occlusion_collision_mask: int = 1

## Default eye-level vertical offset added when origin_node is not a Camera3D.
@export var eye_height_offset: float = 1.6

## Minimum elevation in meters above eye level before qualifying an entity as 'above you'.
@export var above_elevation_threshold: float = 0.35

## Minimum vertical distance in meters below
## the player's ground plane before qualifying as 'below you'.
@export var below_ground_threshold: float = 0.5

## Regular expression used for splitting camelCase identifiers into spaced words.
var _regex_camel: RegEx = RegEx.new()

## Regular expression used for stripping numerical IDs and symbol delimiters from names.
var _regex_symbols: RegEx = RegEx.new()


## Configures process mode, compiles regex patterns, and binds global events.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("SpatialDescriber: Initializing spatial description module.")

	var err_camel: Error = _regex_camel.compile("([a-z])([A-Z])")
	if err_camel != OK:
		print("SpatialDescriber: Failed to compile camelCase RegEx pattern.")

	var err_symbols: Error = _regex_symbols.compile("[0-9_@]+")
	if err_symbols != OK:
		print("SpatialDescriber: Failed to compile symbols RegEx pattern.")

	if has_node("/root/Events"):
		var events_node: Node = get_node("/root/Events")
		if events_node.has_signal("describe_surroundings_requested"):
			events_node.describe_surroundings_requested.connect(describe_surroundings)
			print("SpatialDescriber: Connected to Events.describe_surroundings_requested.")


## Executes a localized sweep and generates an audible narration summary for interactables.
## [param origin_node] The [Node3D] representing the player or camera.
func describe_surroundings(origin_node: Node3D) -> void:
	print("SpatialDescriber: describe_surroundings() invoked.")
	if not is_instance_valid(origin_node):
		print("SpatialDescriber: Invalid origin node passed.")
		return

	var camera: Camera3D = _resolve_active_camera(origin_node)
	if not is_instance_valid(camera):
		print("SpatialDescriber: No active Camera3D found for spatial sweep.")
		_speak("Camera view unavailable.")
		return

	var target_viewport: Viewport = origin_node.get_viewport()
	var view_pos: Vector3 = camera.global_position
	var space_state: PhysicsDirectSpaceState3D = origin_node.get_world_3d().direct_space_state

	# Establish the ground walking plane to distinguish standing floor from pits/stairs.
	var ground_y: float = (
		origin_node.global_position.y if origin_node != camera else (view_pos.y - eye_height_offset)
	)

	print("SpatialDescriber: Viewpoint Y: ", view_pos.y, ", Ground Y: ", ground_y)

	var unique_roots: Dictionary = {}
	var candidate_nodes: Array[Node] = get_tree().get_nodes_in_group(&"interactables")

	for item: Node in candidate_nodes:
		if not is_instance_valid(item):
			continue

		if item.get_viewport() != target_viewport:
			continue

		if _is_menu_or_diorama_node(item):
			continue

		var node_3d: Node3D = null
		if item is Node3D:
			node_3d = item as Node3D
		elif item.get_parent() is Node3D:
			node_3d = item.get_parent() as Node3D

		if not is_instance_valid(node_3d) or node_3d == origin_node:
			continue

		var root_node: Node3D = _resolve_interactable_root(node_3d)
		if is_instance_valid(root_node) and root_node != origin_node:
			var root_id: int = root_node.get_instance_id()
			if not unique_roots.has(root_id):
				unique_roots[root_id] = root_node

	var filtered_targets: Array[Node3D] = []
	var seen_positions: Array[Vector3] = []

	for root_id: int in unique_roots:
		var node: Node3D = unique_roots[root_id] as Node3D
		if not node.is_inside_tree() or not node.is_visible_in_tree():
			continue
		if "is_held" in node and node.get("is_held") == true:
			continue
		if "holder" in node and is_instance_valid(node.get("holder")):
			continue

		var is_child_of_another: bool = false
		for other_id: int in unique_roots:
			if root_id != other_id:
				var other: Node3D = unique_roots[other_id] as Node3D
				if is_instance_valid(other) and other.is_ancestor_of(node):
					is_child_of_another = true
					break

		if is_child_of_another:
			continue

		var is_spatial_dup: bool = false
		for seen_pos: Vector3 in seen_positions:
			if (
				seen_pos.distance_squared_to(node.global_position)
				< spatial_deduplication_threshold_sq
			):
				is_spatial_dup = true
				break

		if not is_spatial_dup:
			seen_positions.append(node.global_position)
			filtered_targets.append(node)

	var valid_targets: Array[Dictionary] = []

	for target_3d: Node3D in filtered_targets:
		var target_pos: Vector3 = target_3d.global_position
		var dist: float = view_pos.distance_to(target_pos)

		if dist > description_radius or dist < 0.3:
			continue

		if not camera.is_position_in_frustum(target_pos):
			continue

		if _is_occluded(space_state, view_pos, target_3d, origin_node):
			print("SpatialDescriber: Skipping '%s' (occluded)" % target_3d.name)
			continue

		var display_name: String = _resolve_display_name(target_3d)
		if display_name.is_empty():
			continue

		valid_targets.append(
			{"node": target_3d, "name": display_name, "position": target_pos, "distance": dist}
		)

	if valid_targets.is_empty():
		var empty_msg: String = "No interactables in view."
		print("SpatialDescriber: Output: ", empty_msg)
		_speak(empty_msg)
		return

	var clusters: Array[Dictionary] = _cluster_targets(valid_targets)
	_sort_clusters_prioritized(camera, view_pos, clusters)

	var spoken_segments: Array[String] = []
	var announced: Array[Dictionary] = clusters.slice(0, max_announced_clusters)

	for cluster: Dictionary in announced:
		var count: int = cluster["count"] as int
		var item_name: String = cluster["name"] as String
		var avg_pos: Vector3 = cluster["avg_pos"] as Vector3
		var avg_dist: float = view_pos.distance_to(avg_pos)
		var rounded_dist: int = maxi(1, int(roundf(avg_dist)))

		var dir_phrase: String = _get_relative_direction(camera, view_pos, avg_pos, ground_y)
		var label_phrase: String = _format_plural(item_name, count)
		var meter_word: String = "meter" if rounded_dist == 1 else "meters"

		var segment: String = "%s, %d %s %s" % [label_phrase, rounded_dist, meter_word, dir_phrase]
		spoken_segments.append(segment)

	var final_speech: String = "; ".join(spoken_segments) + "."
	print("SpatialDescriber: Output: ", final_speech)
	_speak(final_speech)
	on_description_generated.emit(final_speech)


## Resolves the active [Camera3D] for the viewpoint sweep.
## [param origin_node] The root player or observer node.
## [return] The active [Camera3D] or null.
func _resolve_active_camera(origin_node: Node3D) -> Camera3D:
	print("SpatialDescriber: Resolving active camera.")
	if origin_node is Camera3D:
		return origin_node as Camera3D

	var viewport_cam: Camera3D = origin_node.get_viewport().get_camera_3d()
	if is_instance_valid(viewport_cam):
		return viewport_cam

	return origin_node.find_child("*Camera*", true, false) as Camera3D


## Ascends node hierarchy to find the canonical root [Node3D] representing the interactable entity.
## [param node] The target [Node3D] detected via group queries.
## [return] The highest root [Node3D] representing the interactable asset.
func _resolve_interactable_root(node: Node3D) -> Node3D:
	if not is_instance_valid(node):
		return null

	var candidate: Node3D = node
	var current: Node = node

	while is_instance_valid(current) and current != get_tree().root:
		if current == get_tree().current_scene:
			break

		if current is Node3D:
			var curr_3d: Node3D = current as Node3D
			if curr_3d is PickableObject:
				return curr_3d
			if curr_3d.has_node("InteractComponent") or curr_3d.has_node("TTSInteractComponent"):
				candidate = curr_3d
			elif candidate == node and curr_3d is CollisionObject3D:
				candidate = curr_3d

		current = current.get_parent()

	return candidate


## Ascertains if a node belongs to a menu, settings preview, or UI diorama branch.
## [param node] The target node being evaluated.
## [return] True if the node is within any menu or preview hierarchy.
func _is_menu_or_diorama_node(node: Node) -> bool:
	var current: Node = node
	while is_instance_valid(current) and current != get_tree().root:
		if current is Control:
			return true
		var lower_name: String = current.name.to_lower()
		if (
			lower_name.contains("menu")
			or lower_name.contains("diorama")
			or lower_name.contains("preview")
			or lower_name.contains("systemmenu")
		):
			return true
		current = current.get_parent()
	return false


## Sorts clusters into distinct priority buckets
## (Front -> Sides -> Far), sorting by distance ascending.
## [param camera] The viewing [Camera3D].
## [param view_pos] Global coordinates of the camera.
## [param clusters] Array of clustered entity dictionaries.
func _sort_clusters_prioritized(
	camera: Camera3D, view_pos: Vector3, clusters: Array[Dictionary]
) -> void:
	print("SpatialDescriber: Prioritizing clusters from near to far.")
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	clusters.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var pos_a: Vector3 = a["avg_pos"] as Vector3
			var pos_b: Vector3 = b["avg_pos"] as Vector3
			var dist_a: float = view_pos.distance_to(pos_a)
			var dist_b: float = view_pos.distance_to(pos_b)

			var dir_a: Vector3 = (
				Vector3(pos_a.x - view_pos.x, 0.0, pos_a.z - view_pos.z).normalized()
			)
			var dir_b: Vector3 = (
				Vector3(pos_b.x - view_pos.x, 0.0, pos_b.z - view_pos.z).normalized()
			)

			var dot_a: float = forward.dot(dir_a)
			var dot_b: float = forward.dot(dir_b)

			var priority_a: int = _get_cluster_priority(dist_a, dot_a)
			var priority_b: int = _get_cluster_priority(dist_b, dot_b)

			if priority_a != priority_b:
				return priority_a < priority_b

			return dist_a < dist_b
	)


## Assigns an integer priority rank based on distance and forward alignment.
## [param dist] Euclidean distance to target in meters.
## [param dot_fwd] Horizontal dot product with camera forward.
## [return] Numerical priority (0 = Front near, 1 = Sides near, 2 = Far).
func _get_cluster_priority(dist: float, dot_fwd: float) -> int:
	if dist <= nearby_distance_threshold:
		if dot_fwd >= 0.4:
			return 0
		return 1
	return 2


## Groups nearby identical objects into single counted clusters.
## [param targets] List of individual validated target dictionaries.
## [return] An array of clustered items with average positions.
func _cluster_targets(targets: Array[Dictionary]) -> Array[Dictionary]:
	print("SpatialDescriber: Clustering %d detected targets." % targets.size())
	var clusters: Array[Dictionary] = []

	for target: Dictionary in targets:
		var target_name: String = target["name"] as String
		var target_pos: Vector3 = target["position"] as Vector3
		var found_cluster: bool = false

		for cluster: Dictionary in clusters:
			if (cluster["name"] as String) == target_name:
				var center: Vector3 = cluster["avg_pos"] as Vector3
				if center.distance_to(target_pos) <= cluster_distance_threshold:
					var old_count: int = cluster["count"] as int
					var new_count: int = old_count + 1
					var total_pos: Vector3 = (center * float(old_count)) + target_pos
					cluster["avg_pos"] = total_pos / float(new_count)
					cluster["count"] = new_count
					found_cluster = true
					break

		if not found_cluster:
			clusters.append({"name": target_name, "count": 1, "avg_pos": target_pos})

	return clusters


## Determines relative direction and
## vertical elevation relative to camera orientation and ground level.
## [param camera] The viewing [Camera3D].
## [param view_pos] The eye-level camera position.
## [param target_pos] Global coordinates of the target entity.
## [param ground_y] Ground-level Y elevation representing the player's walking plane.
## [return] An intuitive spatial direction string.
func _get_relative_direction(
	camera: Camera3D, view_pos: Vector3, target_pos: Vector3, ground_y: float
) -> String:
	print("SpatialDescriber: Calculating relative direction.")
	var forward: Vector3 = -camera.global_transform.basis.z
	var right: Vector3 = camera.global_transform.basis.x

	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var diff: Vector3 = target_pos - view_pos
	var to_target_horiz: Vector3 = Vector3(diff.x, 0.0, diff.z).normalized()

	var dot_forward: float = forward.dot(to_target_horiz)
	var dot_right: float = right.dot(to_target_horiz)

	var horiz_phrase: String = ""
	if dot_forward > 0.85:
		horiz_phrase = "directly ahead"
	elif dot_forward > 0.4:
		horiz_phrase = ("slightly to your right" if dot_right > 0.0 else "slightly to your left")
	elif dot_forward > -0.4:
		horiz_phrase = "to your right" if dot_right > 0.0 else "to your left"
	elif dot_forward > -0.85:
		horiz_phrase = ("behind you to the right" if dot_right > 0.0 else "behind you to the left")
	else:
		horiz_phrase = "directly behind you"

	# If elevated above eye level (e.g., catwalks, high shelves, ceilings)
	if (target_pos.y - view_pos.y) > above_elevation_threshold:
		return "above you " + horiz_phrase

	# If significantly below the player's standing floor (e.g., pits, stairwells)
	if target_pos.y < (ground_y - below_ground_threshold):
		return "below you " + horiz_phrase

	return horiz_phrase


## Resolves an accessible English display name from properties, mesh references, or node hierarchy.
## [param target_node] Target [Node3D] being examined.
## [return] A human-friendly string name.
func _resolve_display_name(target_node: Node3D) -> String:
	if target_node is PickableObject:
		var pickable: PickableObject = target_node as PickableObject
		if pickable.has_method("_get_clean_mesh_name"):
			var clean_mesh: String = pickable._get_clean_mesh_name()
			if clean_mesh != "object":
				return clean_mesh

	if target_node.has_meta(&"display_name"):
		return _clean_name(str(target_node.get_meta(&"display_name")))
	if "display_name" in target_node and not str(target_node.display_name).is_empty():
		return _clean_name(str(target_node.display_name))

	if "mesh" in target_node:
		var raw_mesh_prop: Variant = target_node.get("mesh")
		var resolved_mesh_node: Node = null

		if raw_mesh_prop is Node:
			resolved_mesh_node = raw_mesh_prop as Node
		elif raw_mesh_prop is NodePath and not (raw_mesh_prop as NodePath).is_empty():
			resolved_mesh_node = target_node.get_node_or_null(raw_mesh_prop as NodePath)

		if is_instance_valid(resolved_mesh_node):
			var prop_name: String = resolved_mesh_node.name
			if not _is_generic_name(prop_name):
				return _clean_name(prop_name)

	var child_mesh_name: String = _find_mesh_name(target_node)
	if not child_mesh_name.is_empty():
		return _clean_name(child_mesh_name)

	return _clean_name(target_node.name)


## Recursively searches for instantiated sub-scenes or descriptive mesh instances.
## [param current_node] The [Node] to inspect.
## [return] The resolved mesh name string, or an empty string if none found.
func _find_mesh_name(current_node: Node) -> String:
	for child: Node in current_node.get_children():
		var raw_name: String = child.name

		if _is_generic_name(raw_name):
			var nested_name: String = _find_mesh_name(child)
			if not nested_name.is_empty():
				return nested_name
			continue

		if not child.scene_file_path.is_empty():
			return raw_name

		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			if is_instance_valid(mi.mesh) and not mi.mesh.resource_name.is_empty():
				return mi.mesh.resource_name
			return raw_name

		var found_name: String = _find_mesh_name(child)
		if not found_name.is_empty():
			return found_name

	return ""


## Evaluates whether a node name is an engine default placeholder or structural component.
## [param node_name] The raw node name to evaluate.
## [return] True if the name matches generic structural patterns.
func _is_generic_name(node_name: String) -> bool:
	var lower_name: String = node_name.to_lower()
	return (
		lower_name.begins_with("meshinstance3d")
		or lower_name == "mesh"
		or lower_name.begins_with("probecontainer")
		or lower_name.begins_with("marker3d")
		or lower_name.begins_with("collisionshape3d")
		or lower_name.begins_with("label3d")
		or lower_name.begins_with("interactcomponent")
		or lower_name.begins_with("highlightcomponent")
		or lower_name == "pickable object"
		or lower_name == "object"
	)


## Performs multi-point raycasts between camera view position and target to avoid railing clipping.
## [param space_state] Direct 3D physics space state.
## [param view_pos] Eye-level coordinates of the camera.
## [param target_node] Target [Node3D] to verify visibility towards.
## [param origin_node] The observer node to exclude from ray hits.
## [return] True if all test points on the target are occluded.
func _is_occluded(
	space_state: PhysicsDirectSpaceState3D,
	view_pos: Vector3,
	target_node: Node3D,
	origin_node: Node3D
) -> bool:
	var target_base: Vector3 = target_node.global_position
	var test_points: Array[Vector3] = [
		target_base + Vector3(0.0, 0.5, 0.0),
		target_base + Vector3(0.0, 0.9, 0.0),
		target_base + Vector3(0.0, 0.2, 0.0)
	]

	var exclusions: Array[RID] = []
	_collect_collision_rids(target_node, exclusions)
	_collect_collision_rids(origin_node, exclusions)

	for point: Vector3 in test_points:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			view_pos, point, occlusion_collision_mask
		)
		query.exclude = exclusions

		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			return false

	return true


## Recursively collects physics RIDs from a node tree to exclude them from raycasting.
## [param node] Root [Node] to gather collision objects from.
## [param rids] Array to append found [RID] references into.
func _collect_collision_rids(node: Node, rids: Array[RID]) -> void:
	if not is_instance_valid(node):
		return
	if node is CollisionObject3D:
		rids.append((node as CollisionObject3D).get_rid())
	for child: Node in node.get_children():
		_collect_collision_rids(child, rids)


## Cleans digits, symbols, camelCase, and separators from an identifier to make it human-readable.
## [param raw_name] The raw identifier string to sanitize.
## [return] A formatted string with spaces.
func _clean_name(raw_name: String) -> String:
	var separated_name: String = _regex_camel.sub(raw_name, "$1 $2", true)
	return _regex_symbols.sub(separated_name.to_lower(), " ", true).strip_edges()


## Pluralizes a noun phrase if the count is greater than one.
## [param item_name] The singular noun description.
## [param count] Number of items in the cluster.
## [return] Formatted count and noun string.
func _format_plural(item_name: String, count: int) -> String:
	if count == 1:
		return "1 " + item_name

	if item_name.ends_with("box"):
		return "%d %ses" % [count, item_name]
	if item_name.ends_with("y") and not item_name.ends_with("ey"):
		return "%d %sies" % [count, item_name.left(-1)]
	if item_name.ends_with("s"):
		return "%d %s" % [count, item_name]

	return "%d %ss" % [count, item_name]


## Dispatches the compiled description string to TTSManager.
## [param speech_text] The text prompt for synthesis.
func _speak(speech_text: String) -> void:
	print("SpatialDescriber: _speak() called with text: ", speech_text)
	if has_node("/root/TTSManager"):
		var tts: Node = get_node("/root/TTSManager")
		if tts.has_method("speak"):
			tts.speak(speech_text)
			print("SpatialDescriber: Dispatched speech to TTSManager.")
