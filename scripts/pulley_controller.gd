class_name PulleyConstraint3D
extends Node3D

@export_category("Connected Bodies")
@export var cart_a: RigidBody3D
@export var cart_b: RigidBody3D

@export_category("Visuals")
@export var visual_cable: SeamlessCable3D

@export_category("Constraint Settings")
## How stiff the imaginary rope is. Higher values mean less rubber-banding.
@export var tension_stiffness: float = 250.0
@export var damping: float = 10.0

var _target_total_length: float = 0.0


func _ready() -> void:
	if is_instance_valid(cart_a) and is_instance_valid(cart_b):
		calibrate_rope_length()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(cart_a) or not is_instance_valid(cart_b):
		return
		
	_apply_pulley_forces()


## Call this if you ever teleport the carts or need to reset the puzzle.
func calibrate_rope_length() -> void:
	_target_total_length = cart_a.global_position.y + cart_b.global_position.y
	print("Pulley System calibrated: Locked base Y distance at ", _target_total_length)


func _apply_pulley_forces() -> void:
	# 1. Calculate the error in the "rope"
	var current_length: float = cart_a.global_position.y + cart_b.global_position.y
	var stretch_error: float = _target_total_length - current_length
	
	# 2. Calculate relative velocity to apply damping (stops infinite bouncing)
	var relative_velocity: float = cart_a.linear_velocity.y + cart_b.linear_velocity.y
	
	# 3. Hooke's Law (Spring Force) to simulate the rigid connection
	var correction_force: float = (stretch_error * tension_stiffness) - (relative_velocity * damping)
	
	# 4. Apply the corrective forces to both carts
	# If A goes down, it pulls B up, and vice versa.
	cart_a.apply_central_force(Vector3.UP * correction_force * cart_a.mass)
	cart_b.apply_central_force(Vector3.UP * correction_force * cart_b.mass)
