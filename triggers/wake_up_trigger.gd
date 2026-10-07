@tool
## 3D trigger volume orchestrating a camera wake-up sequence.
class_name WakeUpTrigger
extends Area3D

@export_group("Trigger Volume")
## Geometric shape options for the 3D trigger visualizer and collision hull.
@export var shape_type: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		shape_type = value
		if is_inside_tree():
			_update_visuals()

## Extents of the trigger box or bounds of the sphere.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_inside_tree():
			_update_visuals()

## Local offset applied to collision shape and visualizer node.
@export var trigger_offset: Vector3 = Vector3.ZERO:
	set(value):
		trigger_offset = value
		if is_inside_tree():
			_update_visuals()

@export_group("Trigger Debug Visualizer")
## Determines if the visualizer persists during active gameplay.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree():
			_update_visuals()

## Base tint and opacity applied to volumetric inner fill.
@export var trigger_color: Color = Color(0.2, 0.6, 1.0, 0.25):
	set(value):
		trigger_color = value
		if is_inside_tree():
			_update_visuals()

## Edge color for the outline wireframe cage and orientation arrow.
@export var outline_color: Color = Color(0.4, 0.8, 1.0, 0.9):
	set(value):
		outline_color = value
		if is_inside_tree():
			_update_visuals()

## Allows visualizer to remain visible through level geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_inside_tree():
			_update_visuals()

## Displays forward arrow along local -Z axis indicating orientation.
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

## Primary debug text displayed on trigger label in the editor.
@export var trigger_text: String = "WAKE UP TRIGGER":
	set(value):
		trigger_text = value
		if is_inside_tree():
			_update_visuals()

@export_group("Trigger Settings")
## Starts sequence immediately on scene load.
@export var trigger_on_start: bool = false

## Determines if cinematic sequence triggers only once.
@export var trigger_once: bool = true

@export_group("Wake Up Timings")
## Color overlay used during unconscious state.
@export var fade_color: Color = Color.BLACK

## Total duration for blackness to dissipate and eyelids to open.
@export var eye_open_duration: float = 2.0

## Duration for surrounding blur to resolve back to clear focus.
@export var blur_clear_duration: float = 1.5

## Number of blinks during eye opening sequence.
@export_range(0, 6) var blink_count: int = 3

## Maximum blur strength when eyes begin opening.
@export var max_blur: float = 2.5

## Seconds camera tilts upward while lying down.
@export var look_up_duration: float = 1.8

## Seconds camera lingers looking up before standing up.
@export var gaze_hold_duration: float = 0.6

## Seconds taken to transition from ground to standing height.
@export var stand_up_duration: float = 2.4

@export_group("Camera Angles")
## Camera eye height above ground when lying down.
@export var lying_camera_height: float = 0.25

## Roll tilt in degrees while lying on ground.
@export var lying_camera_roll: float = -28.0

## Target pitch angle in degrees looking upward from the ground.
@export var look_up_pitch: float = 38.0

@export_group("Narrative Text")
## Narrative or chapter text shown during sequence.
@export_multiline var intro_text: String = ""

## Seconds before narrative text starts fading in.
@export var text_delay: float = 0.8

## Fade-in duration for the narrative text.
@export var text_fade_in_duration: float = 1.0

## Duration text stays on screen.
@export var text_hold_duration: float = 2.5

## Fade-out duration for the narrative text.
@export var text_fade_out_duration: float = 1.0

## Tracks whether this trigger has already fired.
var _triggered: bool = false

## Cached collision shape child defining trigger volume.
var _collision_shape: CollisionShape3D = null

## Active camera node being animated.
var _active_camera: Camera3D = null

## Default local position of camera before transition.
var _default_cam_position: Vector3 = Vector3.ZERO

## Default local rotation of camera before transition.
var _default_cam_rotation: Vector3 = Vector3.ZERO

## Target local camera position when lying down on the ground.
var _lying_cam_position: Vector3 = Vector3.ZERO

## Active [Tween] driving the camera motion sequence.
var _seq_tween: Tween = null


## Initializes bounds, collision layers, and executes frame-zero blackout.
func _ready() -> void:
	print("WakeUpTrigger: Initializing trigger.")
	_collision_shape = (get_node_or_null("CollisionShape3D") as CollisionShape3D)
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

	if trigger_on_start:
		Events.player_cinematic_lock_requested.emit(true)
		Events.screen_blackout_instant_requested.emit(true, max_blur, fade_color)
		_find_and_trigger_player()


## Rebuilds collision shape and synchronizes [EditorTriggerVisualizer].
func _update_visuals() -> void:
	if not is_inside_tree():
		return

	if not is_instance_valid(_collision_shape):
		_collision_shape = (get_node_or_null("CollisionShape3D") as CollisionShape3D)

	if is_instance_valid(_collision_shape):
		if shape_type == EditorTriggerVisualizer.ShapeType.BOX:
			if not (_collision_shape.shape is BoxShape3D):
				_collision_shape.shape = BoxShape3D.new()
			else:
				_collision_shape.shape = _collision_shape.shape.duplicate()
			_collision_shape.shape.resource_local_to_scene = true
			var box_shape: BoxShape3D = (
				_collision_shape.shape if _collision_shape.shape is BoxShape3D else null
			)
			box_shape.size = trigger_size
		elif shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
			if not (_collision_shape.shape is SphereShape3D):
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


