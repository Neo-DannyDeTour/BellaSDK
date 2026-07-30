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

## Tracks whether the highlight effect is temporarily disabled or overridden by game events.
var _is_suppressed: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	#print("HighlightComponent: Initializing component.")

	if not is_instance_valid(interact_component):
		var parent: Node = get_parent()
		if is_instance_valid(parent):
			interact_component = parent.get_node_or_null("InteractComponent")

	if is_instance_valid(interact_component):
		interact_component.focused.connect(_on_focus)
		interact_component.unfocused.connect(_on_unfocus)
		#print("HighlightComponent: Successfully connected to InteractComponent.")
	else:
		print("HighlightComponent: No InteractComponent assigned or found in parent!")


func _on_focus() -> void:
	print("HighlightComponent: Target actively focused by player.")
	_is_focused = true
	if not _is_suppressed:
		_update_materials(outline_material)


func _on_unfocus() -> void:
	print("HighlightComponent: Target unfocused by player.")
	_is_focused = false
	_update_materials(null)


func suppress(state: bool) -> void:
	#print("HighlightComponent: Suppress state forcefully changed to: ", state)
	_is_suppressed = state
	if _is_suppressed:
		_update_materials(null)
	elif _is_focused:
		_update_materials(outline_material)


func _update_materials(mat: Material) -> void:
	var actually_applied: int = 0

	if target_meshes.size() > 0:
		for m: GeometryInstance3D in target_meshes:
			if is_instance_valid(m):
				_apply_to_mesh(m, mat)
				actually_applied += 1

	if actually_applied == 0:
		var parent: Node = get_parent()
		if is_instance_valid(parent):
			var all_hidden_meshes: Array[Node] = parent.find_children("*", "MeshInstance3D")
			for m: Node in all_hidden_meshes:
				if is_instance_valid(m) and m is GeometryInstance3D:
					_apply_to_mesh(m as GeometryInstance3D, mat)

			var all_hidden_csg: Array[Node] = parent.find_children("*", "CSGShape3D")
			for c: Node in all_hidden_csg:
				if is_instance_valid(c) and c is GeometryInstance3D:
					_apply_to_mesh(c as GeometryInstance3D, mat)


func _apply_to_mesh(base_mesh: GeometryInstance3D, mat: Material) -> void:
	var child_name: String = "HighlightOverlayChild"

	if mat != null:
		print("HighlightComponent: Spawning highlight mesh on: ", base_mesh.name)
		if not base_mesh.has_node(child_name):
			var hl_mesh: MeshInstance3D = MeshInstance3D.new()
			hl_mesh.name = child_name
			hl_mesh.material_override = mat
			hl_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			var is_flat: bool = false

			if base_mesh is MeshInstance3D:
				hl_mesh.mesh = base_mesh.mesh
				if base_mesh.skeleton:
					hl_mesh.skeleton = base_mesh.skeleton
				if base_mesh.skin:
					hl_mesh.skin = base_mesh.skin

				# Detect if the mesh is a flat surface
				if hl_mesh.mesh is QuadMesh or hl_mesh.mesh is PlaneMesh:
					is_flat = true

			elif base_mesh is CSGShape3D:
				var csg_data: Array = base_mesh.get_meshes()
				if csg_data.size() == 2 and csg_data[1] is ArrayMesh:
					hl_mesh.transform = csg_data[0]
					hl_mesh.mesh = csg_data[1]

			base_mesh.add_child(hl_mesh)

			# Optimized 60 FPS Instance Parameter Routing
			# Enables billboarding ONLY if the mesh is flat.
			if is_flat:
				hl_mesh.set_instance_shader_parameter("is_billboard", true)
			else:
				hl_mesh.set_instance_shader_parameter("is_billboard", false)

		base_mesh.custom_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	else:
		print("HighlightComponent: Removing highlight mesh from: ", base_mesh.name)
		var existing_hl: Node = base_mesh.get_node_or_null(child_name)
		if is_instance_valid(existing_hl):
			existing_hl.queue_free()

		base_mesh.custom_aabb = AABB()
