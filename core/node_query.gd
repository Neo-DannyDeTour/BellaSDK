## Fast hierarchical traversal and spatial query utilities in [NodeQuery].
class_name NodeQuery
extends Object


## Traverses up the scene tree to find an ancestor node matching [param target_type].
static func find_ancestor_of_type(node: Node, target_type: Variant) -> Node:
	if not is_instance_valid(node):
		return null
	var current: Node = node.get_parent()
	while is_instance_valid(current):
		if is_instance_of(current, target_type):
			return current
		current = current.get_parent()
	return null


## Traverses up the scene tree to find an ancestor belonging to [param group_name].
static func find_ancestor_in_group(node: Node, group_name: StringName) -> Node:
	if not is_instance_valid(node):
		return null
	var current: Node = node.get_parent()
	while is_instance_valid(current):
		if current.is_in_group(group_name):
			return current
		current = current.get_parent()
	return null


## Traverses up the scene tree to find an ancestor implementing [param method_name].
static func find_ancestor_with_method(node: Node, method_name: StringName) -> Node:
	if not is_instance_valid(node):
		return null
	var current: Node = node.get_parent()
	while is_instance_valid(current):
		if current.has_method(method_name):
			return current
		current = current.get_parent()
	return null


## Traverses up the scene tree to find an ancestor defining [param meta_name].
static func find_ancestor_with_meta(node: Node, meta_name: StringName) -> Node:
	if not is_instance_valid(node):
		return null
	var current: Node = node.get_parent()
	while is_instance_valid(current):
		if current.has_meta(meta_name):
			return current
		current = current.get_parent()
	return null


## Finds the first immediate child matching [param target_type].
static func find_first_child_of_type(node: Node, target_type: Variant) -> Node:
	if not is_instance_valid(node):
		return null
	for child in node.get_children():
		if is_instance_of(child, target_type):
			return child
	return null


## Collects all immediate children matching [param target_type].
static func find_children_of_type(node: Node, target_type: Variant) -> Array[Node]:
	var result: Array[Node] = []
	if not is_instance_valid(node):
		return result
	for child in node.get_children():
		if is_instance_of(child, target_type):
			result.append(child)
	return result


## Collects all immediate children belonging to [param group_name].
static func find_children_in_group(node: Node, group_name: StringName) -> Array[Node]:
	var result: Array[Node] = []
	if not is_instance_valid(node):
		return result
	for child in node.get_children():
		if child.is_in_group(group_name):
			result.append(child)
	return result


## Safely retrieves the first node in [param group_name] or null if missing.
static func get_single_node_in_group(tree: SceneTree, group_name: StringName) -> Node:
	if not is_instance_valid(tree):
		return null
	var nodes: Array[Node] = tree.get_nodes_in_group(group_name)
	if nodes.is_empty():
		return null
	return nodes[0]


## Resolves an interactable root entity by inspecting parent chain groups and methods.
static func resolve_interactable_root(collider: Node3D) -> Node3D:
	if not is_instance_valid(collider):
		return null
	if collider.has_method(&"interact") or collider.is_in_group(&"interactable"):
		return collider
	var current: Node = collider.get_parent()
	while is_instance_valid(current):
		if current.has_method(&"interact") or current.is_in_group(&"interactable"):
			return current as Node3D
		current = current.get_parent()
	return collider


## Executes a direct 3D raycast query returning the collision result dictionary.
static func cast_ray(
	space_state: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	collision_mask: int = CollisionLayers.MASK_ENVIRONMENT,
	exclude: Array[RID] = []
) -> Dictionary:
	if space_state == null:
		return {}
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, collision_mask, exclude
	)
	return space_state.intersect_ray(query)
