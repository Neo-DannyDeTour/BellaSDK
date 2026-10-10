## Activates connected targets when the player gazes at a specified [Node3D].
class_name TriggerLook
extends Area3D

@export_group("Trigger Settings")
## The [Node3D] reference the player must look toward.
@export var look_target: Node3D

## Required continuous gaze duration in seconds.
@export var required_look_time: float = 2.0

## Tolerance cosine dot threshold for looking cone accuracy.
@export_range(0.0, 1.0) var look_tolerance: float = 0.95

## Determines if this look trigger executes only once.
@export var fire_once: bool = true

@export_group("Action Settings")
## Target nodes receiving power activation calls.
@export var targets: Array[Node]

## Indicates if the player character is inside this volume.
var _player_inside: bool = false

## Accumulated gaze duration on the target node.
var _current_look_time: float = 0.0

## Tracks whether activation has already triggered.
var _has_triggered: bool = false

## Cached viewport [Camera3D] node reference.
var _cached_camera: Camera3D = null


## Connects body entry and exit signals to internal listeners and configures physics layers.
func _ready() -> void:
	print("TriggerLook: Initializing gaze trigger volume.")
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_PLAYER
	Utilities.safe_connect(body_entered, _on_body_entered)
	Utilities.safe_connect(body_exited, _on_body_exited)


## Evaluates player camera gaze alignment against target each frame.
func _process(delta: float) -> void:
	if not _player_inside or _has_triggered or not is_instance_valid(look_target):
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


## Dispatches power activation to connected targets.
func _trigger_event() -> void:
	print("TriggerLook: Gaze threshold met, activating targets.")
	if fire_once:
		_has_triggered = true

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


## Detects player body entry into the trigger volume.
func _on_body_entered(body: Node3D) -> void:
	print("TriggerLook: Body entered volume -> ", body.name)
	if body.is_in_group(&"player") or body is Player:
		_player_inside = true


## Detects player body exit and clears active gaze counters.
func _on_body_exited(body: Node3D) -> void:
	print("TriggerLook: Body exited volume -> ", body.name)
	if body.is_in_group(&"player") or body is Player:
		_player_inside = false
		_current_look_time = 0.0


## Fetches and caches the active viewport [Camera3D] node.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		var vp: Viewport = get_viewport()
		if is_instance_valid(vp):
			_cached_camera = vp.get_camera_3d()
	return _cached_camera