## Finds player node and prepares initial ground placement immediately.
func _find_and_trigger_player() -> void:
	print("WakeUpTrigger: Searching for player in scene tree.")
	if trigger_once and _triggered:
		return

	var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if not players.is_empty() and players[0] is Player:
		var p: Player = players[0] if players[0] is Player else null
		_prepare_lying_pose(p)
		_start_sequence(p)
	else:
		call_deferred(&"_find_and_trigger_player")


## Evaluates player body entry collision.
func _on_body_entered(body: Node3D) -> void:
	print("WakeUpTrigger: _on_body_entered triggered by: ", body.name)
	if Engine.is_editor_hint():
		return

	var p: Player = body if body is Player else null
	if not is_instance_valid(p):
		return

	if trigger_once and _triggered:
		return

	print("WakeUpTrigger: Player entered trigger zone: ", p.name)
	_prepare_lying_pose(p)
	_start_sequence(p)


## Presets camera position on ground while hidden behind blackout.
func _prepare_lying_pose(p: Player) -> void:
	print("WakeUpTrigger: Preparing ground lying pose.")
	_active_camera = _find_camera(p)
	if not is_instance_valid(_active_camera):
		return

	_default_cam_position = _active_camera.position
	_default_cam_rotation = _active_camera.rotation_degrees

	var space_state: PhysicsDirectSpaceState3D = _active_camera.get_world_3d().direct_space_state
	var ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		_active_camera.global_position, _active_camera.global_position + (Vector3.DOWN * 6.0)
	)
	ray_params.exclude = [p.get_rid()]
	var ray_hit: Dictionary = space_state.intersect_ray(ray_params)

	var floor_y: float = p.global_position.y
	if not ray_hit.is_empty():
		var hit_pos_raw: Variant = ray_hit.get(&"position")
		if hit_pos_raw is Vector3:
			var hit_pos: Vector3 = hit_pos_raw
			floor_y = hit_pos.y

	var target_world_y: float = floor_y + lying_camera_height
	var height_drop: float = _active_camera.global_position.y - target_world_y

	_lying_cam_position = Vector3(
		_default_cam_position.x, _default_cam_position.y - height_drop, _default_cam_position.z
	)

	_active_camera.position = _lying_cam_position
	_active_camera.rotation_degrees = Vector3(12.0, _default_cam_rotation.y, lying_camera_roll)


## Orchestrates camera positioning, blinks, and stand-up motion sequentially.
func _start_sequence(p: Player) -> void:
	if trigger_once and _triggered:
		return

	_triggered = true
	print("WakeUpTrigger: Starting wake-up sequence for: ", p.name)
	Events.player_cinematic_lock_requested.emit(true)
	Events.screen_blackout_instant_requested.emit(true, max_blur, fade_color)

	var total_text_time: float = 0.5
	if not intro_text.is_empty():
		total_text_time = (
			text_delay + text_fade_in_duration + text_hold_duration + text_fade_out_duration
		)
		_dispatch_intro_text()

	if _seq_tween and _seq_tween.is_valid():
		_seq_tween.kill()

	_seq_tween = create_tween()
	_seq_tween.tween_interval(total_text_time)

	_seq_tween.tween_callback(
		func() -> void:
			print("WakeUpTrigger: Eyes opening from floor.")
			Events.screen_wake_up_requested.emit(
				fade_color, eye_open_duration, max_blur, blink_count, blur_clear_duration
			)
	)

	_seq_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_seq_tween.tween_property(_active_camera, "rotation_degrees:x", look_up_pitch, look_up_duration)
	_seq_tween.parallel().tween_property(
		_active_camera, "rotation_degrees:z", lying_camera_roll * 0.2, look_up_duration
	)

	var remaining_blur_time: float = maxf(
		0.1, (eye_open_duration + blur_clear_duration) - look_up_duration
	)
	_seq_tween.tween_interval(remaining_blur_time + gaze_hold_duration)

	_seq_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_seq_tween.tween_property(
		_active_camera, "position:y", _default_cam_position.y, stand_up_duration
	)
	_seq_tween.parallel().tween_property(
		_active_camera, "rotation_degrees:x", _default_cam_rotation.x, stand_up_duration
	)
	_seq_tween.parallel().tween_property(
		_active_camera, "rotation_degrees:z", _default_cam_rotation.z, stand_up_duration
	)

	_seq_tween.finished.connect(_on_sequence_completed)


## Dispatches narrative text to [member Events] after configured delay.
func _dispatch_intro_text() -> void:
	print("WakeUpTrigger: Scheduling intro text dispatch.")
	var timer: SceneTreeTimer = get_tree().create_timer(text_delay)
	timer.timeout.connect(
		func() -> void:
			Events.wake_up_text_requested.emit(
				intro_text, text_fade_in_duration, text_hold_duration, text_fade_out_duration
			)
	)


## Finds child [Camera3D] within player node hierarchy.
func _find_camera(node: Node) -> Camera3D:
	print("WakeUpTrigger: Scanning node for Camera3D -> ", node.name)
	if node is Camera3D:
		return node as Camera3D
	for child: Node in node.get_children():
		var cam: Camera3D = _find_camera(child)
		if is_instance_valid(cam):
			return cam
	return null


## Restores player camera transforms and releases movement lock.
func _on_sequence_completed() -> void:
	print("WakeUpTrigger: Sequence completed. Releasing player lock.")
	if is_instance_valid(_active_camera):
		_active_camera.position = _default_cam_position
		_active_camera.rotation_degrees = _default_cam_rotation

	Events.player_cinematic_lock_requested.emit(false)
