## Activates connected targets when the player gazes at a specified [Node3D].
class_name TriggerLook
extends BaseTriggerArea3D

@export_group("Trigger Settings")
## The [Node3D] reference the player must look toward.
@export var look_target: Node3D

## Required continuous gaze duration in seconds.
@export var required_look_time: float = 2.0

## Tolerance cosine dot threshold for looking cone accuracy.
@export_range(0.0, 1.0) var look_tolerance: float = 0.95

## Compatibility alias linking to base [member BaseTriggerArea3D.trigger_once].
@export var fire_once: bool:
	get:
		return trigger_once
	set(value):
		trigger_once = value

@export_group("Action Settings")
## Target nodes receiving power activation calls.
@export var targets: Array[Node]

## Indicates if the player character is inside this volume.
var _player_inside: bool = false

## Accumulated gaze duration on the target node.
var _current_look_time: float = 0.0

## Cached viewport [Camera3D] node reference.
var _cached_camera: Camera3D = null


## Initializes base trigger bounds and gates per-frame process evaluation.
func _ready() -> void:
	super._ready()
	set_process(false)


## Evaluates player camera gaze alignment against target each frame while player is inside.
func _process(delta: float) -> void:
	if (
		not _player_inside
		or (trigger_once and _has_triggered)
		or not is_instance_valid(look_target)
	):
		set_process(false)
		return

	var cam: Camera3D = _get_camera()
	if not is_instance_valid(cam):
		return

	var dir_to_target: Vector3 = cam.global_position.direction_to(look_target.global_position)
	var camera_forward: Vector3 = -cam.global_transform.basis.z
	var dot_product: float = camera_forward.dot(dir_to_target)

	if dot_product >= look_tolerance:
		_current_look_time += delta
		if _current_look_time >= required_look_time:
			_trigger_event()
	else:
		_current_look_time = 0.0


## Activates gaze evaluation process when player enters the volume.
func _on_player_entered(_player: Node3D) -> void:
	print("TriggerLook: Player entered volume -> ", _player.name)
	_player_inside = true
	if not (trigger_once and _has_triggered):
		set_process(true)


## Deactivates gaze evaluation process and resets gaze timer when player exits the volume.
func _on_player_exited(_player: Node3D) -> void:
	print("TriggerLook: Player exited volume -> ", _player.name)
	_player_inside = false
	_current_look_time = 0.0
	set_process(false)


## Dispatches power activation to connected targets.
func _trigger_event() -> void:
	print("TriggerLook: Gaze threshold met, activating targets.")
	if trigger_once:
		_has_triggered = true
		set_process(false)

	for target: Node in targets:
		if not is_instance_valid(target):
			continue

		if target.has_method(&"add_power"):
			print("TriggerLook: Calling add_power() on target: ", target.name)
			target.call(&"add_power")
		else:
			var comp: Node = target.get_node_or_null("PowerComponent")
			if is_instance_valid(comp) and comp.has_method(&"add_power"):
				print("TriggerLook: Calling add_power() on PowerComponent of: ", target.name)
				comp.call(&"add_power")


## Fetches and caches the active viewport [Camera3D] node.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		var vp: Viewport = get_viewport()
		if is_instance_valid(vp):
			_cached_camera = vp.get_camera_3d()
	return _cached_camera
