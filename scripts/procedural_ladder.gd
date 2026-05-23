@tool
class_name ProceduralLadder
extends CSGCombiner3D

enum LadderType { METAL, WOOD, CONCRETE }

@export_category("Ladder Style")
@export var type: LadderType = LadderType.METAL:
	set(value):
		type = value
		_request_rebuild()

@export_category("Ladder Dimensions")
@export var ladder_height: float = 5.0:
	set(value):
		ladder_height = max(1.0, value)
		_request_rebuild()

@export var ladder_width: float = 1.0:
	set(value):
		ladder_width = max(0.5, value)
		_request_rebuild()

@export var rung_spacing: float = 0.4:
	set(value):
		rung_spacing = max(0.15, value)
		_request_rebuild()

@export var rung_thickness: float = 0.03:
	set(value):
		rung_thickness = max(0.01, value)
		_request_rebuild()

var _is_dirty: bool = false


func _init() -> void:
	use_collision = true


func _ready() -> void:
	_request_rebuild()


func _request_rebuild() -> void:
	if not _is_dirty:
		_is_dirty = true
		call_deferred(&"_rebuild")


func _rebuild() -> void:
	_is_dirty = false

	for child: Node in get_children():
		child.queue_free()

	var rung_count: int = floori(ladder_height / rung_spacing)
	var start_y: float = -(ladder_height / 2.0) + (rung_spacing / 2.0)

	match type:
		LadderType.METAL:
			_build_metal(rung_count, start_y)
		LadderType.WOOD:
			_build_wood(rung_count, start_y)
		LadderType.CONCRETE:
			_build_concrete(rung_count, start_y)


func _build_metal(rung_count: int, start_y: float) -> void:
	var left_rail: CSGCylinder3D = CSGCylinder3D.new()
	left_rail.radius = rung_thickness * 1.2
	left_rail.height = ladder_height
	left_rail.position = Vector3(-ladder_width / 2.0, 0.0, 0.0)
	add_child(left_rail)

	var right_rail: CSGCylinder3D = CSGCylinder3D.new()
	right_rail.radius = rung_thickness * 1.2
	right_rail.height = ladder_height
	right_rail.position = Vector3(ladder_width / 2.0, 0.0, 0.0)
	add_child(right_rail)

	for i: int in range(rung_count):
		var rung: CSGCylinder3D = CSGCylinder3D.new()
		rung.radius = rung_thickness
		rung.height = ladder_width
		rung.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		rung.position = Vector3(0.0, start_y + float(i) * rung_spacing, 0.0)
		add_child(rung)


func _build_wood(rung_count: int, start_y: float) -> void:
	# Rails maintain a standard shape but scale up slightly only if rungs get very thick
	var rail_width: float = max(0.08, rung_thickness + 0.04)
	var rail_depth: float = max(0.04, rung_thickness + 0.01)

	var left_rail: CSGBox3D = CSGBox3D.new()
	left_rail.size = Vector3(rail_width, ladder_height, rail_depth)
	left_rail.position = Vector3(-ladder_width / 2.0, 0.0, 0.0)
	left_rail.rotation_degrees = Vector3(0.0, 0.0, 1.5)
	add_child(left_rail)

	var right_rail: CSGBox3D = CSGBox3D.new()
	right_rail.size = Vector3(rail_width, ladder_height, rail_depth)
	right_rail.position = Vector3(ladder_width / 2.0, 0.0, 0.0)
	right_rail.rotation_degrees = Vector3(0.0, 0.0, -1.0)
	add_child(right_rail)

	for i: int in range(rung_count):
		var rung: CSGBox3D = CSGBox3D.new()

		# Rung thickness directly and independently drives the step dimensions
		rung.size = Vector3(ladder_width + 0.1, rung_thickness, rung_thickness)

		# Increased pseudo-random positional wobble (now 0.06)
		var x_wobble: float = cos(float(i) * 8.4) * 0.06  # Increased left/right slip
		var y_wobble: float = sin(float(i) * 13.7) * 0.06  # Increased up/down spacing errors
		var z_wobble: float = sin(float(i) * 19.1) * 0.04  # Increased forward/back slip

		var x_rot: float = cos(float(i) * 11.1) * 2.5
		var y_rot: float = sin(float(i) * 5.5) * 2.0
		var z_rot: float = sin(float(i) * 7.3) * 3.0

		rung.rotation_degrees = Vector3(x_rot, y_rot, z_rot)
		rung.position = Vector3(x_wobble, start_y + float(i) * rung_spacing + y_wobble, z_wobble)
		add_child(rung)


func _build_concrete(rung_count: int, start_y: float) -> void:
	var depth: float = 0.15

	for i: int in range(rung_count):
		var y_pos: float = start_y + float(i) * rung_spacing

		var front_bar: CSGCylinder3D = CSGCylinder3D.new()
		front_bar.radius = rung_thickness
		front_bar.height = ladder_width
		front_bar.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		front_bar.position = Vector3(0.0, y_pos, depth)
		add_child(front_bar)

		var left_leg: CSGCylinder3D = CSGCylinder3D.new()
		left_leg.radius = rung_thickness
		left_leg.height = depth
		left_leg.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		left_leg.position = Vector3(-ladder_width / 2.0 + rung_thickness, y_pos, depth / 2.0)
		add_child(left_leg)

		var right_leg: CSGCylinder3D = CSGCylinder3D.new()
		right_leg.radius = rung_thickness
		right_leg.height = depth
		right_leg.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		right_leg.position = Vector3(ladder_width / 2.0 - rung_thickness, y_pos, depth / 2.0)
		add_child(right_leg)
