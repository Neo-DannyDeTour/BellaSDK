class_name SlideTrack
extends Path3D

# --------------------------------------
# EXPORTS (Visible on Root Node)
# --------------------------------------
@export_category("Path Stick Settings")
@export var move_speed: float = 15.0
@export var throw_speed_threshold: float = 8.0
@export var throw_velocity_local: Vector3 = Vector3(0.0, 5.0, -20.0)

@export_category("End Behavior")
@export var stay_at_end: bool = false
@export var return_immediately: bool = false

# --------------------------------------
# VARIABLES
# --------------------------------------
@onready var path_stick: PathStick = $PathStick


# --------------------------------------
# BUILT-IN METHODS
# --------------------------------------
func _ready() -> void:
	print("SlideTrack: _ready() called. Pushing configuration to PathStick.")
	
	if is_instance_valid(path_stick):
		path_stick.move_speed = move_speed
		path_stick.throw_speed_threshold = throw_speed_threshold
		path_stick.throw_velocity_local = throw_velocity_local
		path_stick.stay_at_end = stay_at_end
		path_stick.return_immediately = return_immediately
	else:
		push_error("SlideTrack: PathStick child node not found!")
