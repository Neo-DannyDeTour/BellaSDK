@tool
## Area3D volume modifying health with togglable debug trigger visualizer bounds.
class_name HealthModifier
extends Area3D

@export_group("Health Modifier")
## The amount of health to modify per tick. Negative deals damage, positive heals.
@export var modify_amount: int = -25

## Time interval in seconds between consecutive health modifications.
@export var tick_interval: float = 1.0

@export_group("Trigger Volume")
## Geometry options for the 3D trigger visualizer and collision hull.
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

## Local offset applied to both the collision shape and the visualizer node.
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
@export var trigger_color: Color = Color(0.9, 0.2, 0.2, 0.25):
	set(value):
		trigger_color = value
		if is_inside_tree():
			_update_visuals()

## Edge color for the outline wireframe cage and orientation arrow.
@export var outline_color: Color = Color(1.0, 0.3, 0.3, 0.9):
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

## Displays an arrow pointing along -Z indicating forward orientation.
@export var show_orientation: bool = false:
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
@export var trigger_text: String = "HEALTH MODIFIER":
	set(value):
		trigger_text = value
		if is_inside_tree():
			_update_visuals()

## Internal timer used for scheduling periodic health ticks.
var _tick_timer: Timer

## Maps overlapping physics bodies to their resolved [HealthComponent].
var _health_cache: Dictionary = {}

## Cached collision shape child defining the trigger bounds.
var _collision_shape: CollisionShape3D = null


## Initializes visualizer, collision hull, and runtime damage ticking.
func _ready() -> void:
	print("HealthModifier: Initializing health modifier volume at ", name)
	_collision_shape = (get_node_or_null("CollisionShape3D") as CollisionShape3D)
	_update_visuals()

	if Engine.is_editor_hint():
		return

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	_tick_timer = Timer.new()
	_tick_timer.name = "TickTimer"
	_tick_timer.wait_time = tick_interval
	_tick_timer.autostart = true
	add_child(_tick_timer)
	_tick_timer.timeout.connect(_on_tick_timer_timeout)


## Rebuilds collision shapes and visualizer meshes matching volume settings.
func _update_visuals() -> void:
	if not is_inside_tree():
		return

	if not is_instance_valid(_collision_shape):
		_collision_shape = (get_node_or_null("CollisionShape3D") as CollisionShape3D)

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


## Resolves and caches [HealthComponent] when a body enters the volume.
func _on_body_entered(body: Node3D) -> void:
	print("HealthModifier: Body entered volume -> ", body.name)
	var comp: HealthComponent = _resolve_health_node(body)
	if is_instance_valid(comp):
		_health_cache[body] = comp


## Clears the body from the health component cache upon exit.
func _on_body_exited(body: Node3D) -> void:
	print("HealthModifier: Body exited volume -> ", body.name)
	_health_cache.erase(body)


## Resolves [HealthComponent] on target via direct property or typed search.
func _resolve_health_node(body: Node3D) -> HealthComponent:
	print("HealthModifier: Resolving health component for -> ", body.name)
	if not is_instance_valid(body):
		return null

	if "health_component" in body:
		var comp: Variant = body.get("health_component")
		if comp is HealthComponent:
			return comp as HealthComponent

	var child_comp: Node = NodeQuery.find_first_child_of_type(body, HealthComponent)
	if child_comp is HealthComponent:
		return child_comp as HealthComponent

	var found: Node = body.find_child("*HealthComponent*", true, false)
	if found is HealthComponent:
		return found as HealthComponent

	return null


## Retrieves overlapping bodies within the area. Can be overridden for tests.
func _get_target_bodies() -> Array[Node3D]:
	print("HealthModifier: Fetching overlapping bodies.")
	return get_overlapping_bodies()


## Periodically modifies health on cached and newly resolved overlapping bodies.
func _on_tick_timer_timeout() -> void:
	print("HealthModifier: Processing tick damage/heal.")
	var bodies: Array[Node3D] = _get_target_bodies()

	for body: Node3D in bodies:
		if not is_instance_valid(body):
			_health_cache.erase(body)
			continue

		var comp: HealthComponent = (
			_health_cache.get(body) if _health_cache.get(body) is HealthComponent else null
		)
		if not is_instance_valid(comp):
			comp = _resolve_health_node(body)
			if is_instance_valid(comp):
				_health_cache[body] = comp
			else:
				continue

		if modify_amount < 0:
			comp.take_damage(absi(modify_amount))
		elif modify_amount > 0:
			comp.heal(modify_amount)
