class_name SlideTrack
extends Path3D

# --------------------------------------
# EXPORTS (Visible on Root Node)
# --------------------------------------
@export_category("Path Stick Settings")
## Move speed.
@export var move_speed: float = 15.0
## Throw speed threshold.
@export var throw_speed_threshold: float = 8.0
## Throw velocity local.
@export var throw_velocity_local: Vector3 = Vector3(0.0, 5.0, -20.0)

@export_category("End Behavior")
## Stay at end.
@export var stay_at_end: bool = false
## Return immediately.
@export var return_immediately: bool = false

# --------------------------------------
# VARIABLES
# --------------------------------------
## Path stick.
@onready var path_stick: PathStick = $PathStick


# --------------------------------------
# BUILT-IN METHODS
# --------------------------------------
func _ready() -> void:
	if is_instance_valid(path_stick):
		path_stick.move_speed = move_speed
		path_stick.throw_speed_threshold = throw_speed_threshold
		path_stick.throw_velocity_local = throw_velocity_local
		path_stick.stay_at_end = stay_at_end
		path_stick.return_immediately = return_immediately
	else:
		push_error("SlideTrack: PathStick child node not found!")
