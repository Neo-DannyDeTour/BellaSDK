@tool
## Physics trigger volume initiating a cinematic chapter title card upon player entry.
## Hooks into [Events] singleton and configures an [EditorTriggerVisualizer] debug gizmo.
class_name EnvChapterTrigger
extends Area3D

@export_category("Trigger Volume")
## Selects whether the trigger visualizer and collision represent a box or a sphere.
@export var shape_type: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		shape_type = value
		if is_inside_tree():
			_update_bounds()

## Defines the extents of the trigger volume and visual mesh.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_inside_tree():
			_update_bounds()

## Local offset applied to both the collision shape and the visualizer node.
@export var trigger_offset: Vector3 = Vector3.ZERO:
	set(value):
		trigger_offset = value
		if is_inside_tree():
			_update_bounds()

@export_category("Trigger Debug Visualizer")
## Controls whether the visualizer mesh and label remain visible during gameplay.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree():
			_update_bounds()

## Sets the debug albedo color and opacity for the visualizer inner mesh fill.
@export var trigger_color: Color = Color(0.9, 0.5, 0.1, 0.25):
	set(value):
		trigger_color = value
		if is_inside_tree():
			_update_bounds()

## Edge color applied to the wireframe bounding cage and orientation arrow.
@export var outline_color: Color = Color(1.0, 0.8, 0.3, 0.9):
	set(value):
		outline_color = value
		if is_inside_tree():
			_update_bounds()

## Allows the visualizer to remain visible through walls and level geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_inside_tree():
			_update_bounds()

## Displays an arrow pointing along -Z indicating player entry heading.
@export var show_orientation: bool = true:
	set(value):
		show_orientation = value
		if is_inside_tree():
			_update_bounds()

## Appends metric dimensions to the 3D billboard text label.
@export var show_metric_dimensions: bool = true:
	set(value):
		show_metric_dimensions = value
		if is_inside_tree():
			_update_bounds()

## The floating debug text displayed on the visualizer billboard in the editor.
@export var trigger_text: String = "CHAPTER TRIGGER":
	set(value):
		trigger_text = value
		if is_inside_tree():
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


## Initializes bounds, updates visualizer, and connects player entry signal.
func _ready() -> void:
	print("EnvChapterTrigger: Initializing trigger bounds and connections.")
	_update_bounds()
	if Engine.is_editor_hint():
		return

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Synchronizes collision dimensions and visualizer node properties with inspector values.
func _update_bounds() -> void:
	_update_collision_shape()
	_update_visualizer_node()


## Updates or instantiates the corresponding collision shape based on [member shape_type].
func _update_collision_shape() -> void:
	if not is_inside_tree():
		return

	var col: CollisionShape3D = _get_collision_shape()
	if not is_instance_valid(col):
		return

	if shape_type == EditorTriggerVisualizer.ShapeType.BOX:
		if not col.shape is BoxShape3D:
			col.shape = BoxShape3D.new()
		else:
			col.shape = col.shape.duplicate()
		var box: BoxShape3D = col.shape as BoxShape3D
		box.size = trigger_size
	elif shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
		if not col.shape is SphereShape3D:
			col.shape = SphereShape3D.new()
		else:
			col.shape = col.shape.duplicate()
		var sphere: SphereShape3D = col.shape as SphereShape3D
		sphere.radius = trigger_size.x * 0.5

	col.position = trigger_offset


## Propagates configuration values to the child [EditorTriggerVisualizer] node.
func _update_visualizer_node() -> void:
	if not is_inside_tree():
		return

	var visualizer: EditorTriggerVisualizer = _get_visualizer_node()
	if not is_instance_valid(visualizer):
		return

	visualizer.shape_type = shape_type
	visualizer.show_in_game = show_in_game
	visualizer.trigger_size = trigger_size
	visualizer.trigger_color = trigger_color
	visualizer.outline_color = outline_color
	visualizer.x_ray_mode = x_ray_mode
	visualizer.show_orientation = show_orientation
	visualizer.show_metric_dimensions = show_metric_dimensions
	visualizer.trigger_text = trigger_text
	visualizer.position = trigger_offset


## Safely retrieves the child [CollisionShape3D] instance.
func _get_collision_shape() -> CollisionShape3D:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(col):
		for child: Node in get_children():
			if child is CollisionShape3D:
				col = child
				break
	return col


## Safely retrieves the child [EditorTriggerVisualizer] node.
func _get_visualizer_node() -> EditorTriggerVisualizer:
	var visualizer: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if not is_instance_valid(visualizer):
		for child: Node in get_children():
			if child is EditorTriggerVisualizer:
				return child as EditorTriggerVisualizer
	return visualizer


## Validates player presence and fires the global chapter event signal.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint() or _has_triggered:
		return

	if body.is_in_group(&"player"):
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
