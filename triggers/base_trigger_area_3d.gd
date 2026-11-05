@tool
## Base 3D area trigger encapsulating editor visualization, collision sizing, and player filtering.
class_name BaseTriggerArea3D
extends Area3D

## Emitted when a valid player node enters the trigger volume.
signal player_entered(player: Node3D)

## Emitted when a valid player node exits the trigger volume.
signal player_exited(player: Node3D)

@export_group("Trigger Volume")
## Geometric shape options for the 3D trigger visualizer and collision hull.
@export var shape_type: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		shape_type = value
		if is_inside_tree():
			_update_bounds()

## Extents of the trigger box or diameter bounds of the sphere.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_inside_tree():
			_update_bounds()

## Local offset applied to both the collision shape and visualizer node.
@export var trigger_offset: Vector3 = Vector3.ZERO:
	set(value):
		trigger_offset = value
		if is_inside_tree():
			_update_bounds()

@export_group("Trigger Settings")
## Determines if the trigger action should only fire on the first player entry.
@export var trigger_once: bool = true

## Controls whether player entry immediately consumes this trigger as spent.
@export var auto_consume_on_entry: bool = true

@export_group("Trigger Debug Visualizer")
## Determines if the trigger visualizer remains visible during active gameplay.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree():
			_update_bounds()

## Base tint and opacity applied to the volumetric inner fill.
@export var trigger_color: Color = Color(0.9, 0.5, 0.1, 0.25):
	set(value):
		trigger_color = value
		if is_inside_tree():
			_update_bounds()

## Edge color for the outline wireframe cage and orientation arrow.
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

## The text displayed on the trigger's label inside the editor.
@export var trigger_text: String = "TRIGGER":
	set(value):
		trigger_text = value
		if is_inside_tree():
			_update_bounds()

## Tracks whether this trigger has already executed its action.
var _has_triggered: bool = false

## Cached collision shape child defining the trigger bounds.
var _collision_shape: CollisionShape3D = null


## Initializes collision layers, connects signals, and prepares editor visuals.
func _ready() -> void:
	_collision_shape = _get_collision_shape()
	_sync_from_collision_shape()
	_ensure_visualizer()
	_update_bounds()

	if Engine.is_editor_hint():
		return

	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_PLAYER

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


## Synchronizes collision dimensions and visualizer node properties with inspector values.
func _update_bounds() -> void:
	if not is_inside_tree():
		return

	var col: CollisionShape3D = _get_collision_shape()
	var visual: EditorTriggerVisualizer = _get_visualizer()
	if is_instance_valid(col):
		if shape_type == EditorTriggerVisualizer.ShapeType.BOX:
			if not (col.shape is BoxShape3D):
				col.shape = BoxShape3D.new()
			else:
				col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true
			var box_shape: BoxShape3D = col.shape as BoxShape3D
			box_shape.size = trigger_size
		elif shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
			if not (col.shape is SphereShape3D):
				col.shape = SphereShape3D.new()
			else:
				col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true
			var sphere_shape: SphereShape3D = col.shape as SphereShape3D
			sphere_shape.radius = trigger_size.x * 0.5
		elif shape_type == EditorTriggerVisualizer.ShapeType.CYLINDER:
			if not (col.shape is CylinderShape3D):
				col.shape = CylinderShape3D.new()
			else:
				col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true
			var cyl_shape: CylinderShape3D = col.shape as CylinderShape3D
			cyl_shape.radius = trigger_size.x * 0.5
			cyl_shape.height = trigger_size.y

		col.position = trigger_offset

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


## Adopts geometry settings from existing child collision shape if trigger is uncustomized.
func _sync_from_collision_shape() -> void:
	var col: CollisionShape3D = _get_collision_shape()
	if not is_instance_valid(col) or col.shape == null:
		return

	if (
		trigger_size == Vector3(2.0, 2.0, 2.0)
		and trigger_offset == Vector3.ZERO
		and shape_type == EditorTriggerVisualizer.ShapeType.BOX
	):
		if col.shape is BoxShape3D:
			var box_shape: BoxShape3D = col.shape as BoxShape3D
			if box_shape.size != Vector3(2.0, 2.0, 2.0):
				trigger_size = box_shape.size
			if col.position != Vector3.ZERO:
				trigger_offset = col.position
		elif col.shape is SphereShape3D:
			shape_type = EditorTriggerVisualizer.ShapeType.SPHERE
			var sphere_shape: SphereShape3D = col.shape as SphereShape3D
			var rad: float = sphere_shape.radius
			trigger_size = Vector3(rad * 2.0, rad * 2.0, rad * 2.0)
			if col.position != Vector3.ZERO:
				trigger_offset = col.position
		elif col.shape is CylinderShape3D:
			shape_type = EditorTriggerVisualizer.ShapeType.CYLINDER
			var cyl_shape: CylinderShape3D = col.shape as CylinderShape3D
			trigger_size = Vector3(cyl_shape.radius * 2.0, cyl_shape.height, cyl_shape.radius * 2.0)
			if col.position != Vector3.ZERO:
				trigger_offset = col.position


## Ensures an [EditorTriggerVisualizer] child node exists, instantiating one if missing.
func _ensure_visualizer() -> EditorTriggerVisualizer:
	var visual: EditorTriggerVisualizer = _get_visualizer()
	if not is_instance_valid(visual):
		visual = EditorTriggerVisualizer.new()
		visual.name = "EditorTriggerVisualizer"
		add_child(visual)
	return visual


## Locates child [CollisionShape3D] safely across scene tree variants.
func _get_collision_shape() -> CollisionShape3D:
	if is_instance_valid(_collision_shape):
		return _collision_shape
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(col):
		for child: Node in get_children():
			if child is CollisionShape3D:
				return child as CollisionShape3D
	return col


## Locates child [EditorTriggerVisualizer] node for editor previews.
func _get_visualizer() -> EditorTriggerVisualizer:
	var visual: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if not is_instance_valid(visual):
		for child: Node in get_children():
			if child is EditorTriggerVisualizer:
				return child as EditorTriggerVisualizer
	return visual


## Validates whether [param body] represents an active player character.
func _is_player(body: Node3D) -> bool:
	if not is_instance_valid(body):
		return false
	return body.is_in_group(&"player") or body.name.begins_with("Player")


## Handles engine body entry signal, validates player identity, and dispatches callbacks.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint() or not _is_player(body):
		return

	if trigger_once and _has_triggered:
		return

	if auto_consume_on_entry:
		_has_triggered = true
	print(name, ": Player entered volume -> ", body.name)
	player_entered.emit(body)
	_on_player_entered(body)


## Handles engine body exit signal, validates player identity, and dispatches callbacks.
func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint() or not _is_player(body):
		return

	print(name, ": Player exited volume -> ", body.name)
	player_exited.emit(body)
	_on_player_exited(body)


## Virtual callback executed when a valid player enters the volume. Override in subclass.
func _on_player_entered(_player: Node3D) -> void:
	pass


## Virtual callback executed when a valid player exits the volume. Override in subclass.
func _on_player_exited(_player: Node3D) -> void:
	pass
