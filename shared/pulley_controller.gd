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

@export_category("Travel Limits")
## The max distance (in meters) a cart can drop. 0.0 means unlimited.
@export var max_travel_meters: float = 0.0
## How violently the rope stops the cart when it reaches the max length.
@export var hard_stop_stiffness: float = 1000.0

@onready var _editor_icon: Sprite3D = %EditorIcon

var _target_total_length: float = 0.0
var _cart_a_start_y: float = 0.0
var _cart_b_start_y: float = 0.0

# Track states to prevent print() spamming every frame at 60 FPS
var _hit_limit_a: bool = false
var _hit_limit_b: bool = false


func _ready() -> void:
	# 1. Purge the editor icon immediately at runtime (Zero overhead!)
	if not Engine.is_editor_hint():
		if is_instance_valid(_editor_icon):
			_editor_icon.queue_free()

	if is_instance_valid(cart_a) and is_instance_valid(cart_b):
		calibrate_rope_length()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(cart_a) or not is_instance_valid(cart_b):
		return

	_apply_pulley_forces()

	if max_travel_meters > 0.0:
		_apply_travel_limits()


func calibrate_rope_length() -> void:
	_cart_a_start_y = cart_a.global_position.y
	_cart_b_start_y = cart_b.global_position.y
	_target_total_length = _cart_a_start_y + _cart_b_start_y

	print("Pulley System: Calibrated base Y distance at ", _target_total_length)
	if max_travel_meters > 0.0:
		print("Pulley System: Max travel distance set to ", max_travel_meters, "m.")
	else:
		print("Pulley System: Max travel distance is unlimited.")


func _apply_pulley_forces() -> void:
	var current_length: float = cart_a.global_position.y + cart_b.global_position.y
	var stretch_error: float = _target_total_length - current_length

	var rel_velocity: float = cart_a.linear_velocity.y + cart_b.linear_velocity.y
	var c_force: float = (stretch_error * tension_stiffness) - (rel_velocity * damping)

	cart_a.apply_central_force(Vector3.UP * c_force * cart_a.mass)
	cart_b.apply_central_force(Vector3.UP * c_force * cart_b.mass)


func _apply_travel_limits() -> void:
	# Calculate how far each cart has dropped relative to its starting point
	var drop_a: float = _cart_a_start_y - cart_a.global_position.y
	var drop_b: float = _cart_b_start_y - cart_b.global_position.y

	# Check limit for Cart A
	if drop_a > max_travel_meters:
		if not _hit_limit_a:
			print("Pulley System: Cart A reached maximum travel limit.")
			_hit_limit_a = true

		var over_travel: float = drop_a - max_travel_meters
		var stop_force: float = over_travel * hard_stop_stiffness
		cart_a.apply_central_force(Vector3.UP * stop_force * cart_a.mass)
	elif _hit_limit_a:
		_hit_limit_a = false

	# Check limit for Cart B
	if drop_b > max_travel_meters:
		if not _hit_limit_b:
			print("Pulley System: Cart B reached maximum travel limit.")
			_hit_limit_b = true

		var over_travel: float = drop_b - max_travel_meters
		var stop_force: float = over_travel * hard_stop_stiffness
		cart_b.apply_central_force(Vector3.UP * stop_force * cart_b.mass)
	elif _hit_limit_b:
		_hit_limit_b = false
