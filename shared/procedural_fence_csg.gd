class_name ProceduralFence
extends CSGCombiner3D

enum Orientation { VERTICAL, HORIZONTAL, DIAGONAL }

## Property: Fence Width.
@export_category("Fence Dimensions")
@export var fence_width: float = 4.0:
	set(value):
		fence_width = value
		_request_rebuild()

## Property: Fence Height.
@export var fence_height: float = 2.0:
	set(value):
		fence_height = value
		_request_rebuild()

## Property: Fence Depth.
@export var fence_depth: float = 0.1:
	set(value):
		fence_depth = value
		_request_rebuild()

## Property: Has Border.
@export_category("Border")
@export var has_border: bool = true:
	set(value):
		has_border = value
		_request_rebuild()

## Property: Border Thickness.
@export var border_thickness: float = 0.2:
	set(value):
		border_thickness = value
		_request_rebuild()

## Defines the directional alignment of the inner fence bars (Vertical, Horizontal, or Diagonal).
@export_category("Bars")
@export var bar_orientation: ProceduralFence.Orientation = ProceduralFence.Orientation.DIAGONAL:
	set(value):
		bar_orientation = value
		_request_rebuild()

## Property: Bar Count.
@export var bar_count: int = 12:
	set(value):
		bar_count = value
		_request_rebuild()

## Property: Bar Thickness.
@export var bar_thickness: float = 0.05:
	set(value):
		bar_thickness = value
		_request_rebuild()

## Property: Diagonal Angle.
@export_range(10.0, 80.0) var diagonal_angle: float = 45.0:
	set(value):
		diagonal_angle = value
		_request_rebuild()

## Property: Is Dirty.
var _is_dirty: bool = false


func _init() -> void:
	print("ProceduralFence: _init() called, initializing collision.")
	use_collision = true


func _ready() -> void:
	_request_rebuild()


func _request_rebuild() -> void:
	if not _is_dirty:
		print("ProceduralFence: Rebuild requested and deferred.")
		_is_dirty = true
		call_deferred(&"_rebuild")


func _rebuild() -> void:
	print("ProceduralFence: Rebuilding geometry.")
	_is_dirty = false

	for child: Node in get_children():
		child.queue_free()

	var inner_width: float = fence_width
	var inner_height: float = fence_height

	if has_border:
		inner_width = maxf(0.01, fence_width - border_thickness * 2.0)
		inner_height = maxf(0.01, fence_height - border_thickness * 2.0)

	var bars_combiner: CSGCombiner3D = CSGCombiner3D.new()
	bars_combiner.operation = CSGShape3D.OPERATION_UNION
	add_child(bars_combiner)

	match bar_orientation:
		ProceduralFence.Orientation.VERTICAL:
			ProceduralFence._generate_angled_bars(
				bars_combiner, inner_width, inner_height, bar_count, bar_thickness, 0.0
			)
		ProceduralFence.Orientation.HORIZONTAL:
			ProceduralFence._generate_angled_bars(
				bars_combiner, inner_width, inner_height, bar_count, bar_thickness, 90.0
			)
		ProceduralFence.Orientation.DIAGONAL:
			var count_right: int = ceili(float(bar_count) / 2.0)
			var count_left: int = floori(float(bar_count) / 2.0)

			ProceduralFence._generate_angled_bars(
				bars_combiner, inner_width, inner_height, count_right, bar_thickness, diagonal_angle
			)
			ProceduralFence._generate_angled_bars(
				bars_combiner, inner_width, inner_height, count_left, bar_thickness, -diagonal_angle
			)

	# Intersection box to cleanly slice rotated corners
	var clipper: CSGBox3D = CSGBox3D.new()
	clipper.operation = CSGShape3D.OPERATION_INTERSECTION
	clipper.size = Vector3(inner_width, inner_height, fence_depth * 2.0)
	bars_combiner.add_child(clipper)

	if has_border:
		ProceduralFence._generate_border(
			self, fence_width, fence_height, fence_depth, border_thickness
		)


# --- STATIC FUNCTIONS ---


