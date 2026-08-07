@tool
extends StaticBody3D
class_name NoteItem

## Stores the text content displayed when the player reads the note.
@export_multiline var note_text: String = ""

## Sets the image texture and instantly updates the mesh in the editor.
@export var note_texture: Texture2D:
	set(value):
		note_texture = value
		_update_appearance()

## Max size in meters for the longest side of the note (0.3 = 30cm).
@export var max_size_meters: float = 0.3:
	set(value):
		max_size_meters = value
		_update_appearance()


func _ready() -> void:
	if not Engine.is_editor_hint():
		print("NoteItem: Spawned in world.")

	_update_appearance()


func _update_appearance() -> void:
	if not is_inside_tree():
		return

	var mesh_node: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if not is_instance_valid(mesh_node) or mesh_node.mesh == null:
		return

	if note_texture:
		# 1. Calculate Aspect Ratio
		var tex_w: float = float(note_texture.get_width())
		var tex_h: float = float(note_texture.get_height())
		var aspect: float = tex_w / tex_h

		# Ensure unique mesh so resizing one note doesn't resize all of them
		if not mesh_node.mesh.resource_local_to_scene:
			mesh_node.mesh = mesh_node.mesh.duplicate()

		# 2. Auto-adjust size without stretching
		if mesh_node.mesh is PlaneMesh:
			if aspect > 1.0:
				mesh_node.mesh.size = Vector2(max_size_meters, max_size_meters / aspect)
			else:
				mesh_node.mesh.size = Vector2(max_size_meters * aspect, max_size_meters)
		elif mesh_node.mesh is BoxMesh:
			if aspect > 1.0:
				mesh_node.mesh.size = Vector3(max_size_meters, 0.005, max_size_meters / aspect)
			else:
				mesh_node.mesh.size = Vector3(max_size_meters * aspect, 0.005, max_size_meters)

		# 3. Apply texture and make double-sided
		var new_mat: StandardMaterial3D = StandardMaterial3D.new()
		new_mat.albedo_texture = note_texture
		new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

		# Anisotropic filtering keeps environmental notes sharp when viewed at steep angles
		new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

		mesh_node.set_surface_override_material(0, new_mat)


# Catches the call from your InteractionScanner -> InteractComponent
func interact_with(character: CharacterBody3D) -> void:
	print("NoteItem: Player triggered interact_with().")

	# Dynamically locate the NoteReader on the player
	var reader: NoteReader = character.find_child("NoteReader", true, false) as NoteReader

	if is_instance_valid(reader):
		print("NoteItem: NoteReader found. Sending data to UI and reading note.")
		reader.open_note(self, note_text, character)

		var col: CollisionShape3D = get_node_or_null("CollisionShape3D")
		if is_instance_valid(col):
			col.disabled = true
	else:
		print("NoteItem ERROR: Could not find NoteReader on the character! Check Player tree.")
