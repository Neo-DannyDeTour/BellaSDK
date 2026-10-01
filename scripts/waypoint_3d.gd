## Agnostic 3D navigation waypoint with linked chains and editor debug gizmos.
@tool
class_name Waypoint3D
extends Marker3D

## Emitted when an entity checks in or reaches within [member arrival_radius].
signal reached(actor: Node3D)

## Distance in units to consider an actor within arrival threshold.
@export_range(0.1, 10.0, 0.1) var arrival_radius: float = 1.0:
	set(value):
		arrival_radius = maxf(0.1, value)
		update_gizmos()

## Next sequential waypoint in path chain for patrol loops or sequences.
@export var next_waypoint: Waypoint3D:
	set(value):
		next_waypoint = value
		update_gizmos()

## Pause duration in seconds actors can query to linger at this spot.
@export var wait_time: float = 0.0

## Speed multiplier tag applied when actors move towards or through this node.
@export var speed_modifier: float = 1.0

## Optional scripted action or animation state tag triggered upon arrival.
@export var action_tag: StringName = &""


## Evaluates whether [param actor_or_pos] is within [member arrival_radius].
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

	var reached_flag: bool = global_position.distance_to(check_pos) <= arrival_radius
	if reached_flag and actor_or_pos is Node3D:
		print("Waypoint3D: [", name, "] reached by ", (actor_or_pos as Node3D).name)
		reached.emit(actor_or_pos as Node3D)
	return reached_flag


## Triggers visual gizmo redrawing inside the Godot 3D editor.
func _notification(what: int) -> void:
	if Engine.is_editor_hint() and what == NOTIFICATION_TRANSFORM_CHANGED:
		update_gizmos()
