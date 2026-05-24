class_name HighlightComponent
extends Node

@export var outline_material: ShaderMaterial
## Leave this EMPTY for FBX/GLTF/OBJ files! The script will find them automatically.
## Updated to GeometryInstance3D so you can drag-and-drop CSG meshes here too!
@export var target_meshes: Array[GeometryInstance3D]

var _is_focused: bool = false
var _is_suppressed: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	var interact := get_parent().get_node_or_null("Interact_Component")
	if interact:
		interact.focused.connect(_on_focus)
		interact.unfocused.connect(_on_unfocus)
	else:
		push_warning("HighlightComponent: No Interact_Component found in parent!")


func _on_focus() -> void:
	_is_focused = true
	if not _is_suppressed:
		_update_materials(outline_material)


func _on_unfocus() -> void:
	_is_focused = false
	_update_materials(null)


func suppress(state: bool) -> void:
	_is_suppressed = state
	if _is_suppressed:
		_update_materials(null)
	elif _is_focused:
		_update_materials(outline_material)


func _update_materials(mat: Material) -> void:
	var actually_applied: int = 0

	# 1. Assigned meshes (Supports both MeshInstance3D and CSGShape3D)
	if target_meshes.size() > 0:
		for m in target_meshes:
			if m != null:
				_apply_to_mesh(m, mat)
				actually_applied += 1

	# 2. THE FBX/OBJ/CSG MAGIC
	if actually_applied == 0:
		# Grab standard meshes
		var all_hidden_meshes := get_parent().find_children("*", "MeshInstance3D")
		for m in all_hidden_meshes:
			_apply_to_mesh(m as GeometryInstance3D, mat)

		# Grab CSG meshes so your blockouts highlight properly!
		var all_hidden_csg := get_parent().find_children("*", "CSGShape3D")
		for c in all_hidden_csg:
			_apply_to_mesh(c as GeometryInstance3D, mat)


# --- THE FIX ---
func _apply_to_mesh(base_mesh: GeometryInstance3D, mat: Material) -> void:
	var child_name := "HighlightOverlayChild"

	if mat != null:
		# Instead of overwriting `material_overlay` (which deletes your green wireframes),
		# we spawn a lightweight duplicate child mesh dedicated purely to the highlight outline.
		if not base_mesh.has_node(child_name):
			var hl_mesh := MeshInstance3D.new()
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
					hl_mesh.transform = csg_data[0]  # Apply internal offset
					hl_mesh.mesh = csg_data[1]

			base_mesh.add_child(hl_mesh)

		base_mesh.custom_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	else:
		# Unfocus: safely delete the child highlight mesh
		var existing_hl := base_mesh.get_node_or_null(child_name)
		if existing_hl:
			existing_hl.queue_free()

		base_mesh.custom_aabb = AABB()
