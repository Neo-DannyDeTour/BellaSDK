@tool
## Trigger volume requesting camera trauma through [ScreenEffectsCore].
class_name ScreenshakeEffect
extends Area3D

@export_group("Trigger Volume")
## Geometry options for the 3D trigger visualizer and collision hull.
@export var shape_type: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		shape_type = value
		if is_inside_tree():
			_update_visuals()

## Dimensions of the trigger area visualizer and collision hull.
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
## Determines if the trigger visualizer mesh should be visible in-game.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree():
			_update_visuals()

## Base tint and opacity applied to the volumetric inner fill.
@export var trigger_color: Color = Color(1.0, 0.5, 0.0, 0.25):
	set(value):
		trigger_color = value
		if is_inside_tree():
			_update_visuals()

## Edge color for the outline wireframe cage and orientation arrow.
@export var outline_color: Color = Color(1.0, 0.7, 0.2, 0.9):
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

## Text displayed above the trigger in the editor viewport.
@export var trigger_text: String = "SCREENSHAKE":
	set(value):
		trigger_text = value
		if is_inside_tree():
			_update_visuals()

@export_group("Shake Settings")
## Dictates whether the screen shake triggers once or repetitively.
@export var trigger_once: bool = true

## Peak trauma intensity requested from [ScreenEffectsCore].
@export_range(0.0, 16.0) var shake_intensity: float = 4.0

## Duration in seconds of sustained screen shake trauma.
@export var shake_duration: float = 2.5

## Tracks if the trigger has already activated to enforce single-fire.
var _triggered: bool = false

## Cached collision shape child defining the trigger bounds.
var _collision_shape: CollisionShape3D = null


## Configures player-only physics mask and connects body entry signal.
func _ready() -> void:
	print("ScreenshakeEffect: Initializing trigger volume: ", name)
	var col_node: Node = get_node_or_null("CollisionShape3D")
	_collision_shape = col_node if col_node is CollisionShape3D else null
	_update_visuals()

	if Engine.is_editor_hint():
		return

	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_PLAYER

	if not show_in_game:
		var editor_mesh: EditorTriggerVisualizer = _get_visualizer()
		if is_instance_valid(editor_mesh):
			editor_mesh.queue_free()

	Utilities.safe_connect(body_entered, _on_body_entered)


## Updates editor wireframe visualizer and collision box dimensions.
func _update_visuals() -> void:
	if not is_inside_tree():
		return

	if not is_instance_valid(_collision_shape):
		var col_node: Node = get_node_or_null("CollisionShape3D")
		_collision_shape = col_node if col_node is CollisionShape3D else null

	if is_instance_valid(_collision_shape):
		if shape_type == EditorTriggerVisualizer.ShapeType.BOX:
			if not _collision_shape.shape is BoxShape3D:
				_collision_shape.shape = BoxShape3D.new()
			else:
				_collision_shape.shape = _collision_shape.shape.duplicate()
			_collision_shape.shape.resource_local_to_scene = true
			var box_shape: BoxShape3D = (
				_collision_shape.shape if _collision_shape.shape is BoxShape3D else null
			)
			if is_instance_valid(box_shape):
				box_shape.size = trigger_size
		elif shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
			if not _collision_shape.shape is SphereShape3D:
				_collision_shape.shape = SphereShape3D.new()
			else:
				_collision_shape.shape = _collision_shape.shape.duplicate()
			_collision_shape.shape.resource_local_to_scene = true
			var sphere_shape: SphereShape3D = (
				_collision_shape.shape if _collision_shape.shape is SphereShape3D else null
			)
			if is_instance_valid(sphere_shape):
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


## Locates [EditorTriggerVisualizer] child node for editor previews using [NodeQuery].
func _get_visualizer() -> EditorTriggerVisualizer:
	var raw_vis: Node = get_node_or_null("EditorTriggerVisualizer")
	var visual: EditorTriggerVisualizer = raw_vis if raw_vis is EditorTriggerVisualizer else null
	if not is_instance_valid(visual):
		visual = (
			NodeQuery.find_first_child_of_type(self, EditorTriggerVisualizer)
			as EditorTriggerVisualizer
		)
	return visual


## Requests trauma via [signal Events.screenshake_requested] on player entry.
func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return
	if trigger_once and _triggered:
		return

	_triggered = true
	print("ScreenshakeEffect: Activated by: ", body.name, ". Adding trauma.")
	var normalized_trauma: float = clampf(shake_intensity / 16.0, 0.0, 1.0)
	Events.screenshake_requested.emit(normalized_trauma, shake_duration)
