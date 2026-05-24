@tool
extends MeshInstance3D

@export var water: Node3D

@export_group("Buoyancy Settings")
## How deep the ship sits in the water (negative values push it down)
@export var float_offset: float = -0.5
## The distance between the virtual probes. Set this roughly to half the ship's length/width.
@export var probe_spacing: float = 1.5
## How smoothly the ship reacts to waves. Higher = stiffer, lower = heavier/sluggish.
@export var responsiveness: float = 6.0


func _process(delta: float) -> void:
	# 1. SAFETY: Stop if no water node or function is missing
	if not water or not water.has_method("get_height"):
		return

	var pos: Vector3 = global_position

	# 2. PROBES: Sample the water height at the center, and 4 points around the ship
	# We explicitly type the returns as floats.
	var h_center: float = water.get_height(pos)
	var h_front: float = water.get_height(pos + Vector3(0.0, 0.0, probe_spacing))
	var h_back: float = water.get_height(pos + Vector3(0.0, 0.0, -probe_spacing))
	var h_right: float = water.get_height(pos + Vector3(probe_spacing, 0.0, 0.0))
	var h_left: float = water.get_height(pos + Vector3(-probe_spacing, 0.0, 0.0))

	# 3. DRAFT: Calculate the Target Height (solves the hovering issue)
	var target_y: float = h_center + float_offset

	# 4. TILT: Calculate the Surface Normal using the probes
	var slope_x: float = (h_right - h_left) / (probe_spacing * 2.0)
	var slope_z: float = (h_front - h_back) / (probe_spacing * 2.0)
	var surface_normal: Vector3 = Vector3(-slope_x, 1.0, -slope_z).normalized()

	# 5. SWAY: Fake Horizontal Displacement
	# The boat slides slightly down the slope of the wave, faking horizontal wave movement
	var sway_x: float = surface_normal.x * 2.0
	var sway_z: float = surface_normal.z * 2.0

	# 6. APPLY POSITION (Lerped for smoothness to prevent jerking)
	var target_pos: Vector3 = Vector3(pos.x + sway_x * delta, target_y, pos.z + sway_z * delta)
	global_position = global_position.lerp(target_pos, responsiveness * delta)

	# 7. APPLY ROTATION (Slerped for smooth pitching and rolling)
	var current_basis: Basis = global_transform.basis

	# Align the ship's UP vector to the wave's surface normal
	var target_right: Vector3 = surface_normal.cross(current_basis.z).normalized()
	var target_forward: Vector3 = target_right.cross(surface_normal).normalized()
	var target_basis: Basis = Basis(target_right, surface_normal, target_forward)

	# Slerp (Spherical Linear Interpolation) blends the rotation smoothly
	global_transform.basis = (
		current_basis.slerp(target_basis, responsiveness * delta).orthonormalized()
	)
