## Sweeps the graphics preview camera horizontally around the Y-axis.
class_name GraphicsCCTVCamera
extends Camera3D

## Maximum sweep angle in degrees to either side.
@export var max_sweep_angle: float = 35.0

## Oscillation sweep speed multiplier.
@export var sweep_speed: float = 0.4

## Base starting Y rotation in radians.
var _initial_rotation_y: float = 0.0

## Elapsed continuous time counter for oscillation math.
var _sweep_time: float = 0.0


## Configures practical camera attributes and caches initial orientation.
func _ready() -> void:
	print("GraphicsCCTVCamera: Initializing preview camera components.")
	_initial_rotation_y = rotation.y
	_setup_camera_attributes()


## Ensures [CameraAttributesPractical] is present for DoF rendering.
func _setup_camera_attributes() -> void:
	print("GraphicsCCTVCamera: Configuring CameraAttributesPractical.")
	if not is_instance_valid(attributes) or not (attributes is CameraAttributesPractical):
		attributes = CameraAttributesPractical.new()

	var attr: CameraAttributesPractical = attributes as CameraAttributesPractical
	attr.dof_blur_far_distance = 6.0
	attr.dof_blur_far_transition = 3.0
	attr.dof_blur_near_distance = 1.0
	attr.dof_blur_near_transition = 0.5
	attr.dof_blur_far_enabled = false
	attr.dof_blur_near_enabled = false
	attr.dof_blur_amount = 0.0


## Frame update applying sinusoidal panning across the Y axis.
func _process(delta: float) -> void:
	if not current:
		return

	_sweep_time += delta * sweep_speed
	var angle_offset: float = deg_to_rad(max_sweep_angle) * sin(_sweep_time)
	rotation.y = _initial_rotation_y + angle_offset
