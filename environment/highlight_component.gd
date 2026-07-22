class_name HighlightComponent
extends Node

## The shader material applied as an outline when the target is focused.
@export var outline_material: ShaderMaterial

## Array of specific meshes to highlight. Leave empty to auto-detect FBX/GLTF/OBJ/CSG nodes.
@export var target_meshes: Array[GeometryInstance3D]

## The component handling interaction logic. Assign in the inspector for optimal performance.
@export var interact_component: Node

## Tracks whether the current target is actively being focused on by the player.
var _is_focused: bool = false

## Tracks whether the highlight effect is temporarily disabled or overridden.
var _is_suppressed: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	print("HighlightComponent: Initializing component.")

	# Optimized check: Prefer the exported variable, fallback to string lookup only if unassigned.
	if not is_instance_valid(interact_component):
		var parent: Node = get_parent()
		if is_instance_valid(parent):
			interact_component = parent.get_node_or_null("InteractComponent")

	if is_instance_valid(interact_component):
		interact_component.focused.connect(_on_focus)
		interact_component.unfocused.connect(_on_unfocus)
		print("HighlightComponent: Successfully connected to InteractComponent.")
	else:
		#push_warning("HighlightComponent: No InteractComponent assigned or found in parent!")
		print("HighlightComponent: No InteractComponent assigned or found in parent!")


func _on_focus() -> void:
	print("HighlightComponent: Target focused.")
	_is_focused = true
	if not _is_suppressed:
		_update_materials(outline_material)


func _on_unfocus() -> void:
	print("HighlightComponent: Target unfocused.")
	_is_focused = false
	_update_materials(null)


func suppress(state: bool) -> void:
	#print("HighlightComponent: Suppress state changed to: ", state)
	_is_suppressed = state
	if _is_suppressed:
		_update_materials(null)
	elif _is_focused:
		_update_materials(outline_material)


func _update_materials(mat: Material) -> void:
	var actually_applied: int = 0

	# 1. Assigned meshes (Supports both MeshInstance3D and CSGShape3D)
	if target_meshes.size() > 0:
		for m: GeometryInstance3D in target_meshes:
			if is_instance_valid(m):
				_apply_to_mesh(m, mat)
				actually_applied += 1

	# 2. THE FBX/OBJ/CSG MAGIC
	if actually_applied == 0:
		var parent: Node = get_parent()
		if is_instance_valid(parent):
			# Grab standard meshes
			var all_hidden_meshes: Array[Node] = parent.find_children("*", "MeshInstance3D")
			for m: Node in all_hidden_meshes:
				if is_instance_valid(m) and m is GeometryInstance3D:
					_apply_to_mesh(m as GeometryInstance3D, mat)

			# Grab CSG meshes so your blockouts highlight properly
			var all_hidden_csg: Array[Node] = parent.find_children("*", "CSGShape3D")
			for c: Node in all_hidden_csg:
				if is_instance_valid(c) and c is GeometryInstance3D:
					_apply_to_mesh(c as GeometryInstance3D, mat)


func _apply_to_mesh(base_mesh: GeometryInstance3D, mat: Material) -> void:
	var child_name: String = "HighlightOverlayChild"

	if mat != null:
		# Instead of overwriting `material_overlay`, we spawn a lightweight duplicate child mesh
		if not base_mesh.has_node(child_name):
			var hl_mesh: MeshInstance3D = MeshInstance3D.new()
			hl_mesh.name = child_name
			hl_mesh.material_override = mat
			hl_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			if base_mesh is MeshInstance3D:
				hl_mesh.mesh = base_mesh.mesh
				if base_mesh.skeleton:
					hl_mesh.skeleton = base_mesh.skeleton
				if base_mesh.skin:
					hl_mesh.skin = base_mesh.skin
			elif base_mesh is CSGShape3D:
				# Extract the exact baked mesh from the CSG node
				var csg_data: Array = base_mesh.get_meshes()
				if csg_data.size() == 2 and csg_data[1] is ArrayMesh:
					hl_mesh.transform = csg_data[0]
					hl_mesh.mesh = csg_data[1]

			base_mesh.add_child(hl_mesh)

		base_mesh.custom_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	else:
		# Unfocus: safely delete the child highlight mesh
		var existing_hl: Node = base_mesh.get_node_or_null(child_name)
		if is_instance_valid(existing_hl):
			existing_hl.queue_free()

		base_mesh.custom_aabb = AABB()
