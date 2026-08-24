## A volume that activates connected targets when the player looks at a specific node.
##
## Tracks the player's camera facing direction while they are inside the [Area3D].
## If they look at the [member look_target] for the required duration, it powers on targets.
class_name TriggerLook
extends Area3D

## The object the player needs to look at (e.g., a [Marker3D]).
@export_group("Trigger Settings")
@export var look_target: Node3D
## How long the player must look at the target (in seconds).
@export var required_look_time: float = 2.0
## How exact the look needs to be. 1.0 is dead center, 0.95 gives a forgiving cone.
@export_range(0.0, 1.0) var look_tolerance: float = 0.95
## If true, the trigger can only be fired once.
@export var fire_once: bool = true

## Array of nodes to power on. Can be the PowerComponent itself or the Parent node.
@export_group("Action Settings")
@export var targets: Array[Node]

## Tracks if the player is currently inside the volume.
var _player_inside: bool = false
## The accumulated time the player has spent looking at the target.
var _current_look_time: float = 0.0
## Tracks if the trigger has already successfully fired.
var _has_triggered: bool = false
## Cached [Camera3D] reference to avoid expensive viewport lookups every frame.
var _cached_camera: Camera3D = null


## Automatically connects body entry and exit signals.
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Evaluates the player's camera facing direction against the target node each frame.
func _process(delta: float) -> void:
	if not _player_inside or _has_triggered or not is_instance_valid(look_target):
		return

	if not is_instance_valid(_get_camera()):
		return

	var dir_to_target: Vector3 = _cached_camera.global_position.direction_to(
		look_target.global_position
	)
	var camera_forward: Vector3 = -_cached_camera.global_transform.basis.z
	var dot_product: float = camera_forward.dot(dir_to_target)

	if dot_product >= look_tolerance:
		_current_look_time += delta

		if _current_look_time >= required_look_time:
			_trigger_event()
	else:
		_current_look_time = 0.0


## Dispatches the power signal to all connected targets when the look condition is met.
func _trigger_event() -> void:
	if fire_once:
		_has_triggered = true

	print("Trigger Look completed!")

	# --- SMART POWER SENDER ---
	for target: Variant in targets:
		if target == null:
			continue

		# 1. Did they target the component directly?
		if target.has_method("add_power"):
			target.add_power()
		# 2. Did they target the parent node? Look for the component!
		else:
			var comp: Node = target.get_node_or_null("PowerComponent")
			if comp and comp.has_method("add_power"):
				comp.add_power()


## Flags the player as being inside the look volume.
func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_inside = true


## Flags the player as having left the volume and resets look timers.
func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_inside = false
		_current_look_time = 0.0


## Retrieves and caches the current active [Camera3D] from the viewport.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
	return _cached_camera
