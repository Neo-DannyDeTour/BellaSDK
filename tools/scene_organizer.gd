@tool
## Organizes level nodes under [Entities] and applies project collision layers.
class_name SceneOrganizer
extends EditorScript


## Executes scene reorganization and enforces standardized collision masks.
func _run() -> void:
	print("SceneOrganizer: Reorganizing scene tree into clean categories...")
	var root: Node = EditorInterface.get_edited_scene_root()
	if not is_instance_valid(root):
		push_error("SceneOrganizer: Open testbed2 in the editor before running.")
		return

	# Create top-level folders and move them to index 0 and 1 so they appear at the top
	var landmarks: Node3D = _get_or_create_container(root, "Landmarks")
	var entities: Node3D = _get_or_create_container(root, "Entities")
	root.move_child(landmarks, 0)
	root.move_child(entities, 1)

	# Subcategory containers under Entities
	var doors: Node3D = _get_or_create_container(entities, "Doors")
	var puzzles: Node3D = _get_or_create_container(entities, "InteractivePuzzles")
	var pickups: Node3D = _get_or_create_container(entities, "Pickups")
	var enemies: Node3D = _get_or_create_container(entities, "Enemies")
	var props: Node3D = _get_or_create_container(entities, "Props")
	var triggers: Node3D = _get_or_create_container(entities, "Triggers")
	var vfx: Node3D = _get_or_create_container(entities, "VFX_Audio")

	var children_to_process: Array[Node] = []
	for child: Node in root.get_children():
		# Do not touch core managers, player, or the folders themselves
		if child in [landmarks, entities] or child.name == "VirtualChunkManager":
			continue
		if child is WorldEnvironment or child is DirectionalLight3D or child.name == "Player":
			continue
		children_to_process.append(child)

	for child: Node in children_to_process:
		var target: Node3D = _classify_node(
			child, landmarks, doors, puzzles, pickups, enemies, props, triggers, vfx
		)
		if is_instance_valid(target):
			_safe_reparent(child, target)
			_assign_category_layers(child, target)

	EditorInterface.mark_scene_as_unsaved()
	print("SceneOrganizer: Reorganization complete. Check top of Scene tree!")


## Categorizes [param node] to its corresponding entity container based on name and path.
func _classify_node(
	node: Node,
	landmarks: Node3D,
	doors: Node3D,
	puzzles: Node3D,
	pickups: Node3D,
	enemies: Node3D,
	props: Node3D,
	triggers: Node3D,
	vfx: Node3D
) -> Node3D:
	var path: String = node.scene_file_path.to_lower()
	var node_name: String = node.name.to_lower()
	var combined: String = path + " " + node_name

	# 1. Landmarks
	if (
		node is CSGTorus3D
		or combined.contains("torus")
		or combined.contains("citadel")
		or combined.contains("ocean")
	):
		if not node.is_in_group("landmark"):
			node.add_to_group("landmark", true)
		return landmarks

	# 2. Doors & Gates
	if combined.contains("door") or combined.contains("gate"):
		return doors

	# 3. Enemies & Hazard Traps
	if (
		combined.contains("enemy")
		or combined.contains("turret")
		or combined.contains("drone")
		or combined.contains("guardian")
		or combined.contains("trap")
		or combined.contains("killfield")
		or combined.contains("fire")
		or combined.contains("tentacle")
		or combined.contains("flying_tile")
	):
		return enemies

	# 4. Weapons & Pickups
	if (
		combined.contains("pickup")
		or combined.contains("pickable")
		or combined.contains("weapon")
		or combined.contains("shotgun")
		or combined.contains("revolver")
		or combined.contains("ammo")
		or combined.contains("keycard")
		or combined.contains("glider")
		or combined.contains("upgrade")
		or combined.contains("cell")
	):
		return pickups

	# 5. Interactive Puzzles & Mechanics
	if (
		combined.contains("valve")
		or combined.contains("button")
		or combined.contains("puzzle")
		or combined.contains("laser")
		or combined.contains("mirror")
		or combined.contains("lock")
		or combined.contains("lever")
		or combined.contains("bridge")
		or combined.contains("pulley")
		or combined.contains("plug")
		or combined.contains("socket")
		or combined.contains("wheel")
	):
		return puzzles

	# 6. Triggers & Checkpoints
	if combined.contains("trigger") or combined.contains("checkpoint"):
		return triggers

	# 7. VFX, Audio & Environment Logic
	if (
		combined.contains("vfx")
		or combined.contains("smoke")
		or combined.contains("soundscape")
		or combined.contains("blood")
		or combined.contains("fog")
		or combined.contains("leak")
		or combined.contains("lightlogic")
		or combined.contains("lightsequence")
		or combined.contains("rain")
		or combined.contains("waterfall")
	):
		return vfx

	# 8. World Props & Traversals
	if (
		combined.contains("box")
		or combined.contains("barrel")
		or combined.contains("cart")
		or combined.contains("table")
		or combined.contains("torch")
		or combined.contains("glass")
		or combined.contains("rope")
		or combined.contains("ladder")
		or combined.contains("fence")
		or combined.contains("stairs")
		or combined.contains("monke")
		or combined.contains("prop")
		or combined.contains("interact")
		or combined.contains("obstacle")
		or combined.contains("building")
	):
		return props

	return null


