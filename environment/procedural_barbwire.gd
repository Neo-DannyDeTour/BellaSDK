@tool
## Generates straight or coiled barbed wire meshes with instanced [MultiMesh] barbs.
##
## Constructs geometry by sweeping a cylindrical [ArrayMesh] along a generated [Curve3D].
class_name ProceduralBarbwire
extends Node3D

## Available geometric patterns for the barbed wire span.
enum WireType {
	STRAIGHT,
	SPRING,
}

## Radial segment count for the swept wire cross-section.
const WIRE_SIDES: int = 8

## Sampling step length in meters along helical spring curves.
const WIRE_STEP_METERS: float = 0.1

## Geometric configuration profile for the wire.
@export_category("Wire Shape")

## The procedural path style (Straight span or Helical spring).
@export var wire_type: ProceduralBarbwire.WireType = ProceduralBarbwire.WireType.STRAIGHT:
	set(value):
		wire_type = value
		if is_inside_tree():
			_request_rebuild()

## Total length of the barbed wire in meters.
@export var length: float = 10.0:
	set(value):
		length = value
		if is_inside_tree():
			_request_rebuild()

## Radius thickness of the main extruded wire line.
@export var wire_thickness: float = 0.02:
	set(value):
		wire_thickness = value
		if is_inside_tree():
			_request_rebuild()

## Configuration parameters for helical spring generation.
@export_category("Spring Settings")

## Radial expansion distance of helical coils from the center axis.
@export var spring_radius: float = 0.3:
	set(value):
		spring_radius = value
		if is_inside_tree():
			_request_rebuild()

## Total number of full helical turns across the wire length.
@export var spring_coils: int = 12:
	set(value):
		spring_coils = value
		if is_inside_tree():
			_request_rebuild()

## Number of curve sample vertices generated per individual spring coil.
@export var spring_resolution: int = 64:
	set(value):
		spring_resolution = maxi(4, value)
		if is_inside_tree():
			_request_rebuild()

## Configuration parameters for decorative barbs.
@export_category("Barbs")

## Linear distance along the curve between successive barb clusters.
@export var barb_spacing: float = 0.5:
	set(value):
		barb_spacing = maxf(0.1, value)
		if is_inside_tree():
			_request_rebuild()

## Scale dimension of individual barb spikes.
@export var barb_size: float = 0.08:
	set(value):
		barb_size = value
		if is_inside_tree():
			_request_rebuild()

## Tracks whether a deferred mesh rebuild is currently pending.
var _is_dirty: bool = false


## Lifecycle ready callback ensuring geometry exists without redundant rebuilds.
func _ready() -> void:
	print("ProceduralBarbwire: _ready() called.")
	if Engine.is_editor_hint() or get_child_count() == 0:
		_request_rebuild()


## Schedules a deferred rebuild to batch inspector property modifications.
func _request_rebuild() -> void:
	if not is_inside_tree():
		return

	if not _is_dirty:
		_is_dirty = true
		print("ProceduralBarbwire: Scheduling deferred rebuild.")
		call_deferred(&"_rebuild")


## Clears existing child nodes via [Utilities] and rebuilds procedural curve and meshes.
func _rebuild() -> void:
	_is_dirty = false
	print("ProceduralBarbwire: Rebuilding mesh structure via Utilities.")

	Utilities.clear_children(self)

	var curve: Curve3D = _generate_curve()
	_build_wire_mesh(curve)
	_build_barbs(curve)


## Calculates a straight or helical [Curve3D] based on configuration settings.
func _generate_curve() -> Curve3D:
	print("ProceduralBarbwire: Generating curve for wire type: ", wire_type)
	var curve: Curve3D = Curve3D.new()
	curve.bake_interval = 0.1

	if wire_type == ProceduralBarbwire.WireType.STRAIGHT:
		curve.add_point(Vector3(-length / 2.0, 0.0, 0.0))
		curve.add_point(Vector3(length / 2.0, 0.0, 0.0))
	else:
		var total_points: int = spring_coils * spring_resolution
		for i: int in range(total_points + 1):
			var t: float = float(i) / float(total_points)
			var current_length: float = -length / 2.0 + (t * length)
			var angle: float = t * float(spring_coils) * TAU
			var x: float = current_length
			var y: float = spring_radius * cos(angle)
			var z: float = spring_radius * sin(angle)

			curve.add_point(Vector3(x, y, z))

	return curve


