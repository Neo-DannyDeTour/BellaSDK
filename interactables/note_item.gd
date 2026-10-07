@tool
## World note prop displaying 2D textures and transmitting text to [NoteReader].
class_name NoteItem
extends StaticBody3D

## Stores text content emitted when the player reads the note.
@export_multiline var note_text: String = ""

## Texture resource rendered on the note mesh in world space.
@export var note_texture: Texture2D:
	set(value):
		note_texture = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_appearance()

## Maximum dimensional size in meters for the note's longest side.
@export var max_size_meters: float = 0.3:
	set(value):
		max_size_meters = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_appearance()

## Cached mesh instance child displaying the note material.
var _mesh_node: MeshInstance3D = null

## Cached collision shape child defining the interactive boundary.
var _collision_shape: CollisionShape3D = null


## Configures interaction collision layers and material overrides on ready.
func _ready() -> void:
	collision_layer = CollisionLayers.MASK_INTERACTIVE
	collision_mask = CollisionLayers.MASK_NONE
	_mesh_node = get_node_or_null("MeshInstance3D") as MeshInstance3D
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D

	if not Engine.is_editor_hint():
		print("NoteItem: Spawned note prop in world: ", name)
	_update_appearance()


## Returns the HUD prompt text queried by [InteractionManager].
func get_interaction_prompt() -> String:
	return "Read Note"


## Toggles visual focus highlight outlines when targeted by player reticle.
func set_highlight(enabled: bool) -> void:
	print("NoteItem: Setting highlight outline to: ", enabled)


## Primary interaction entrypoint called by [InteractionManager].
func interact(interactor: Node3D) -> void:
	print("NoteItem: interact() invoked by: ", interactor.name)
	var reader: NoteReader = _resolve_note_reader(interactor)
	if is_instance_valid(reader):
		print("NoteItem: Dispatching note to NoteReader.")
		var player_char: CharacterBody3D = interactor if interactor is CharacterBody3D else null
		if player_char == null:
			player_char = (
				NodeQuery.find_ancestor_of_type(interactor, CharacterBody3D) as CharacterBody3D
			)
		reader.open_note(self, note_text, player_char)
		if is_instance_valid(_collision_shape):
			_collision_shape.disabled = true
	else:
		push_warning("NoteItem: Unable to resolve NoteReader on interactor!")


## Backward-compatible legacy wrapper delegating directly to [method interact].
func interact_with(character: CharacterBody3D) -> void:
	print("NoteItem: interact_with() called. Delegating to interact().")
	interact(character)


## Resizes the quad geometry to match the assigned texture aspect ratio.
func _update_appearance() -> void:
	if not is_inside_tree():
		return

	if not is_instance_valid(_mesh_node):
		_mesh_node = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not is_instance_valid(_mesh_node) or _mesh_node.mesh == null:
		return

	if note_texture != null:
		var tex_w: float = float(note_texture.get_width())
		var tex_h: float = float(note_texture.get_height())
		var aspect: float = tex_w / maxf(tex_h, 1.0)

		if Engine.is_editor_hint() and not _mesh_node.mesh.resource_local_to_scene:
			_mesh_node.mesh = _mesh_node.mesh.duplicate()

		if _mesh_node.mesh is PlaneMesh:
			var plane: PlaneMesh = _mesh_node.mesh if _mesh_node.mesh is PlaneMesh else null
			if aspect > 1.0:
				plane.size = Vector2(max_size_meters, max_size_meters / aspect)
			else:
				plane.size = Vector2(max_size_meters * aspect, max_size_meters)
		elif _mesh_node.mesh is BoxMesh:
			var box: BoxMesh = _mesh_node.mesh if _mesh_node.mesh is BoxMesh else null
			if aspect > 1.0:
				box.size = Vector3(max_size_meters, 0.005, max_size_meters / aspect)
			else:
				box.size = Vector3(max_size_meters * aspect, 0.005, max_size_meters)

		var mat: StandardMaterial3D = (
			_mesh_node.get_surface_override_material(0) as StandardMaterial3D
		)
		if mat == null:
			mat = StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			_mesh_node.set_surface_override_material(0, mat)
		mat.albedo_texture = note_texture


## Resolves active [NoteReader] component using [NodeQuery].
func _resolve_note_reader(interactor: Node) -> NoteReader:
	if not is_instance_valid(interactor):
		return null
	var reader: Node = NodeQuery.find_first_child_of_type(interactor, NoteReader)
	if is_instance_valid(reader):
		return reader as NoteReader
	reader = NodeQuery.find_ancestor_of_type(interactor, NoteReader)
	if is_instance_valid(reader):
		return reader as NoteReader
	var scene_reader: Node = NodeQuery.get_single_node_in_group(get_tree(), &"note_reader")
	if scene_reader is NoteReader:
		return scene_reader as NoteReader
	return null
