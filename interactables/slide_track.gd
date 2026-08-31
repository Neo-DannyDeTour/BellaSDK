## A sliding track that automatically configures an attached [PathStick].
##
## Manages movement speed, throwing physics constraints, and return behaviors
## for objects traversing along a defined 3D path curve.
class_name SlideTrack
extends Path3D

# --------------------------------------
# EXPORTS (Visible on Root Node)
# --------------------------------------
@export_category("Path Stick Settings")
## The base travel speed at which the stick moves along the track.
@export var move_speed: float = 15.0
## The minimum velocity required from the player to throw the stick.
@export var throw_speed_threshold: float = 8.0
## The localized velocity vector applied to the stick when thrown.
@export var throw_velocity_local: Vector3 = Vector3(0.0, 5.0, -20.0)

@export_category("End Behavior")
## If true, the stick remains at the end of the path rather than resetting.
@export var stay_at_end: bool = false
## If true, the stick snaps immediately back to its starting position upon reaching the end.
@export var return_immediately: bool = false

# --------------------------------------
# VARIABLES
# --------------------------------------
## The child [PathStick] node that physically travels along this path.
@onready var path_stick: PathStick = $PathStick


# --------------------------------------
# BUILT-IN METHODS
# --------------------------------------
## Synchronizes export configuration variables to the assigned [PathStick] node upon creation.
func _ready() -> void:
	if is_instance_valid(path_stick):
		path_stick.move_speed = move_speed
		path_stick.throw_speed_threshold = throw_speed_threshold
		path_stick.throw_velocity_local = throw_velocity_local
		path_stick.stay_at_end = stay_at_end
		path_stick.return_immediately = return_immediately
	else:
		push_error("SlideTrack: PathStick child node not found!")
