extends Node

## Dictionary mapping scene group names to their required high-contrast colors.
var _group_colors: Dictionary = {
	#"player": Color(0.0, 0.0, 1.0, 1.0),       # Blue silhouette for the player
	"enemies": Color(1.0, 0.0, 0.0, 1.0),  # Red silhouette for threats
	"interactables": Color(1.0, 1.0, 0.0, 1.0),  # Yellow silhouette for items/doors
	"traversal": Color(0.0, 1.0, 0.0, 1.0)  # Green silhouette for ladders/monkey bars
}

## Caches the instantiated unshaded materials so they are only created once at startup.
var _group_materials: Dictionary = {}

## Tracks the current active state so dynamically spawned objects can be highlighted instantly.
var is_active: bool = false


func _ready() -> void:
	print("VisionAssistManager: Initializing AAA high contrast materials.")

	# Pre-generate materials for 60 FPS performance
	for group_name: String in _group_colors.keys():
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = _group_colors[group_name]
		mat.no_depth_test = true  # Forces rendering through walls
		mat.render_priority = 100
		_group_materials[group_name] = mat

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("vision_assist_toggled"):
			events.vision_assist_toggled.connect(_on_vision_assist_toggled)

	# Listen for newly instantiated scenes (e.g., dynamically spawned traps)
	get_tree().node_added.connect(_on_scene_node_added)


func _on_vision_assist_toggled(toggled_on: bool) -> void:
	print("VisionAssistManager: Applying AAA overlays across all groups. Active: ", toggled_on)
	is_active = toggled_on

	# Loop through each registered group and apply their specific colored material
	for group_name: String in _group_materials.keys():
		var target_material: StandardMaterial3D = _group_materials[group_name]
		var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)

		for node: Node in nodes:
			_apply_overlay_to_meshes(node, is_active, target_material)


func _on_scene_node_added(node: Node) -> void:
	# If the setting is off, do nothing when a new object spawns
	if not is_active:
		return

	# Wait until the new scene and all its child meshes are fully built in the tree
	if not node.is_node_ready():
		await node.ready

	# Double check active state post-yield to prevent race conditions
	if not is_active:
		return

	# Check if the newly spawned root node belongs to any of our tracked groups
	for group_name: String in _group_materials.keys():
		if node.is_in_group(group_name):
			print("VisionAssistManager: Applying overlay to dynamically spawned node: ", node.name)
			_apply_overlay_to_meshes(node, true, _group_materials[group_name])
			break  # No need to check other groups if a match is found


func _apply_overlay_to_meshes(
	target_node: Node, active_state: bool, target_material: StandardMaterial3D
) -> void:
	# 1. GeometryInstance3D safely captures MeshInstance3D, CSGShape3D, and MultiMeshInstance3D
	if target_node is GeometryInstance3D:
		target_node.material_overlay = target_material if active_state else null

	# 2. Unconditionally recurse through ALL children.
	# (This ensures nested sub-meshes are never skipped).
	for child: Node in target_node.get_children():
		_apply_overlay_to_meshes(child, active_state, target_material)