## Sweeps circular profile along supplied guide curve into a static [ArrayMesh].
## [param curve] The guide curve to sweep the circular cross-section across.
func _build_wire_mesh(curve: Curve3D) -> void:
	print("ProceduralBarbwire: Building wire ArrayMesh sweep along curve.")
	var baked_len: float = curve.get_baked_length()
	if baked_len <= 0.001:
		return

	var steps: int = 1
	if wire_type == ProceduralBarbwire.WireType.SPRING:
		steps = maxi(2, ceili(baked_len / WIRE_STEP_METERS))

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var stride: int = WIRE_SIDES + 1
	for r: int in range(steps + 1):
		var offset: float = (float(r) / float(steps)) * baked_len
		var xform: Transform3D = curve.sample_baked_with_rotation(offset, true)
		for j: int in range(stride):
			var angle: float = (float(j) / float(WIRE_SIDES)) * TAU
			var dir: Vector3 = xform.basis.x * cos(angle) + xform.basis.y * sin(angle)
			verts.append(xform.origin + dir * wire_thickness)
			normals.append(dir.normalized())
			uvs.append(Vector2(offset, float(j) / float(WIRE_SIDES)))

	for r: int in range(steps):
		var row_a: int = r * stride
		var row_b: int = (r + 1) * stride
		for j: int in range(WIRE_SIDES):
			var a: int = row_a + j
			var b: int = row_a + j + 1
			var c: int = row_b + j
			var d: int = row_b + j + 1
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh: ArrayMesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var wire_mesh: MeshInstance3D = MeshInstance3D.new()
	wire_mesh.name = &"WireMesh"
	wire_mesh.mesh = arr_mesh
	add_child(wire_mesh)


## Instantiates star barb geometry along curve sampled intervals via [MultiMesh].
## [param curve] The baked curve from which transform matrices are sampled.
func _build_barbs(curve: Curve3D) -> void:
	print("ProceduralBarbwire: Building instanced MultiMesh barbs along curve.")
	var baked_length: float = curve.get_baked_length()
	var barb_count: int = floori(baked_length / barb_spacing)

	if barb_count <= 0:
		return

	var box_mesh_1: BoxMesh = BoxMesh.new()
	box_mesh_1.size = Vector3(barb_size * 2.0, wire_thickness * 1.5, wire_thickness * 1.5)

	var box_mesh_2: BoxMesh = BoxMesh.new()
	box_mesh_2.size = Vector3(wire_thickness * 1.5, barb_size * 2.0, wire_thickness * 1.5)

	var multi_mesh_1: MultiMesh = MultiMesh.new()
	multi_mesh_1.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh_1.instance_count = barb_count
	multi_mesh_1.mesh = box_mesh_1

	var multi_mesh_2: MultiMesh = MultiMesh.new()
	multi_mesh_2.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh_2.instance_count = barb_count
	multi_mesh_2.mesh = box_mesh_2

	for i: int in range(barb_count):
		var offset: float = float(i + 1) * barb_spacing
		var random_twist: float = offset * 13.0
		var barb_transform: Transform3D = curve.sample_baked_with_rotation(offset)
		barb_transform = barb_transform.rotated_local(Vector3.RIGHT, random_twist)

		multi_mesh_1.set_instance_transform(i, barb_transform)
		multi_mesh_2.set_instance_transform(i, barb_transform)

	var instance_1: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance_1.multimesh = multi_mesh_1
	add_child(instance_1)

	var instance_2: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance_2.multimesh = multi_mesh_2
	add_child(instance_2)
