@tool
class_name ProceduralSpiralStairsCSG
extends CSGMesh3D

@export_category("Staircase Dimensions")
@export var outer_radius: float = 2.5:
	set(v):
		outer_radius = v
		_update_mesh()
@export var inner_radius: float = 0.5:
	set(v):
		inner_radius = v
		_update_mesh()
@export var total_height: float = 4.0:
	set(v):
		total_height = v
		_update_mesh()
@export var rotations: float = 1.0:
	set(v):
		rotations = v
		_update_mesh()

@export_category("Steps & Ramps")
@export var step_count: int = 30:
	set(v):
		step_count = v
		_update_mesh()
@export var step_thickness: float = 0.2:
	set(v):
		step_thickness = v
		_update_mesh()
@export var smooth_ramp: bool = false:
	set(v):
		smooth_ramp = v
		_update_mesh()
@export var smooth_underside: bool = true:
	set(v):
		smooth_underside = v
		_update_mesh()
@export var fill_to_floor: bool = false:
	set(v):
		fill_to_floor = v
		_update_mesh()


func _ready() -> void:
	_update_mesh()


func _update_mesh() -> void:
	if step_count <= 0:
		return

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var unit_angle: float = (rotations * TAU) / step_count
	var step_height: float = total_height / step_count

	# Build the vertices for each step or ramp segment
	for i: int in range(step_count):
		var current_angle: float = i * unit_angle
		var next_angle: float = (i + 1) * unit_angle

		var current_height: float = i * step_height
		var next_height: float = (i + 1) * step_height

		# If it's a ramp, the top slopes up. If not, the top is flat.
		var h_top_cur: float = current_height if smooth_ramp else next_height
		var h_top_next: float = next_height

		var h_bot_cur: float = 0.0
		var h_bot_next: float = 0.0

		if not fill_to_floor:
			# If smooth_ramp is true, we force a smooth underside to prevent bad geometry
			if smooth_underside or smooth_ramp:
				h_bot_cur = current_height - step_thickness
				h_bot_next = next_height - step_thickness
			else:
				# Blocky, standard steps underneath
				h_bot_cur = next_height - step_thickness
				h_bot_next = next_height - step_thickness

		# Calculate 3D points
		var point_a: Vector3 = Vector3(
			cos(current_angle) * inner_radius, h_top_cur, sin(current_angle) * inner_radius
		)
		var point_b: Vector3 = Vector3(
			cos(current_angle) * outer_radius, h_top_cur, sin(current_angle) * outer_radius
		)
		var point_c: Vector3 = Vector3(
			cos(next_angle) * outer_radius, h_top_next, sin(next_angle) * outer_radius
		)
		var point_d: Vector3 = Vector3(
			cos(next_angle) * inner_radius, h_top_next, sin(next_angle) * inner_radius
		)

		var point_e: Vector3 = Vector3(point_a.x, h_bot_cur, point_a.z)
		var point_f: Vector3 = Vector3(point_b.x, h_bot_cur, point_b.z)
		var point_g: Vector3 = Vector3(point_c.x, h_bot_next, point_c.z)
		var point_h: Vector3 = Vector3(point_d.x, h_bot_next, point_d.z)

		# Core Faces (Top, Bottom, Inner, Outer)
		_add_quad(st, point_a, point_b, point_c, point_d)  # Top
		_add_quad(st, point_h, point_g, point_f, point_e)  # Bottom
		_add_quad(st, point_b, point_f, point_g, point_c)  # Outer Edge
		_add_quad(st, point_a, point_d, point_h, point_e)  # Inner Edge

		# Risers and Caps
		if smooth_ramp:
			# For a continuous ramp, we only need to cap the very start and very end
			if i == 0:
				_add_quad(st, point_e, point_f, point_b, point_a)  # Front cap
			if i == step_count - 1:
				_add_quad(st, point_d, point_c, point_g, point_h)  # Back cap
		else:
			# Standard stairs need every vertical riser closed
			_add_quad(st, point_e, point_f, point_b, point_a)  # Front
			_add_quad(st, point_d, point_c, point_g, point_h)  # Back

	# Finalize mesh and apply to the CSG node
	st.generate_normals()
	self.mesh = st.commit()


# Helper function to generate two triangles per quad face
func _add_quad(st: SurfaceTool, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) -> void:
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p3)

	st.add_vertex(p1)
	st.add_vertex(p3)
	st.add_vertex(p4)
