## Dynamic UI button with responsive hover scaling and mouse-tracking tilt spring physics.
class_name JuicyButton
extends Button

## Target scale factor applied when button is hovered.
@export var hover_scale: Vector2 = Vector2(1.08, 1.08)

## Maximum rotational tilt in degrees applied while hovered.
@export var max_rotation_degrees: float = 5.0

## Angular spring stiffness scalar for tilt reactions.
@export var tilt_stiffness: float = 240.0

## Angular damping coefficient preventing infinite tilt oscillations.
@export var tilt_damping: float = 18.0

## Scale spring stiffness scalar for hover scaling.
@export var scale_stiffness: float = 200.0

## Scale damping coefficient for hover scale smoothing.
@export var scale_damping: float = 16.0

## Base scale of the button captured on boot.
var original_scale: Vector2 = Vector2.ONE

## Current scale velocity vector for spring interpolation.
var _scale_velocity: Vector2 = Vector2.ZERO

## Current angular velocity for tilt spring interpolation.
var _rotation_velocity: float = 0.0

## Tracks whether mouse cursor is currently hovering over button.
var is_hovered: bool = false


## Captures baseline scale, centers pivot, and connects hover signals.
func _ready() -> void:
	print("JuicyButton: Initializing interactive button -> ", name)
	original_scale = scale
	Utilities.center_control(self)

	Utilities.safe_connect(mouse_entered, _on_hover)
	Utilities.safe_connect(mouse_exited, _on_unhover)
	Utilities.safe_connect(resized, _on_resized)


## Recalculates center pivot offset using [method Utilities.center_control].
func _on_resized() -> void:
	print("JuicyButton: Resized -> ", name)
	Utilities.center_control(self)


## Sets hover state and prints activation log.
func _on_hover() -> void:
	print("JuicyButton: Mouse entered hover state -> ", name)
	is_hovered = true


## Clears hover state and prints deactivation log.
func _on_unhover() -> void:
	print("JuicyButton: Mouse exited hover state -> ", name)
	is_hovered = false


## Evaluates interactive mouse tilt and scale via [method MathUtils.damped_spring].
## [param delta] Frame delta time in seconds.
func _process(delta: float) -> void:
	var target_scale: Vector2 = hover_scale if is_hovered else original_scale
	var target_rotation: float = 0.0

	if is_hovered:
		var mouse_pos: Vector2 = get_local_mouse_position()
		var center_x: float = size.x * 0.5
		if center_x > 0.001:
			var normalized_x: float = clampf((mouse_pos.x - center_x) / center_x, -1.0, 1.0)
			var max_rad: float = deg_to_rad(max_rotation_degrees)
			target_rotation = MathUtils.clamp_angle_rad(max_rad * normalized_x, -max_rad, max_rad)

	var spring_x: Dictionary = MathUtils.damped_spring(
		scale.x, target_scale.x, _scale_velocity.x, scale_stiffness, scale_damping, delta
	)
	var spring_y: Dictionary = MathUtils.damped_spring(
		scale.y, target_scale.y, _scale_velocity.y, scale_stiffness, scale_damping, delta
	)
	scale.x = spring_x[&"position"]
	_scale_velocity.x = spring_x[&"velocity"]
	scale.y = spring_y[&"position"]
	_scale_velocity.y = spring_y[&"velocity"]

	var rot_spring: Dictionary = MathUtils.damped_spring(
		rotation, target_rotation, _rotation_velocity, tilt_stiffness, tilt_damping, delta
	)
	rotation = rot_spring[&"position"]
	_rotation_velocity = rot_spring[&"velocity"]
