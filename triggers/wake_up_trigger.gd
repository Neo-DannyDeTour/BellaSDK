@tool
## 3D trigger volume orchestrating a camera wake-up sequence.
class_name WakeUpTrigger
extends BaseTriggerArea3D

@export_group("Trigger Settings")
## Starts sequence immediately on scene load.
@export var trigger_on_start: bool = false

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
	if trigger_text == "TRIGGER":
		trigger_text = "WAKE UP TRIGGER"
	if trigger_color == Color(0.9, 0.5, 0.1, 0.25):
		trigger_color = Color(0.2, 0.6, 1.0, 0.25)
	if outline_color == Color(1.0, 0.8, 0.3, 0.9):
		outline_color = Color(0.4, 0.8, 1.0, 0.9)
	super._ready()

	if Engine.is_editor_hint():
		return

	if trigger_on_start:
		Events.player_cinematic_lock_requested.emit(true)
		Events.screen_blackout_instant_requested.emit(true, max_blur, fade_color)
		_find_and_trigger_player()


## Evaluates player body entry and begins wake up sequence.
func _on_player_entered(player_node: Node3D) -> void:
	var p: Player = player_node as Player
	if not is_instance_valid(p):
		return

	print("WakeUpTrigger: Player entered trigger zone: ", p.name)
	_prepare_lying_pose(p)
	_start_sequence(p)


## Finds player node and prepares initial ground placement immediately.
func _find_and_trigger_player() -> void:
	print("WakeUpTrigger: Searching for player in scene tree.")
	if trigger_once and _has_triggered:
		return

	var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if not players.is_empty() and players[0] is Player:
		var p: Player = players[0] as Player
		_has_triggered = true
		_prepare_lying_pose(p)
		_start_sequence(p)
	else:
		call_deferred(&"_find_and_trigger_player")


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
