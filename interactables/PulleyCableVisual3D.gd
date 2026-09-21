@tool
## Stretches and aligns a visual cylinder mesh between an anchor and a moving cart.
class_name PulleyCableVisual3D
extends Node3D

# --------------------------------------
# CONSTANTS
# --------------------------------------

## Squared distance threshold to detect positional changes.
const POSITION_EPSILON_SQUARED: float = 0.000001

## Minimum squared distance between endpoints required to orient the mesh.
const MIN_SPAN_DISTANCE_SQUARED: float = 0.000001

# --------------------------------------
# EXPORTS
# --------------------------------------

@export_category("Connections")
## Fixed overhead attachment point for the cable.
@export var overhead_anchor: Node3D

## Moving target node connected to the lower end of the cable.
@export var cart: Node3D

@export_category("Visuals")
## Cylinder mesh instance oriented and scaled along the cable axis.
@export var cable_mesh: MeshInstance3D

# --------------------------------------
# INTERNAL VARIABLES
# --------------------------------------

## Cached global position of the overhead anchor from previous frame.
var _cached_top_pos: Vector3 = Vector3.INF

## Cached global position of the cart from previous frame.
var _cached_bottom_pos: Vector3 = Vector3.INF

# --------------------------------------
# ENGINE METHODS
# --------------------------------------


## Validates required mesh references and initializes tracking.
func _ready() -> void:
	if not Engine.is_editor_hint():
		print("PulleyCableVisual3D: Initializing optimized straight cable.")

	if not is_instance_valid(cable_mesh):
		printerr("PulleyCableVisual3D: Error - Missing cable_mesh instance!")


## Inspects endpoint movements and triggers mesh reorientation when dirty.
func _process(_delta: float) -> void:
	if (
		not is_instance_valid(overhead_anchor)
		or not is_instance_valid(cart)
		or not is_instance_valid(cable_mesh)
	):
		return

	var top_pos: Vector3 = overhead_anchor.global_position
	var bottom_pos: Vector3 = cart.global_position

	var top_dirty: bool = top_pos.distance_squared_to(_cached_top_pos) > POSITION_EPSILON_SQUARED
	var bottom_dirty: bool = (
		bottom_pos.distance_squared_to(_cached_bottom_pos) > POSITION_EPSILON_SQUARED
	)

	if top_dirty or bottom_dirty:
		_cached_top_pos = top_pos
		_cached_bottom_pos = bottom_pos
		_stretch_cable_to_fit(top_pos, bottom_pos)


# --------------------------------------
# VISUAL POSITIONING
# --------------------------------------


## Positions, aligns, and scales the cylinder mesh between the two coordinates.
func _stretch_cable_to_fit(top_pos: Vector3, bottom_pos: Vector3) -> void:
	var delta_vec: Vector3 = bottom_pos - top_pos
	var dist_sq: float = delta_vec.length_squared()

	cable_mesh.global_position = top_pos.lerp(bottom_pos, 0.5)

	if dist_sq > MIN_SPAN_DISTANCE_SQUARED:
		var distance: float = sqrt(dist_sq)
		var norm_dir: Vector3 = delta_vec / distance

		var up_vector: Vector3 = Vector3.UP if absf(norm_dir.y) < 0.999 else Vector3.RIGHT
		cable_mesh.look_at(bottom_pos, up_vector)
		cable_mesh.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		cable_mesh.scale = Vector3(1.0, distance * 0.5, 1.0)
