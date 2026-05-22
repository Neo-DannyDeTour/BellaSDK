@tool
extends MeshInstance3D
class_name SeamlessCable3D

@export_category("Cable Connections")
## Add as many Marker3Ds, CablePoint3Ds, or nodes here as you want. Order matters!
@export var anchors: Array[Node3D]

@export_category("Default Shape")
## Used if the anchor in the array is NOT a custom CablePoint3D
@export var default_droop: float = 2.0
@export var default_segments: int = 10

@export_category("Appearance")
@export var cable_material: ShaderMaterial
@export var thickness: float = 0.04
@export var radial_segments: int = 6

# Cached statically so 100 cables still only use 1 fallback material in memory
static var _fallback_material: StandardMaterial3D

# Stores the snapshot of the cable's last known state to prevent editor freezing
var _last_state_hash: int = 0

func _ready() -> void:
	_update_cable_positions()
	
	# Turn off processing during gameplay — it only runs in the editor!
	if not Engine.is_editor_hint():
		set_process(false)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_cable_positions()

func _update_cable_positions() -> void:
	var valid_anchors: Array[Node3D] = []
	for anchor: Node3D in anchors:
		if is_instance_valid(anchor):
			valid_anchors.append(anchor)

	var span_count: int = valid_anchors.size() - 1
	if span_count < 1:
		mesh = null
		_last_state_hash = 0
		return

	# --- Hash Checking for Editor Performance ---
	var current_state: Array = []
	for anchor: Node3D in valid_anchors:
		current_state.append(anchor.global_position)
		if "droop" in anchor:
			current_state.append(float(anchor.get("droop")))
		if "segments" in anchor:
			current_state.append(int(anchor.get("segments")))
	
	var current_hash: int = current_state.hash()
	
	# If nothing moved or changed, abort the heavy geometry math
	if current_hash == _last_state_hash and mesh != null:
		return
		
	_last_state_hash = current_hash
	# --------------------------------------------

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var vertex_count: int = 0
	var cable_phase: float = float(get_instance_id() % 1000) / 1000.0 * TAU

	for span_index: int in range(span_count):
		var start_node: Node3D = valid_anchors[span_index]
		var end_node: Node3D = valid_anchors[span_index + 1]
		
		# Duck-typing: grab custom droop/segments if available, else fallback
		var span_droop: float = float(start_node.get("droop")) if "droop" in start_node else default_droop
		var span_segments: int = int(start_node.get("segments")) if "segments" in start_node else default_segments
		span_segments = max(1, span_segments)

		var start_pos: Vector3 = start_node.global_position
		var end_pos: Vector3 = end_node.global_position
		var mid_pos: Vector3 = start_pos.lerp(end_pos, 0.5)
		var control_pos: Vector3 = mid_pos + (Vector3.DOWN * span_droop * 2.0)

		var points: Array[Vector3] = []
		for i: int in range(span_segments + 1):
			var t: float = float(i) / float(span_segments)
			points.append(_get_bezier_point(start_pos, control_pos, end_pos, t))

		# Generate the 3D Tube Geometry
		for i: int in range(points.size()):
			var p: Vector3 = points[i]
			var t_progression: float = float(i) / float(span_segments)
			
			var forward: Vector3 = Vector3.FORWARD
			if i < points.size() - 1:
				forward = (points[i+1] - p).normalized()
			elif i > 0:
				forward = (p - points[i-1]).normalized()
				
			var up: Vector3 = Vector3.UP
			if abs(forward.y) > 0.99:
				up = Vector3.RIGHT
			var right: Vector3 = up.cross(forward).normalized()
			up = forward.cross(right).normalized()
			
			var t_matrix: Transform3D = Transform3D(Basis(right, up, forward), p)
			t_matrix = global_transform.affine_inverse() * t_matrix 

			for j: int in range(radial_segments + 1):
				var angle: float = (float(j) / float(radial_segments)) * TAU
				var local_circle: Vector3 = Vector3(cos(angle) * thickness, sin(angle) * thickness, 0.0)
				
				var normal: Vector3 = (t_matrix.basis * local_circle).normalized()
				var vertex: Vector3 = t_matrix * local_circle
				
				st.set_normal(normal)
				st.set_uv(Vector2(float(j) / float(radial_segments), t_progression))
				
				# Send data to wind shader: R = Curve %, B = Random Sync Phase
				st.set_color(Color(t_progression, 0.0, cable_phase, 1.0))
				st.add_vertex(vertex)

		# Stitch the vertices together with Triangles
		var verts_per_ring: int = radial_segments + 1
		for i: int in range(span_segments):
			for j: int in range(radial_segments):
				var ring_start: int = vertex_count + (i * verts_per_ring)
				var current: int = ring_start + j
				var next_vert: int = current + 1
				var top: int = current + verts_per_ring
				var top_next: int = top + 1

				st.add_index(current)
				st.add_index(next_vert)
				st.add_index(top)
				
				st.add_index(next_vert)
				st.add_index(top_next)
				st.add_index(top)
		
		vertex_count += points.size() * verts_per_ring

	st.generate_tangents()
	mesh = st.commit()
	
	# Apply materials
	if cable_material != null:
		material_override = cable_material
	else:
		if _fallback_material == null:
			_fallback_material = StandardMaterial3D.new()
			_fallback_material.albedo_color = Color(0.1, 0.1, 0.1)
			_fallback_material.roughness = 0.8
		material_override = _fallback_material

func _get_bezier_point(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var q0: Vector3 = p0.lerp(p1, t)
	var q1: Vector3 = p1.lerp(p2, t)
	return q0.lerp(q1, t)
