## Global autoload responsible for generating Text-to-Speech spatial descriptions.
##
## [SpatialDescriber] acts as an accessibility layer that translates the 3D positions
## of surrounding objects into conversational, directional language and routes it
## to the [TTSManager].
## It gathers interactable objects in the player's vicinity, verifies line-of-sight with
## multi-point raycasts, factors in vertical elevation (above/below), groups identical items
## into clusters, and prioritizes items directly in the player's line of sight.
extends Node

## Emitted when an environment description string has been generated.
## [param description_text] The formatted spoken summary string.
signal on_description_generated(description_text: String)

@export_category("Spatial Description Tuning")
## Maximum search radius in meters around the origin node.
@export var description_radius: float = 15.0

## Maximum distance in meters between identical items to be grouped together.
@export var cluster_distance_threshold: float = 2.5

## Maximum number of distinct item clusters announced per sweep to avoid auditory overwhelm.
@export var max_announced_clusters: int = 4

## Collision mask used to filter out occluded items from narration.
@export_flags_3d_physics var occlusion_collision_mask: int = 1

## Default eye-level vertical offset added when origin_node is not a Camera3D.
@export var eye_height_offset: float = 1.5

## Vertical elevation threshold in meters between floor levels before adding
## 'above' or 'below' qualifiers.
@export var vertical_threshold: float = 1.2

## Regular expression used for splitting camelCase identifiers into spaced words.
var _regex_camel: RegEx = RegEx.new()

## Regular expression used for stripping numerical IDs and symbol delimiters from names.
var _regex_symbols: RegEx = RegEx.new()


## Lifecycle method called when the node enters the scene tree.
## Connects to the global event bus if available and precompiles regex patterns.
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
	if not is_instance_valid(origin_node):
		print("SpatialDescriber: Invalid origin node passed.")
		return

	var view_pos: Vector3 = _get_view_position(origin_node)
	var space_state: PhysicsDirectSpaceState3D = origin_node.get_world_3d().direct_space_state
	print("SpatialDescriber: Describing surroundings from viewpoint: ", view_pos)

	var candidate_nodes: Array[Node] = get_tree().get_nodes_in_group(&"interactables")
	var valid_targets: Array[Dictionary] = []
	var visited_ids: Dictionary = {}

	print("SpatialDescriber: Found %d candidate interactables in group." % candidate_nodes.size())

	for item: Node in candidate_nodes:
		if not is_instance_valid(item):
			continue

		var target_3d: Node3D = item as Node3D
		if target_3d == null and item.get_parent() is Node3D:
			target_3d = item.get_parent() as Node3D

		if target_3d == null:
			continue

		var item_id: int = target_3d.get_instance_id()
		if visited_ids.has(item_id):
			continue
		visited_ids[item_id] = true

		var dist: float = view_pos.distance_to(target_3d.global_position)
		if dist > description_radius:
			print("SpatialDescriber: Skipping '%s' (out of range: %.1fm)" % [target_3d.name, dist])
			continue

		if _is_occluded(space_state, view_pos, target_3d, origin_node):
			print("SpatialDescriber: Skipping '%s' (occluded by geometry)" % target_3d.name)
			continue

		var display_name: String = _resolve_display_name(target_3d)
		print("SpatialDescriber: Valid target detected: '%s' at %.1fm" % [display_name, dist])

		valid_targets.append(
			{
				"node": target_3d,
				"name": display_name,
				"position": target_3d.global_position,
				"distance": dist
			}
		)

	if valid_targets.is_empty():
		var empty_msg: String = "No interactables nearby."
		print("SpatialDescriber: Output: ", empty_msg)
		_speak(empty_msg)
		return

	var clusters: Array[Dictionary] = _cluster_targets(valid_targets)
	_sort_clusters_by_field_of_view(origin_node, view_pos, clusters)

	var spoken_segments: Array[String] = []
	var announced_clusters: Array[Dictionary] = clusters.slice(0, max_announced_clusters)

	for cluster: Dictionary in announced_clusters:
		var count: int = cluster["count"] as int
		var item_name: String = cluster["name"] as String
		var avg_pos: Vector3 = cluster["avg_pos"] as Vector3
		var avg_dist: float = view_pos.distance_to(avg_pos)
		var rounded_dist: int = maxi(1, int(roundf(avg_dist)))

		var direction_phrase: String = _get_relative_direction(origin_node, view_pos, avg_pos)
		var label_phrase: String = _format_plural(item_name, count)
		var meter_word: String = "meter" if rounded_dist == 1 else "meters"

		var segment: String = (
			"%s, %d %s %s" % [label_phrase, rounded_dist, meter_word, direction_phrase]
		)
		spoken_segments.append(segment)

	var final_speech: String = "; ".join(spoken_segments) + "."
	print("SpatialDescriber: Output: ", final_speech)
	_speak(final_speech)
	on_description_generated.emit(final_speech)


