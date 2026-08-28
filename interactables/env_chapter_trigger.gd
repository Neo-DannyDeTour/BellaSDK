@tool
## A physics trigger volume that initiates a cinematic chapter title card when the player enters.
##
## Hooks into the global [Events] singleton to pass styling, timing, and text data to the UI.
## Forwards visual properties to an [EditorTriggerVisualizer] child node for level design.
class_name EnvChapterTrigger
extends Area3D

@export_category("Trigger Visuals")
## Selects whether the trigger visualizer and collision represent a box or a sphere.
@export var shape_type: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		shape_type = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_bounds()

## Controls whether the visualizer mesh and label remain visible during gameplay.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_bounds()

## Defines the extents of the trigger volume and visual mesh.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_bounds()

## Sets the debug albedo color and opacity for the visualizer mesh.
@export var trigger_color: Color = Color(0.9, 0.5, 0.1, 0.4):
	set(value):
		trigger_color = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_bounds()

## The floating debug text displayed on the visualizer billboard in the editor.
@export var trigger_text: String = "TRIGGER":
	set(value):
		trigger_text = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_bounds()

@export_category("Chapter Settings")
## The exact string to display on the screen when the title card animates in.
@export var chapter_name: String = "Chapter 1"
## The base color of the chapter text.
@export var text_color: Color = Color.WHITE
## The preset animation style passed to the UI handler.
@export var animation_style: Events.ChapterAnimStyle = Events.ChapterAnimStyle.SIMPLE
## How long in seconds the chapter title remains visible on screen.
@export var display_duration: float = 5.0

@export_category("Randomization")
## If true, overrides the inspector settings with random effects on entry.
@export var play_random_effects: bool = false

## Ensures the chapter event only fires once per playthrough.
var _has_triggered: bool = false


## Removes debug visualizers at runtime and registers the collision signal.
func _ready() -> void:
	if Engine.is_editor_hint():
		_update_bounds()
		return

	var visualizer: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if is_instance_valid(visualizer) and not show_in_game:
		visualizer.queue_free()
		print("EnvChapterTrigger: Editor visualizer freed for game performance.")

	body_entered.connect(_on_body_entered)


## Synchronizes collision dimensions and visualizer node properties with inspector values.
func _update_bounds() -> void:
	_update_collision_shape()
	_update_visualizer_node()


## Updates or instantiates the corresponding collision shape based on [member shape_type].
func _update_collision_shape() -> void:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(col):
		return

	if shape_type == EditorTriggerVisualizer.ShapeType.BOX:
		if not col.shape is BoxShape3D:
			col.shape = BoxShape3D.new()
			col.shape.resource_local_to_scene = true
		(col.shape as BoxShape3D).size = trigger_size
	elif shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
		if not col.shape is SphereShape3D:
			col.shape = SphereShape3D.new()
			col.shape.resource_local_to_scene = true
		(col.shape as SphereShape3D).radius = trigger_size.x / 2.0


## Propagates configuration values to the child [EditorTriggerVisualizer] node.
func _update_visualizer_node() -> void:
	var visualizer: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if not is_instance_valid(visualizer):
		return

	visualizer.shape_type = shape_type
	visualizer.show_in_game = show_in_game
	visualizer.trigger_size = trigger_size
	visualizer.trigger_color = trigger_color
	visualizer.trigger_text = trigger_text


## Validates player presence and fires the global chapter event signal.
## [param body]: The 3D physics body that triggered the area.
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


## Generates randomized styling parameters for demonstration scenarios.
func _apply_random_effects_if_enabled() -> void:
	if not play_random_effects:
		return

	print("EnvChapterTrigger: _apply_random_effects_if_enabled() called.")

	var style_values: Array = Events.ChapterAnimStyle.values()
	animation_style = style_values.pick_random() as Events.ChapterAnimStyle
	text_color = Color(randf(), randf(), randf(), 1.0)
	display_duration = randf_range(3.0, 7.0)

	print(
		"EnvChapterTrigger: Random effects generated -> Style: ",
		animation_style,
		", Color: ",
		text_color,
		", Duration: ",
		display_duration
	)
