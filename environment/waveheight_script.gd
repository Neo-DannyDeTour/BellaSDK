@tool
## Adjusts mesh draft, tilt, and sway to match dynamic water height.
class_name WaveHeightController
extends MeshInstance3D

## Water surface node providing height via get_height().
@export var water: Node3D

@export_group("Buoyancy Settings")
## Vertical draft displacement offset into the water.
@export var float_offset: float = -0.5

## Distance between virtual wave probe sampling points.
@export var probe_spacing: float = 1.5

## Damping response rate adjusting to wave movement.
@export var responsiveness: float = 6.0

## Indicates whether linked water node provides get_height().
var _is_water_valid: bool = false

## Cached longitudinal probe offset vector along Z-axis.
var _z_offset: Vector3 = Vector3.ZERO

## Cached lateral probe offset vector along X-axis.
var _x_offset: Vector3 = Vector3.ZERO

## Cached target position vector avoiding per-tick heap allocations.
var _target_pos: Vector3 = Vector3.ZERO


## Validates water reference and pre-caches probe vectors.
func _ready() -> void:
	print("WaveHeightController: Initializing buoyancy script on: ", name)
	if is_instance_valid(water) and water.has_method(&"get_height"):
		_is_water_valid = true
		print("WaveHeightController: Water node successfully linked for: ", name)
	else:
		push_warning("WaveHeightController: Water node missing get_height() on: " + name)

	_z_offset = Vector3(0.0, 0.0, probe_spacing)
	_x_offset = Vector3(probe_spacing, 0.0, 0.0)


## Samples wave height probes and damps transform each frame via [MathUtils].
func _process(delta: float) -> void:
	if not _is_water_valid or not is_instance_valid(water):
		return

	var pos: Vector3 = global_position
	var h_center: float = float(water.call(&"get_height", pos))
	var h_front: float = float(water.call(&"get_height", pos + _z_offset))
	var h_back: float = float(water.call(&"get_height", pos - _z_offset))
	var h_right: float = float(water.call(&"get_height", pos + _x_offset))
	var h_left: float = float(water.call(&"get_height", pos - _x_offset))

	var target_y: float = h_center + float_offset
	var slope_x: float = (h_right - h_left) / (probe_spacing * 2.0)
	var slope_z: float = (h_front - h_back) / (probe_spacing * 2.0)
	var surface_normal: Vector3 = Vector3(-slope_x, 1.0, -slope_z).normalized()

	var sway_x: float = surface_normal.x * 2.0
	var sway_z: float = surface_normal.z * 2.0

	_target_pos.x = pos.x + (sway_x * delta)
	_target_pos.y = target_y
	_target_pos.z = pos.z + (sway_z * delta)

	global_position = MathUtils.damp_v3(global_position, _target_pos, responsiveness, delta)

	var current_basis: Basis = global_transform.basis
	var forward: Vector3 = -current_basis.z
	var target_right: Vector3 = forward.cross(surface_normal).normalized()
	if target_right.is_zero_approx():
		target_right = current_basis.x

	var target_forward: Vector3 = surface_normal.cross(target_right).normalized()
	var target_basis: Basis = Basis(target_right, surface_normal, -target_forward)

	var damp_weight: float = 1.0 - exp(-responsiveness * delta)
	global_transform.basis = current_basis.slerp(target_basis, damp_weight).orthonormalized()
