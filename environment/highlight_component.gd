## Applies an outline material to target meshes when the parent interactable is focused.
##
## Caches visual geometry in [method _ready]
## to avoid recursive tree walks during interaction events.
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

## Cached geometry instances to prevent expensive runtime tree traversals on interaction.
var _cached_meshes: Array[GeometryInstance3D] = []


## Initializes component connections and caches all target meshes for fast runtime lookup.
func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if not is_instance_valid(interact_component):
		var parent: Node = get_parent()
		if is_instance_valid(parent):
			interact_component = parent.get_node_or_null("InteractComponent")

	if is_instance_valid(interact_component):
		interact_component.focused.connect(_on_focus)
		interact_component.unfocused.connect(_on_unfocus)
	else:
		print("HighlightComponent: No InteractComponent assigned or found in parent!")

	_cache_target_meshes()


## Caches explicitly assigned meshes or discovers them once during scene initialization.
func _cache_target_meshes() -> void:
	_cached_meshes.clear()

	if target_meshes.size() > 0:
		for m: GeometryInstance3D in target_meshes:
			if is_instance_valid(m):
				_cached_meshes.append(m)
		return

	var parent: Node = get_parent()
	if not is_instance_valid(parent):
		return

	var mesh_nodes: Array[Node] = parent.find_children("*", "MeshInstance3D")
	for m: Node in mesh_nodes:
		if is_instance_valid(m) and m is GeometryInstance3D:
			_cached_meshes.append(m as GeometryInstance3D)

	var csg_nodes: Array[Node] = parent.find_children("*", "CSGShape3D")
	for c: Node in csg_nodes:
		if is_instance_valid(c) and c is GeometryInstance3D:
			_cached_meshes.append(c as GeometryInstance3D)


## Callback triggered when the interactable gains player focus.
func _on_focus() -> void:
	print("HighlightComponent: Target actively focused by player.")
	_is_focused = true
	if not _is_suppressed:
		_update_materials(outline_material)


## Callback triggered when the interactable loses player focus.
func _on_unfocus() -> void:
	print("HighlightComponent: Target unfocused by player.")
	_is_focused = false
	_update_materials(null)


## Temporarily suppresses or restores the highlight state based on game events.
## [param state] True to suppress highlights; false to restore focus state.
func suppress(state: bool) -> void:
	_is_suppressed = state
	if _is_suppressed:
		_update_materials(null)
	elif _is_focused:
		_update_materials(outline_material)


## Applies or clears the outline material across all cached geometry targets.
## [param mat] The material to apply, or null to clear highlights.
func _update_materials(mat: Material) -> void:
	for m: GeometryInstance3D in _cached_meshes:
		if is_instance_valid(m):
			_apply_to_mesh(m, mat)


## Instantiates or cleans up child overlay nodes and updates bounds on the target mesh.
## [param base_mesh] The target mesh receiving the outline.
## [param mat] The outline material to set, or null to remove existing outlines.
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

				if hl_mesh.mesh is QuadMesh or hl_mesh.mesh is PlaneMesh:
					is_flat = true

			elif base_mesh is CSGShape3D:
				var csg_data: Array = base_mesh.get_meshes()
				if csg_data.size() == 2 and csg_data[1] is ArrayMesh:
					hl_mesh.transform = csg_data[0]
					hl_mesh.mesh = csg_data[1]

			base_mesh.add_child(hl_mesh)

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
