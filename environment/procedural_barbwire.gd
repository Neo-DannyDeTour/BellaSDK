@tool
class_name ProceduralBarbwire
extends Node3D

enum WireType { STRAIGHT, SPRING }

@export_category("Wire Shape")
@export var wire_type: WireType = WireType.STRAIGHT:
	set(value):
		wire_type = value
		_request_rebuild()

@export var length: float = 10.0:
	set(value):
		length = value
		_request_rebuild()

@export var wire_thickness: float = 0.02:
	set(value):
		wire_thickness = value
		_request_rebuild()

@export_category("Spring Settings")
@export var spring_radius: float = 0.3:
	set(value):
		spring_radius = value
		_request_rebuild()

@export var spring_coils: int = 12:
	set(value):
		spring_coils = value
		_request_rebuild()

@export var spring_resolution: int = 64:
	set(value):
		spring_resolution = max(4, value)
		_request_rebuild()

@export_category("Barbs")
@export var barb_spacing: float = 0.5:
	set(value):
		barb_spacing = max(0.1, value)
		_request_rebuild()

@export var barb_size: float = 0.08:
	set(value):
		barb_size = value
		_request_rebuild()

var _is_dirty: bool = false


func _ready() -> void:
	_request_rebuild()


func _request_rebuild() -> void:
	if not _is_dirty:
		_is_dirty = true
		call_deferred(&"_rebuild")


func _rebuild() -> void:
	_is_dirty = false

	# Trace action for runtime debugging
	print("ProceduralBarbwire: Rebuilding mesh structure.")

	for child: Node in get_children():
		child.queue_free()

	var curve: Curve3D = _generate_curve()
	_build_wire_mesh(curve)
	_build_barbs(curve)


func _generate_curve() -> Curve3D:
	var curve: Curve3D = Curve3D.new()
	curve.bake_interval = 0.1

	if wire_type == WireType.STRAIGHT:
		curve.add_point(Vector3(-length / 2.0, 0.0, 0.0))
		curve.add_point(Vector3(length / 2.0, 0.0, 0.0))
	else:
		var total_points: int = spring_coils * spring_resolution
		for i: int in range(total_points + 1):
			var t: float = float(i) / float(total_points)
			var current_length: float = -length / 2.0 + (t * length)

			# Parametric equation for a helix
			var angle: float = t * float(spring_coils) * TAU
			var x: float = current_length
			var y: float = spring_radius * cos(angle)
			var z: float = spring_radius * sin(angle)

			curve.add_point(Vector3(x, y, z))

	return curve


func _build_wire_mesh(curve: Curve3D) -> void:
	print("ProceduralBarbwire: Building wire mesh sweep along curve.")

	var path: Path3D = Path3D.new()
	path.curve = curve
	add_child(path)

	var polygon: CSGPolygon3D = CSGPolygon3D.new()
	polygon.mode = CSGPolygon3D.MODE_PATH

	add_child(polygon)

	polygon.path_node = polygon.get_path_to(path)

	# CRITICAL FIX 1: Prevent double-transform offset when moved in the editor
	polygon.path_local = true

	polygon.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	polygon.path_interval = 0.1

	# CRITICAL FIX 2: Better rotation mode for 3D springs to prevent flat "pinching"
	polygon.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW
	polygon.smooth_faces = true

	var profile: PackedVector2Array = []
	var points: int = 8
	for i: int in range(points):
		var angle: float = (float(i) / float(points)) * TAU
		profile.append(Vector2(cos(angle), sin(angle)) * wire_thickness)

	polygon.polygon = profile


func _build_barbs(curve: Curve3D) -> void:
	var baked_length: float = curve.get_baked_length()
	var barb_count: int = floori(baked_length / barb_spacing)

	if barb_count <= 0:
		return

	# Create the visual representation of a "Star" barb (two crossed boxes)
	var box_mesh_1: BoxMesh = BoxMesh.new()
	box_mesh_1.size = Vector3(barb_size * 2.0, wire_thickness * 1.5, wire_thickness * 1.5)

	var box_mesh_2: BoxMesh = BoxMesh.new()
	box_mesh_2.size = Vector3(wire_thickness * 1.5, barb_size * 2.0, wire_thickness * 1.5)

	# Use MultiMesh to batch all barbs into single draw calls
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

		# Stagger the rotation slightly so the barbs look chaotic
		var random_twist: float = offset * 13.0

		# FIX: Renamed 'transform' to 'barb_transform' to prevent shadowing Node3D.transform
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