static func _generate_angled_bars(
	parent: Node3D, w: float, h: float, count: int, thickness: float, angle_deg: float
) -> void:
	print("ProceduralFence: Generating %d angled bars at %f degrees." % [count, angle_deg])
	if count <= 0:
		return

	var angle_rad: float = deg_to_rad(angle_deg)
	var cos_a: float = absf(cos(angle_rad))
	var sin_a: float = absf(sin(angle_rad))

	var grid_w: float = w * cos_a + h * sin_a
	var spacing: float = grid_w / float(count + 1)

	var dir_x: float = -sin(angle_rad)
	var dir_y: float = cos(angle_rad)
	var origin_dir_x: float = cos(angle_rad)
	var origin_dir_y: float = sin(angle_rad)

	for i: int in range(count):
		var local_x: float = -grid_w / 2.0 + spacing * float(i + 1)
		var origin_x: float = local_x * origin_dir_x
		var origin_y: float = local_x * origin_dir_y

		var t_vals: Array[float] = []

		if absf(dir_x) > 0.0001:
			t_vals.append((-w / 2.0 - origin_x) / dir_x)
			t_vals.append((w / 2.0 - origin_x) / dir_x)

		if absf(dir_y) > 0.0001:
			t_vals.append((-h / 2.0 - origin_y) / dir_y)
			t_vals.append((h / 2.0 - origin_y) / dir_y)

		var valid_t: Array[float] = []
		for t: float in t_vals:
			var px: float = origin_x + t * dir_x
			var py: float = origin_y + t * dir_y
			if (
				px >= -w / 2.0 - 0.001
				and px <= w / 2.0 + 0.001
				and py >= -h / 2.0 - 0.001
				and py <= h / 2.0 + 0.001
			):
				valid_t.append(t)

		if valid_t.size() >= 2:
			valid_t.sort()
			var t1: float = valid_t[0]
			var t2: float = valid_t[valid_t.size() - 1]

			var p1_x: float = origin_x + t1 * dir_x
			var p1_y: float = origin_y + t1 * dir_y
			var p2_x: float = origin_x + t2 * dir_x
			var p2_y: float = origin_y + t2 * dir_y

			var length: float = sqrt(pow(p2_x - p1_x, 2) + pow(p2_y - p1_y, 2))

			if length < 0.01:
				continue

			var center_x: float = (p1_x + p2_x) / 2.0
			var center_y: float = (p1_y + p2_y) / 2.0

			length += thickness * 1.5

			var bar: CSGBox3D = CSGBox3D.new()
			bar.size = Vector3(thickness, length, thickness)
			bar.position = Vector3(center_x, center_y, 0.0)
			bar.rotation_degrees = Vector3(0.0, 0.0, angle_deg)

			parent.add_child(bar)


static func _generate_border(
	parent: Node3D, f_width: float, f_height: float, f_depth: float, b_thickness: float
) -> void:
	print("ProceduralFence: Generating border constraints.")
	var lr_size: Vector3 = Vector3(b_thickness, f_height, f_depth)
	ProceduralFence._add_csg_box(
		parent, lr_size, Vector3(-f_width / 2.0 + b_thickness / 2.0, 0.0, 0.0)
	)
	ProceduralFence._add_csg_box(
		parent, lr_size, Vector3(f_width / 2.0 - b_thickness / 2.0, 0.0, 0.0)
	)

	var inner_w: float = maxf(0.01, f_width - b_thickness * 2.0)
	var tb_size: Vector3 = Vector3(inner_w, b_thickness, f_depth)

	ProceduralFence._add_csg_box(
		parent, tb_size, Vector3(0.0, f_height / 2.0 - b_thickness / 2.0, 0.0)
	)
	ProceduralFence._add_csg_box(
		parent, tb_size, Vector3(0.0, -f_height / 2.0 + b_thickness / 2.0, 0.0)
	)


static func _add_csg_box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var box: CSGBox3D = CSGBox3D.new()
	box.size = size
	box.position = pos
	parent.add_child(box)
