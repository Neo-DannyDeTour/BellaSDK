@tool
## 3D navigation waypoint with inspector-editable trigger visualizer bounds and path links.
class_name Waypoint3D
extends Marker3D

## Emitted when an entity checks in or reaches within arrival threshold.
signal reached(actor: Node3D)

## Alias for the editor trigger visualizer geometry type enum.
const SHAPE_TYPE: Variant = EditorTriggerVisualizer.ShapeType

@export_group("Waypoint Navigation")
## Distance in units to consider an actor within arrival threshold.
@export_range(0.1, 50.0, 0.1) var arrival_radius: float = 1.0:
	set(value):
		arrival_radius = maxf(0.1, value)
		trigger_size = Vector3.ONE * (arrival_radius * 2.0)
		if is_inside_tree():
			_update_visuals()

## Next sequential waypoint in path chain for patrol loops or sequences.
@export var next_waypoint: Waypoint3D:
	set(value):
		next_waypoint = value
		if is_inside_tree():
			_update_visuals()

## Pause duration in seconds actors can query to linger at this waypoint.
@export var wait_time: float = 0.0

## Speed multiplier tag applied when actors move towards this waypoint.
@export var speed_modifier: float = 1.0

## Optional scripted action or animation state tag triggered upon arrival.
@export var action_tag: StringName = &""

## Automatically senses overlapping player bodies to emit [signal reached].
@export var monitor_player: bool = true:
	set(value):
		monitor_player = value
		if is_inside_tree():
			_update_visuals()

@export_group("Trigger Volume")
## Geometry options for the 3D trigger visualizer and detection hull.
@export var shape_type: SHAPE_TYPE = SHAPE_TYPE.SPHERE:
	set(value):
		shape_type = value
		if is_inside_tree():
			_update_visuals()

## Extents of the trigger box or diameter bounds of the sphere.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		arrival_radius = trigger_size.x * 0.5
		if is_inside_tree():
			_update_visuals()

## Local offset applied to detection shape and visualizer node.
@export var trigger_offset: Vector3 = Vector3.ZERO:
	set(value):
		trigger_offset = value
		if is_inside_tree():
			_update_visuals()

@export_group("Trigger Debug Visualizer")
## Determines if visualizer remains visible during active gameplay.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree():
			_update_visuals()

## Base tint and opacity applied to volumetric inner fill.
@export var trigger_color: Color = Color(0.1, 0.7, 0.9, 0.25):
	set(value):
		trigger_color = value
		if is_inside_tree():
			_update_visuals()

## Edge color for outline wireframe cage and orientation arrow.
@export var outline_color: Color = Color(0.2, 0.85, 1.0, 0.9):
	set(value):
		outline_color = value
		if is_inside_tree():
			_update_visuals()

## Allows visualizer to remain visible through walls and geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_inside_tree():
			_update_visuals()

## Displays arrow pointing along -Z indicating entry heading.
@export var show_orientation: bool = true:
	set(value):
		show_orientation = value
		if is_inside_tree():
			_update_visuals()

## Appends metric dimensions to 3D billboard text label.
@export var show_metric_dimensions: bool = true:
	set(value):
		show_metric_dimensions = value
		if is_inside_tree():
			_update_visuals()

## Text displayed on the waypoint visualizer label in editor.
@export var trigger_text: String = "WAYPOINT":
	set(value):
		trigger_text = value
		if is_inside_tree():
			_update_visuals()

## Child mesh instance rendering directional path arrow to next waypoint.
var _chain_mesh: MeshInstance3D = null

## Area3D volume detecting player body entry for autonomous signal dispatch.
var _detector_area: Area3D = null

## Cached collision shape child defining player proximity bounds.
var _collision_shape: CollisionShape3D = null


## Initializes visualizer, collision hull, and transforms.
func _ready() -> void:
	print("Waypoint3D: Initializing waypoint at ", name)
	set_notify_transform(true)
	add_to_group(&"trigger_visualizers")
	_update_visuals()

	if not Engine.is_editor_hint() and has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("trigger_visibility_toggled"):
			events.trigger_visibility_toggled.connect(set_debug_visibility)


## Listens for engine notifications to redraw gizmos on transform shifts.
func _notification(what: int) -> void:
	if Engine.is_editor_hint() and what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_chain_arrow()


## Rebuilds visualizer settings and synchronizes detector bounds.
func _update_visuals() -> void:
	if not is_inside_tree():
		return

	var visual: EditorTriggerVisualizer = _get_visualizer()
	if is_instance_valid(visual):
		visual.shape_type = shape_type
		visual.trigger_size = trigger_size
		visual.trigger_color = trigger_color
		visual.outline_color = outline_color
		visual.x_ray_mode = x_ray_mode
		visual.show_orientation = show_orientation
		visual.show_metric_dimensions = show_metric_dimensions
		var label_str: String = trigger_text
		if is_instance_valid(next_waypoint):
			label_str += " ➔ " + next_waypoint.name
		visual.trigger_text = label_str
		visual.show_in_game = show_in_game
		visual.position = trigger_offset

	_update_chain_arrow()
	_update_detector()


