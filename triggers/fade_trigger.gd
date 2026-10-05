@tool
## Trigger volume initiating camera transition sequences via [ScreenEffectsCore].
class_name FadeTrigger
extends Area3D

@export_group("Trigger Settings")
## Determines if the effect should only happen the first time a player enters.
@export var trigger_once: bool = true

## Duration in seconds for the screen to fade to the target color.
@export var fade_in_duration: float = 1.0

## Duration in seconds the screen remains fully faded before returning.
@export var hold_duration: float = 0.5

## Duration in seconds for the screen to return to normal.
@export var fade_out_duration: float = 1.0

@export_group("Visual Effects")
## The target color the screen will fade towards.
@export var fade_color: Color = Color.BLACK

## Enables a blur effect during the fade transition.
@export var use_blur: bool = true

## The maximum intensity of the blur effect.
@export var max_blur: float = 2.5

## Enables a blinking effect during the transition.
@export var use_blink: bool = false

## The number of times the screen blinks during the fade sequence.
@export_range(1, 10) var blink_count: int = 1

@export_group("Trigger Volume")
## Geometric shape options for the 3D trigger visualizer and collision hull.
@export var shape_type: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		shape_type = value
		if is_inside_tree():
			_update_visuals()

## Extents of the trigger box or diameter bounds of the sphere.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_inside_tree():
			_update_visuals()

## Local offset applied to both the collision shape and visualizer node.
@export var trigger_offset: Vector3 = Vector3.ZERO:
	set(value):
		trigger_offset = value
		if is_inside_tree():
			_update_visuals()

@export_group("Trigger Debug Visualizer")
## Determines if the trigger visualizer remains visible during active gameplay.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree():
			_update_visuals()

## Base tint and opacity applied to the volumetric inner fill.
@export var trigger_color: Color = Color(0.9, 0.5, 0.1, 0.25):
	set(value):
		trigger_color = value
		if is_inside_tree():
			_update_visuals()

## Edge color for the outline wireframe cage and orientation arrow.
@export var outline_color: Color = Color(1.0, 0.8, 0.3, 0.9):
	set(value):
		outline_color = value
		if is_inside_tree():
			_update_visuals()

## Allows the visualizer to remain visible through walls and level geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_inside_tree():
			_update_visuals()

## Displays an arrow pointing along -Z indicating player entry heading.
@export var show_orientation: bool = true:
	set(value):
		show_orientation = value
		if is_inside_tree():
			_update_visuals()

## Appends metric dimensions to the 3D billboard text label.
@export var show_metric_dimensions: bool = true:
	set(value):
		show_metric_dimensions = value
		if is_inside_tree():
			_update_visuals()

## The text displayed on the trigger's label inside the editor.
@export var trigger_text: String = "FADE TRIGGER":
	set(value):
		trigger_text = value
		if is_inside_tree():
			_update_visuals()

## Tracks whether this trigger has already been activated by a player.
var _triggered: bool = false

## Cached collision shape child defining the trigger bounds.
var _collision_shape: CollisionShape3D = null


## Initializes bounds and connects body entry callback.
func _ready() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_update_visuals()

	if Engine.is_editor_hint():
		return

	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_PLAYER

	if not show_in_game:
		var editor_mesh: EditorTriggerVisualizer = _get_visualizer()
		if is_instance_valid(editor_mesh):
			editor_mesh.queue_free()

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Rebuilds collision shapes and visualizer meshes matching volume settings.
func _update_visuals() -> void:
	if not is_inside_tree():
		return

	if not is_instance_valid(_collision_shape):
		_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D

	if is_instance_valid(_collision_shape):
		if shape_type == EditorTriggerVisualizer.ShapeType.BOX:
			if not _collision_shape.shape is BoxShape3D:
				_collision_shape.shape = BoxShape3D.new()
			else:
				_collision_shape.shape = _collision_shape.shape.duplicate()
			_collision_shape.shape.resource_local_to_scene = true
			var box_shape: BoxShape3D = _collision_shape.shape as BoxShape3D
			box_shape.size = trigger_size
		elif shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
			if not _collision_shape.shape is SphereShape3D:
				_collision_shape.shape = SphereShape3D.new()
			else:
				_collision_shape.shape = _collision_shape.shape.duplicate()
			_collision_shape.shape.resource_local_to_scene = true
			var sphere_shape: SphereShape3D = _collision_shape.shape as SphereShape3D
			sphere_shape.radius = trigger_size.x * 0.5

		_collision_shape.position = trigger_offset

	var visual: EditorTriggerVisualizer = _get_visualizer()
	if is_instance_valid(visual):
		visual.shape_type = shape_type
		visual.trigger_size = trigger_size
		visual.trigger_color = trigger_color
		visual.outline_color = outline_color
		visual.x_ray_mode = x_ray_mode
		visual.show_orientation = show_orientation
		visual.show_metric_dimensions = show_metric_dimensions
		visual.trigger_text = trigger_text
		visual.show_in_game = show_in_game
		visual.position = trigger_offset


## Locates [EditorTriggerVisualizer] child node for editor previews.
func _get_visualizer() -> EditorTriggerVisualizer:
	var visual: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if not is_instance_valid(visual):
		for child: Node in get_children():
			if child is EditorTriggerVisualizer:
				return child as EditorTriggerVisualizer
	return visual


## Evaluates player entry and begins the post-process screen transition.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if not body.is_in_group(&"player"):
		return

	if trigger_once and _triggered:
		return

	_triggered = true
	print("FadeTrigger: Activated by: ", body.name, ". Starting screen fade sequence.")
	_dispatch_fade_sequence()


## Dispatches screen transition parameters to centralized [ScreenEffectsCore].
func _dispatch_fade_sequence() -> void:
	print("FadeTrigger: Dispatching transition payload to ScreenEffectsCore.")
	if Events.has_signal(&"screen_fade_requested"):
		Events.screen_fade_requested.emit(
			fade_color,
			fade_in_duration,
			hold_duration,
			fade_out_duration,
			use_blur,
			max_blur,
			use_blink,
			blink_count
		)
