@tool
class_name EnvChapterTrigger
extends Area3D

@export_category("Level Design")
## Changes the size of the trigger box directly from the inspector.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_bounds()

## Sets the color of the visual box in the editor to make it highly visible.
@export var editor_color: Color = Color(1.0, 0.0, 0.0, 0.4):
	set(value):
		editor_color = value
		_update_bounds()

@export_category("Chapter Settings")
@export var chapter_name: String = "Chapter 1"
@export var text_color: Color = Color.WHITE
@export var animation_style: Events.ChapterAnimStyle = Events.ChapterAnimStyle.SIMPLE
@export var display_duration: float = 5.0

@export_category("Randomization")
## If true, overrides the settings above with random effects when the player enters.
@export var play_random_effects: bool = false

var _has_triggered: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	var editor_mesh: MeshInstance3D = get_node_or_null("EditorVisual")
	if editor_mesh:
		editor_mesh.queue_free()
		print("EnvChapterTrigger: Editor visual mesh freed for performance.")

	body_entered.connect(_on_body_entered)


func _update_bounds() -> void:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if col:
		if not col.shape:
			col.shape = BoxShape3D.new()

		if not col.shape.resource_local_to_scene:
			col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true

		if col.shape is BoxShape3D:
			var box: BoxShape3D = col.shape as BoxShape3D
			box.size = trigger_size

	var mesh: MeshInstance3D = get_node_or_null("EditorVisual")
	if mesh and mesh.mesh is BoxMesh:
		var box_mesh: BoxMesh = mesh.mesh as BoxMesh
		box_mesh.size = trigger_size

		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if not mat:
			mat = StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh.material_override = mat

		mat.albedo_color = editor_color


func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint() or _has_triggered:
		return

	if body.is_in_group("player"):
		_has_triggered = true
		_apply_random_effects_if_enabled()

		print(
			"EnvChapterTrigger: Player entered. Emitting chapter '",
			chapter_name,
			"' with style ID ",
			animation_style
		)

		Events.chapter_triggered.emit(
			chapter_name, animation_style as int, display_duration, text_color
		)


func _apply_random_effects_if_enabled() -> void:
	if not play_random_effects:
		return

	print("EnvChapterTrigger: _apply_random_effects_if_enabled() called.")

	# Grab all available integer values from the enum and pick one at random
	var style_values: Array = Events.ChapterAnimStyle.values()
	animation_style = style_values.pick_random() as Events.ChapterAnimStyle

	# Generate a random, fully opaque color
	text_color = Color(randf(), randf(), randf(), 1.0)

	# Randomize the duration slightly between 3.0 and 7.0 seconds
	display_duration = randf_range(3.0, 7.0)

	print(
		"EnvChapterTrigger: Random effects generated -> Style: ",
		animation_style,
		", Color: ",
		text_color,
		", Duration: ",
		display_duration
	)