## Resolves the observer's eye/view position, factoring in Camera3D or vertical eye offsets.
## [param origin_node] The observing [Node3D].
## Returns global coordinates representing eye level.
func _get_view_position(origin_node: Node3D) -> Vector3:
	if origin_node is Camera3D:
		return origin_node.global_position

	var cam: Camera3D = origin_node.find_child("*Camera*", true, false) as Camera3D
	if is_instance_valid(cam):
		return cam.global_position

	return origin_node.global_position + Vector3(0.0, eye_height_offset, 0.0)


## Resolves the observer's floor-level base position.
## [param origin_node] The observing [Node3D].
## Returns global coordinates representing ground/feet level.
func _get_ground_position(origin_node: Node3D) -> Vector3:
	if origin_node is Camera3D:
		return origin_node.global_position - Vector3(0.0, eye_height_offset, 0.0)

	return origin_node.global_position


## Sorts clusters in-place so items in front and line of sight are described first.
## [param origin_node] The viewing orientation reference [Node3D].
## [param view_pos] The eye-level origin position.
## [param clusters] Array of clustered entity dictionaries.
func _sort_clusters_by_field_of_view(
	origin_node: Node3D, view_pos: Vector3, clusters: Array[Dictionary]
) -> void:
	var forward: Vector3 = -origin_node.global_transform.basis.z.normalized()

	clusters.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var to_a: Vector3 = (a["avg_pos"] as Vector3) - view_pos
			var to_b: Vector3 = (b["avg_pos"] as Vector3) - view_pos

			var dist_a_sq: float = to_a.length_squared()
			var dist_b_sq: float = to_b.length_squared()

			var dot_a: float = forward.dot(to_a.normalized()) if dist_a_sq > 0.0001 else 1.0
			var dot_b: float = forward.dot(to_b.normalized()) if dist_b_sq > 0.0001 else 1.0

			if not is_equal_approx(dot_a, dot_b):
				return dot_a > dot_b
			return dist_a_sq < dist_b_sq
	)


## Groups nearby identical objects into single counted clusters.
## [param targets] List of individual validated target dictionaries.
## Returns an array of clustered items with average positions.
func _cluster_targets(targets: Array[Dictionary]) -> Array[Dictionary]:
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


## Determines relative direction and vertical position relative to player orientation.
## [param origin_node] The listener [Node3D].
## [param view_pos] The eye-level origin position.
## [param target_pos] Global coordinates of the target entity.
## Returns an intuitive spatial direction string.
func _get_relative_direction(origin_node: Node3D, view_pos: Vector3, target_pos: Vector3) -> String:
	var forward: Vector3 = -origin_node.global_transform.basis.z
	var right: Vector3 = origin_node.global_transform.basis.x

	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var diff: Vector3 = target_pos - view_pos
	var ground_pos: Vector3 = _get_ground_position(origin_node)
	var floor_height_diff: float = target_pos.y - ground_pos.y

	var to_target_horiz: Vector3 = Vector3(diff.x, 0.0, diff.z).normalized()
	var dot_forward: float = forward.dot(to_target_horiz)
	var dot_right: float = right.dot(to_target_horiz)

	var horiz_phrase: String = ""
	if dot_forward > 0.85:
		horiz_phrase = "directly ahead"
	elif dot_forward > 0.4:
		horiz_phrase = "slightly to your right" if dot_right > 0.0 else "slightly to your left"
	elif dot_forward > -0.4:
		horiz_phrase = "to your right" if dot_right > 0.0 else "to your left"
	elif dot_forward > -0.85:
		horiz_phrase = "behind you to the right" if dot_right > 0.0 else "behind you to the left"
	else:
		horiz_phrase = "directly behind you"

	if floor_height_diff > vertical_threshold:
		return "above you " + horiz_phrase
	if floor_height_diff < -vertical_threshold:
		return "below you " + horiz_phrase

	return horiz_phrase


## Resolves an accessible English display name from properties, mesh references, or node hierarchy.
## [param target_node] Target [Node3D] being examined.
## Returns a human-friendly string name.
func _resolve_display_name(target_node: Node3D) -> String:
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
## Returns the resolved mesh name string, or an empty string if none found.
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
## Returns true if the name matches generic structural patterns.
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
	)


## Performs multi-point raycasts between observer eye level and target to avoid
## railing/ledge clipping.
## [param space_state] Direct 3D physics space state.
## [param view_pos] Eye-level coordinates of the observer.
## [param target_node] Target [Node3D] to verify visibility towards.
## [param origin_node] The observer node to exclude from ray hits.
## Returns true if all test points on the target are occluded.
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
## Returns a formatted string with spaces.
func _clean_name(raw_name: String) -> String:
	var separated_name: String = _regex_camel.sub(raw_name, "$1 $2", true)
	return _regex_symbols.sub(separated_name.to_lower(), " ", true).strip_edges()


## Pluralizes a noun phrase if the count is greater than one.
## [param item_name] The singular noun description.
## [param count] Number of items in the cluster.
## Returns a formatted count and noun string.
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
	if has_node("/root/TTSManager"):
		var tts: Node = get_node("/root/TTSManager")
		if tts.has_method("speak"):
			tts.speak(speech_text)
			print("SpatialDescriber: Dispatched speech to TTSManager.")
