@tool
extends CSGPolygon3D
class_name ProceduralStairsCSG

@export_category("Stair Dimensions")
@export_range(1, 100) var step_count: int = 10:
	set(value):
		step_count = value
		if is_inside_tree():
			_update_stairs()

@export var total_height: float = 2.0:
	set(value):
		total_height = max(0.1, value)
		if is_inside_tree():
			_update_stairs()

@export var total_length: float = 3.0:
	set(value):
		total_length = max(0.1, value)
		if is_inside_tree():
			_update_stairs()

@export var stair_width: float = 1.5:
	set(value):
		stair_width = max(0.1, value)
		depth = stair_width
		if is_inside_tree():
			_update_stairs()

# --- THE NEW LANDING SETTINGS ---
@export_category("EQ Landings")
@export var landing_step_indices: Array[int] = []:
	set(value):
		landing_step_indices = value
		if is_inside_tree():
			_update_stairs()

@export var landing_extra_length: float = 1.0:
	set(value):
		landing_extra_length = max(0.0, value)
		if is_inside_tree():
			_update_stairs()

@export var top_landing_length: float = 1.5:
	set(value):
		top_landing_length = max(0.0, value)
		if is_inside_tree():
			_update_stairs()

@export_category("Stair Style")
@export var fill_to_floor: bool = true:
	set(value):
		fill_to_floor = value
		if is_inside_tree():
			_update_stairs()

@export var step_thickness: float = 0.2:
	set(value):
		step_thickness = max(0.01, value)
		if is_inside_tree():
			_update_stairs()

@export_category("Physics")
@export var generate_smooth_ramp: bool = true:
	set(value):
		generate_smooth_ramp = value
		if is_inside_tree():
			_update_stairs()

var ramp_body: StaticBody3D
var ramp_collision: CollisionPolygon3D


func _ready() -> void:
	mode = CSGPolygon3D.MODE_DEPTH
	depth = stair_width
	_update_stairs()


func _update_stairs() -> void:
	if step_count < 1:
		return

	var step_h: float = total_length / step_count
	var step_v: float = total_height / step_count

	var points := PackedVector2Array()
	var ramp_points := PackedVector2Array()

	points.append(Vector2(0, 0))
	ramp_points.append(Vector2(0, 0))

	var cx := 0.0
	var cy := 0.0

	# Generate both the visual stairs AND the physics ramp simultaneously
	for i in range(step_count):
		var extra := 0.0

		# Check if this specific step is marked as an EQ landing
		if i in landing_step_indices:
			extra += landing_extra_length

		# Check if it is the very last step (Top Landing)
		if i == step_count - 1:
			extra += top_landing_length

		# 1. VISUAL: Draw Riser (Up)
		cy += step_v
		points.append(Vector2(cx, cy))

		# 2. VISUAL: Draw Tread + Extra EQ length (Forward)
		cx += step_h + extra
		points.append(Vector2(cx, cy))

		# 3. PHYSICS: Draw Slope up to the standard edge
		ramp_points.append(Vector2(cx - extra, cy))

		# 4. PHYSICS: If it's a landing, draw a flat section across it
		if extra > 0:
			ramp_points.append(Vector2(cx, cy))

	# Close the bottom profiles
	if fill_to_floor:
		points.append(Vector2(cx, 0))
		ramp_points.append(Vector2(cx, 0))
	else:
		points.append(Vector2(cx, cy - step_thickness))
		points.append(Vector2(0, -step_thickness))

		ramp_points.append(Vector2(cx, cy - step_thickness))
		ramp_points.append(Vector2(0, -step_thickness))

	polygon = points
	_build_collision_ramp(ramp_points)


func _build_collision_ramp(ramp_points: PackedVector2Array) -> void:
	if not generate_smooth_ramp:
		use_collision = true
		if ramp_body and is_instance_valid(ramp_body):
			ramp_body.queue_free()
			ramp_body = null
		return

	use_collision = false

	if not ramp_body or not is_instance_valid(ramp_body):
		ramp_body = get_node_or_null("PhysicsRampBody") as StaticBody3D
		if not ramp_body:
			ramp_body = StaticBody3D.new()
			ramp_body.name = "PhysicsRampBody"
			add_child(ramp_body)

	ramp_body.collision_layer = self.collision_layer
	ramp_body.collision_mask = self.collision_mask

	if not ramp_collision or not is_instance_valid(ramp_collision):
		ramp_collision = ramp_body.get_node_or_null("RampCollision") as CollisionPolygon3D
		if not ramp_collision:
			ramp_collision = CollisionPolygon3D.new()
			ramp_collision.name = "RampCollision"
			ramp_body.add_child(ramp_collision)

	ramp_collision.depth = stair_width
	ramp_collision.position.z = -stair_width / 2.0

	# Feed the synced math directly into the collision shape!
	ramp_collision.polygon = ramp_points