## Dispatches layer assignment according to target category container.
func _assign_category_layers(node: Node, target_parent: Node3D) -> void:
	match target_parent.name:
		"Landmarks":
			_apply_layers(
				node,
				CollisionLayers.LAYER_ENVIRONMENT_IDX,
				CollisionLayers.RENDER_LAYER_ENVIRONMENT_IDX
			)
		"Doors", "InteractivePuzzles", "Pickups", "Props":
			_apply_layers(
				node,
				CollisionLayers.LAYER_INTERACTIVE_IDX,
				CollisionLayers.RENDER_LAYER_INTERACTIVE_IDX
			)
		"Enemies":
			_apply_layers(
				node,
				CollisionLayers.LAYER_ENEMIES_IDX,
				CollisionLayers.RENDER_LAYER_ENVIRONMENT_IDX
			)
		"Triggers", "VFX_Audio":
			_apply_layers(
				node,
				CollisionLayers.LAYER_ENVIRONMENT_IDX,
				CollisionLayers.RENDER_LAYER_ENVIRONMENT_IDX
			)


## Applies physics collision and render layers recursively through [param node].
func _apply_layers(node: Node, physics_layer: int, render_layer: int) -> void:
	var phys_mask: int = CollisionLayers.layer_to_mask(physics_layer)
	var rend_mask: int = CollisionLayers.layer_to_mask(render_layer)

	var phys_nodes: Array[Node] = []
	if node is CollisionObject3D:
		phys_nodes.append(node)
	phys_nodes.append_array(node.find_children("", "CollisionObject3D", true, false))

	for col_obj: Node in phys_nodes:
		var c_obj: CollisionObject3D = col_obj as CollisionObject3D
		if is_instance_valid(c_obj):
			c_obj.collision_layer = phys_mask

	var visual_nodes: Array[Node] = []
	if node is VisualInstance3D:
		visual_nodes.append(node)
	visual_nodes.append_array(node.find_children("", "VisualInstance3D", true, false))

	for vis_obj: Node in visual_nodes:
		var v_obj: VisualInstance3D = vis_obj as VisualInstance3D
		if is_instance_valid(v_obj):
			v_obj.layers = rend_mask


## Finds or instantiates an identity container [Node3D] under [param parent].
func _get_or_create_container(parent: Node, container_name: String) -> Node3D:
	var existing: Node = parent.get_node_or_null(container_name)
	if is_instance_valid(existing) and existing is Node3D:
		return existing as Node3D

	var container: Node3D = Node3D.new()
	container.name = container_name
	parent.add_child(container)
	container.owner = EditorInterface.get_edited_scene_root()
	return container


## Safely reparents [param node] to [param new_parent] keeping global transformation.
func _safe_reparent(node: Node, new_parent: Node) -> void:
	if not is_instance_valid(node) or not is_instance_valid(new_parent):
		return
	if node.get_parent() == new_parent:
		return

	var node_3d: Node3D = node as Node3D
	var prev_transform: Transform3D = Transform3D.IDENTITY
	if is_instance_valid(node_3d):
		prev_transform = node_3d.global_transform

	node.get_parent().remove_child(node)
	new_parent.add_child(node)
	node.owner = EditorInterface.get_edited_scene_root()

	if is_instance_valid(node_3d):
		node_3d.global_transform = prev_transform