## Draws directional path connection arrow to [member next_waypoint].
func _update_chain_arrow() -> void:
	if not is_instance_valid(_chain_mesh):
		_chain_mesh = get_node_or_null("WaypointChainLine") as MeshInstance3D
		if not is_instance_valid(_chain_mesh):
			_chain_mesh = MeshInstance3D.new()
			_chain_mesh.name = "WaypointChainLine"
			add_child(_chain_mesh)

	var draw_active: bool = (
		(Engine.is_editor_hint() or show_in_game or EditorTriggerVisualizer.debug_force_visible)
		and is_instance_valid(next_waypoint)
	)
	_chain_mesh.visible = draw_active

	if not draw_active or not next_waypoint.is_inside_tree():
		_chain_mesh.mesh = null
		return

	var local_dest: Vector3 = to_local(next_waypoint.global_position)
	var imm_mesh: ImmediateMesh = ImmediateMesh.new()
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_line(imm_mesh, trigger_offset, local_dest)

	var dir: Vector3 = (local_dest - trigger_offset).normalized()
	var dist: float = trigger_offset.distance_to(local_dest)
	if dist > 0.8:
		var side: Vector3 = dir.cross(Vector3.UP).normalized() * 0.3
		var back: Vector3 = local_dest - (dir * 0.5)
		_draw_line(imm_mesh, local_dest, back + side)
		_draw_line(imm_mesh, local_dest, back - side)
	imm_mesh.surface_end()

	_chain_mesh.mesh = imm_mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = outline_color
	mat.no_depth_test = x_ray_mode
	_chain_mesh.set_surface_override_material(0, mat)


## Helper appending a two-vertex segment into an [ImmediateMesh].
func _draw_line(target_mesh: ImmediateMesh, from: Vector3, to: Vector3) -> void:
	target_mesh.surface_add_vertex(from)
	target_mesh.surface_add_vertex(to)


## Locates or instantiates child [EditorTriggerVisualizer].
func _get_visualizer() -> EditorTriggerVisualizer:
	var visual: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if not is_instance_valid(visual):
		for child: Node in get_children():
			if child is EditorTriggerVisualizer:
				return child as EditorTriggerVisualizer
		visual = EditorTriggerVisualizer.new()
		visual.name = "EditorTriggerVisualizer"
		add_child(visual)
	return visual


## Toggles visibility on waypoint chain line and visualizer from console.
func set_debug_visibility(is_active: bool) -> void:
	print("Waypoint3D: Debug visibility toggle -> ", is_active)
	var visual: EditorTriggerVisualizer = _get_visualizer()
	if is_instance_valid(visual):
		visual.set_debug_visibility(is_active)
	if is_instance_valid(_chain_mesh):
		_chain_mesh.visible = (
			(Engine.is_editor_hint() or show_in_game or is_active)
			and is_instance_valid(next_waypoint)
		)


## Creates or updates player detection [Area3D] volume.
func _update_detector() -> void:
	if Engine.is_editor_hint():
		return

	if not monitor_player:
		if is_instance_valid(_detector_area):
			_detector_area.queue_free()
		return

	if not is_instance_valid(_detector_area):
		_detector_area = Area3D.new()
		_detector_area.name = "PlayerDetectionArea"
		_detector_area.collision_layer = 0
		_detector_area.collision_mask = 2
		add_child(_detector_area)
		_detector_area.body_entered.connect(_on_detector_body_entered)

	if not is_instance_valid(_collision_shape):
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		_detector_area.add_child(_collision_shape)

	if shape_type == EditorTriggerVisualizer.ShapeType.BOX:
		if not _collision_shape.shape is BoxShape3D:
			_collision_shape.shape = BoxShape3D.new()
		(_collision_shape.shape as BoxShape3D).size = trigger_size
	else:
		if not _collision_shape.shape is SphereShape3D:
			_collision_shape.shape = SphereShape3D.new()
		(_collision_shape.shape as SphereShape3D).radius = arrival_radius

	_collision_shape.position = trigger_offset


## Handles player entering proximity volume and emits [signal reached].
func _on_detector_body_entered(body: Node3D) -> void:
	print("Waypoint3D: [", name, "] detected player body -> ", body.name)
	reached.emit(body)


## Evaluates whether [param actor_or_pos] is within arrival radius.
func is_reached(actor_or_pos: Variant) -> bool:
	var check_pos: Vector3 = Vector3.ZERO
	if actor_or_pos is Node3D:
		var actor_node: Node3D = actor_or_pos as Node3D
		if not is_instance_valid(actor_node):
			return false
		check_pos = actor_node.global_position
	elif actor_or_pos is Vector3:
		check_pos = actor_or_pos
	else:
		return false

	var center: Vector3 = global_position + trigger_offset
	var reached_flag: bool = center.distance_to(check_pos) <= arrival_radius
	if reached_flag and actor_or_pos is Node3D:
		print("Waypoint3D: [", name, "] reached by ", (actor_or_pos as Node3D).name)
		reached.emit(actor_or_pos as Node3D)
	return reached_flag
