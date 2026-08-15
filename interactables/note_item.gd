@tool
## An environmental world item that displays a custom 2D texture and passes text to the UI.
##
## Automatically calculates texture aspect ratios to size its 3D geometry without stretching.
## Binds to the player's internal `NoteReader` node when interacted with.
class_name NoteItem
extends StaticBody3D

## Stores the text content displayed when the player reads the note.
@export_multiline var note_text: String = ""

## Sets the image texture and instantly updates the mesh in the editor.
@export var note_texture: Texture2D:
	set(value):
		note_texture = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_appearance()

## Max size in meters for the longest side of the note (0.3 = 30cm).
@export var max_size_meters: float = 0.3:
	set(value):
		max_size_meters = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_appearance()


## Initializes structural dimensions and generates materials dynamically upon entering the tree.
func _ready() -> void:
	if not Engine.is_editor_hint():
		print("NoteItem: Spawned in world.")

	_update_appearance()


## Computes the assigned texture's aspect ratio to safely resize and texture the mesh block.
func _update_appearance() -> void:
	if not is_inside_tree():
		return

	var mesh_node: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
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
			var plane: PlaneMesh = mesh_node.mesh as PlaneMesh
			if aspect > 1.0:
				plane.size = Vector2(max_size_meters, max_size_meters / aspect)
			else:
				plane.size = Vector2(max_size_meters * aspect, max_size_meters)
		elif mesh_node.mesh is BoxMesh:
			var box: BoxMesh = mesh_node.mesh as BoxMesh
			if aspect > 1.0:
				box.size = Vector3(max_size_meters, 0.005, max_size_meters / aspect)
			else:
				box.size = Vector3(max_size_meters * aspect, 0.005, max_size_meters)

		# 3. Apply texture and make double-sided
		var new_mat: StandardMaterial3D = StandardMaterial3D.new()
		new_mat.albedo_texture = note_texture
		new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

		# Anisotropic filtering keeps environmental notes sharp when viewed at steep angles
		new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

		mesh_node.set_surface_override_material(0, new_mat)


## Locates the `NoteReader` node on the interactor and initiates the reading sequence.
## [param character]: The player character node.
func interact_with(character: CharacterBody3D) -> void:
	print("NoteItem: Player triggered interact_with().")

	# Dynamically locate the NoteReader on the player
	var reader: Node = character.find_child("NoteReader", true, false)

	if is_instance_valid(reader) and reader.has_method("open_note"):
		print("NoteItem: NoteReader found. Sending data to UI and reading note.")
		reader.call("open_note", self, note_text, character)

		var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
		if is_instance_valid(col):
			col.disabled = true
	else:
		print("NoteItem ERROR: Could not find NoteReader on the character! Check Player tree.")
