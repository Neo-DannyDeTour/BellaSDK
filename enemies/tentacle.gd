## A visual manager that generates a procedural, arcing tentacle mesh between two points.
##
## [ProceduralTentacle3D] dynamically constructs a series of cylinder segments arranged
## along a quadratic Bezier curve to visually connect a base node and a target node.
## It handles creating and pooling the meshes efficiently to maintain a high framerate.
class_name ProceduralTentacle3D
extends Node3D

## The starting point of the tentacle, usually the base of the enemy.
@export var base_node: Node3D

## The target point the tentacle dynamically reaches towards.
@export var target_node: Node3D

## The total number of visual cylinder meshes to generate for the body.
@export var segment_count: int = 15

## The visual color applied to the tentacle material.
@export var tentacle_color: Color = Color(0.3, 0.1, 0.4)

## The radius of the tentacle meshes.
@export var thickness: float = 0.15

## Internal array tracking all spawned mesh segments to update them per frame.
var _segments: Array[MeshInstance3D] = []

## The shared mesh resource used by all segments to save memory.
var _base_mesh: CylinderMesh


## Initializes the shared mesh and spawns the required number of visual segments.
func _ready() -> void:
	print("ProceduralTentacle3D: _ready() - Generating optimized procedural tentacle.")
	_create_base_mesh()
	_spawn_visual_segments()


## Frame execution lifecycle method that recalculates and positions the Bezier curve segments.
## [param _delta] The time elapsed since the previous physics tick in seconds.
func _process(_delta: float) -> void:
	if not is_instance_valid(base_node) or not is_instance_valid(target_node):
		return

	var p0: Vector3 = base_node.global_position
	var p2: Vector3 = target_node.global_position

	var distance_sq: float = p0.distance_squared_to(p2)
	var distance: float = sqrt(distance_sq)
	var p1: Vector3 = p0.lerp(p2, 0.5)
	p1.y += (distance * 0.6)

	var prev_pos: Vector3 = p0

	for i: int in range(segment_count):
		var t: float = float(i + 1) / float(segment_count)
		var current_pos: Vector3 = _get_quadratic_bezier(p0, p1, p2, t)

		_update_visual_segment(_segments[i], prev_pos, current_pos)
		prev_pos = current_pos


## Creates the highly optimized cylinder mesh instance shared across all segments.
func _create_base_mesh() -> void:
	print("ProceduralTentacle3D: _create_base_mesh() - Creating shared cylinder mesh.")
	_base_mesh = CylinderMesh.new()
	_base_mesh.top_radius = thickness
	_base_mesh.bottom_radius = thickness
	_base_mesh.height = 1.0
	_base_mesh.radial_segments = 8
	_base_mesh.rings = 1

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tentacle_color
	mat.roughness = 0.6
	_base_mesh.material = mat


## Instantiates the requested number of mesh segments and stores them in the internal array.
func _spawn_visual_segments() -> void:
	print("ProceduralTentacle3D: _spawn_visual_segments() - Instantiating segments.")
	for i: int in range(segment_count):
		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.mesh = _base_mesh
		segment.top_level = true
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(segment)
		_segments.append(segment)


## Mathematical helper calculating a point along a quadratic Bezier curve.
## [param p0] The starting point vector.
## [param p1] The control point vector dictating the arc.
## [param p2] The ending point vector.
## [param t] The interpolation step from 0.0 to 1.0.
## Returns the calculated point as a [Vector3].
func _get_quadratic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var q0: Vector3 = p0.lerp(p1, t)
	var q1: Vector3 = p1.lerp(p2, t)
	return q0.lerp(q1, t)


## Transforms, rotates, and stretches an individual segment to connect two points flawlessly.
## [param segment] The visual [MeshInstance3D] to update.
## [param p1] The starting position for the segment.
## [param p2] The ending position for the segment.
func _update_visual_segment(segment: MeshInstance3D, p1: Vector3, p2: Vector3) -> void:
	var dist_sq: float = p1.distance_squared_to(p2)
	var dist: float = sqrt(dist_sq)
	segment.global_position = p1.lerp(p2, 0.5)

	var dir: Vector3 = p2 - p1
	if dir.length_squared() > 0.000001:
		var up: Vector3 = Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
		segment.look_at(p2, up)
		segment.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	segment.scale = Vector3(1.0, dist, 1.0)
