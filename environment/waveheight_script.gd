@tool
## A script that simulates buoyancy by adjusting the height and rotation of a mesh
## to match the surface of a dynamic water plane.
##
## [WaveHeightController] calculates the height of the water at multiple points to determine
## the draft and tilt of the mesh, causing it to bob and sway with the waves.
class_name WaveHeightController
extends MeshInstance3D

## The water node providing height calculations via a [method get_height] method.
@export var water: Node3D

@export_group("Buoyancy Settings")
## How deep the ship sits in the water (negative values push it down)
@export var float_offset: float = -0.5
## Distance between virtual probes. Set roughly to half the ship's length/width.
@export var probe_spacing: float = 1.5
## How smoothly the ship reacts to waves. Higher = stiffer.
@export var responsiveness: float = 6.0

## Tracks if the water node is valid and has the required methods.
var _is_water_valid: bool = false

## Cached Z-axis offset vector for probe calculations.
var _z_offset: Vector3 = Vector3.ZERO

## Cached X-axis offset vector for probe calculations.
var _x_offset: Vector3 = Vector3.ZERO


## Called when the node enters the scene tree for the first time.
## Validates the water node and caches offset vectors.
func _ready() -> void:
	print("Initializing buoyancy script on: ", name)

	# 1. SAFETY: Cache the check once on startup instead of every frame
	if water and water.has_method("get_height"):
		_is_water_valid = true
		print("Water node successfully linked for: ", name)
	else:
		print("Warning: Water node missing or lacks get_height() on: ", name)

	# Cache the vector math so we don't allocate objects every frame
	_z_offset = Vector3(0.0, 0.0, probe_spacing)
	_x_offset = Vector3(probe_spacing, 0.0, 0.0)


## Called every frame. Calculates buoyancy and updates the mesh's position and rotation.
## [param delta] The time elapsed since the previous frame in seconds.
func _process(delta: float) -> void:
	if not _is_water_valid:
		return

	var pos: Vector3 = global_position

	# 2. PROBES: Use the cached offset vectors
	var h_center: float = water.get_height(pos)
	var h_front: float = water.get_height(pos + _z_offset)
	var h_back: float = water.get_height(pos - _z_offset)
	var h_right: float = water.get_height(pos + _x_offset)
	var h_left: float = water.get_height(pos - _x_offset)

	# 3. DRAFT
	var target_y: float = h_center + float_offset

	# 4. TILT
	var slope_x: float = (h_right - h_left) / (probe_spacing * 2.0)
	var slope_z: float = (h_front - h_back) / (probe_spacing * 2.0)

	var surface_normal: Vector3 = Vector3(-slope_x, 1.0, -slope_z).normalized()

	# 5. SWAY
	var sway_x: float = surface_normal.x * 2.0
	var sway_z: float = surface_normal.z * 2.0

	# 6. APPLY POSITION
	var target_pos: Vector3 = Vector3(pos.x + (sway_x * delta), target_y, pos.z + (sway_z * delta))

	global_position = global_position.lerp(target_pos, responsiveness * delta)

	# 7. APPLY ROTATION
	var current_basis: Basis = global_transform.basis
	var target_right: Vector3 = surface_normal.cross(current_basis.z).normalized()
	var target_forward: Vector3 = target_right.cross(surface_normal).normalized()

	var target_basis: Basis = Basis(target_right, surface_normal, target_forward)

	global_transform.basis = (
		current_basis.slerp(target_basis, responsiveness * delta).orthonormalized()
	)
