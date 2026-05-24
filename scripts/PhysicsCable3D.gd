@tool  # This tells Godot to run the script inside the editor!
class_name PhysicsCable3D
extends Node3D

@export_category("Cable Connections")
@export var start_anchor: Node3D
@export var end_plug: RigidBody3D

@export_category("Physics Properties")
@export var link_scene: PackedScene
@export var cable_length_meters: float = 3.0
@export var link_spacing: float = 0.2

@export_category("Appearance")
@export var cable_color: Color = Color(0.1, 0.1, 0.1)
@export var thickness: float = 0.04

# We cache the materials statically so 100 identical cables only use 1 material in memory!
static var _material_cache: Dictionary = {}

var _links: Array[RigidBody3D] = []
var _visual_segments: Array[MeshInstance3D] = []
var _base_mesh: CylinderMesh


func _ready() -> void:
	# 1. Create a perfectly smooth base cylinder
	_base_mesh = CylinderMesh.new()
	_base_mesh.top_radius = thickness
	_base_mesh.bottom_radius = thickness
	_base_mesh.height = 1.0  # We stretch this dynamically in _process
	_base_mesh.radial_segments = 8
	_base_mesh.rings = 1

	# Apply statically cached material for extreme performance
	if not _material_cache.has(cable_color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cable_color
		mat.roughness = 0.8
		_material_cache[cable_color] = mat
	_base_mesh.material = _material_cache[cable_color]

	# 2. ONLY generate physics if we are actually playing the game
	if not Engine.is_editor_hint():
		call_deferred("_generate_physics_chain")

		# Call a new function to build the visual mesh segments AFTER physics generate
		call_deferred("_generate_visual_segments")


func _generate_visual_segments() -> void:
	# Create one mesh segment for every gap between links
	var total_points: int = _links.size() + 1
	for i in range(total_points):
		var segment := MeshInstance3D.new()
		segment.mesh = _base_mesh
		# top_level decouples the mesh from the parent's rotation/position
		segment.top_level = true
		add_child(segment)
		_visual_segments.append(segment)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _links.is_empty() or _visual_segments.is_empty():
		return

	if not is_instance_valid(start_anchor) or not is_instance_valid(end_plug):
		return

	# 1. Gather all current global positions in order
	var points: Array[Vector3] = []
	points.append(start_anchor.global_position)
	for link in _links:
		if is_instance_valid(link):
			points.append(link.global_position)
	points.append(end_plug.global_position)

	# 2. Stretch and aim the cylinders between every point
	for i in range(points.size() - 1):
		var p1 := points[i]
		var p2 := points[i + 1]
		var dist := p1.distance_to(p2)

		var segment := _visual_segments[i]
		segment.global_position = p1.lerp(p2, 0.5)  # Move to the exact middle

		var dir := p2 - p1
		if dir.length() > 0.001:
			# Safely look_at the next point (avoids Godot's Vector3.UP straight-down error)
			var up := Vector3.UP if abs(dir.normalized().y) < 0.99 else Vector3.RIGHT
			segment.look_at(p2, up)

			# A Godot Cylinder stands UP on the Y axis, so we rotate it to aim forward (-Z)
			segment.rotate_object_local(Vector3.RIGHT, PI / 2.0)

		# Scale the cylinder's Y height to bridge the gap perfectly
		segment.scale = Vector3(1.0, dist, 1.0)


func _generate_physics_chain() -> void:
	if not link_scene:
		printerr("CABLE ERROR: You forgot to assign the link_scene in the inspector!")
		return

	if not is_instance_valid(start_anchor) or not is_instance_valid(end_plug):
		return

	var total_links: int = int(cable_length_meters / link_spacing)

	# --- NEW: Link both plugs together bi-directionally! ---
	if end_plug is TetheredPlug:
		end_plug.max_cable_length = cable_length_meters
		end_plug.anchor_point = start_anchor

		# If the start anchor is ALSO a plug, introduce them to each other
		if start_anchor is TetheredPlug:
			end_plug.partner_plug = start_anchor

	if start_anchor is TetheredPlug:
		start_anchor.max_cable_length = cable_length_meters
		start_anchor.anchor_point = end_plug
		start_anchor.partner_plug = end_plug
	# -------------------------------------------------------

	var start_pos := start_anchor.global_position
	var end_pos := end_plug.global_position
	var previous_body: Node3D = start_anchor

	var straight_dist := start_pos.distance_to(end_pos)
	var droop_amount: float = maxf(0.0, cable_length_meters - straight_dist) * 0.5

	for i in range(total_links):
		var link := link_scene.instantiate() as RigidBody3D
		add_child(link)

		for prev in _links:
			link.add_collision_exception_with(prev)
		if start_anchor is PhysicsBody3D:
			link.add_collision_exception_with(start_anchor)

		var fraction := float(i + 1) / float(total_links + 1)
		var drop_offset: Vector3 = Vector3.DOWN * (4.0 * droop_amount * fraction * (1.0 - fraction))
		link.global_position = start_pos.lerp(end_pos, fraction) + drop_offset

		if not link.global_position.is_equal_approx(previous_body.global_position):
			link.look_at(previous_body.global_position)

		_links.append(link)

		var joint := PinJoint3D.new()
		add_child(joint)
		joint.global_position = previous_body.global_position.lerp(link.global_position, 0.5)

		# Only assign node_a if it's an actual Physics Body
		if previous_body is PhysicsBody3D:
			joint.node_a = joint.get_path_to(previous_body)
		# If it's a Marker3D, we do nothing to node_a!
		# Godot will pin it directly to the world at joint.global_position.

		joint.node_b = joint.get_path_to(link)

		previous_body = link

	var final_joint := PinJoint3D.new()
	add_child(final_joint)
	final_joint.global_position = previous_body.global_position.lerp(end_pos, 0.5)
	final_joint.node_a = final_joint.get_path_to(previous_body)
	final_joint.node_b = final_joint.get_path_to(end_plug)

	if end_plug is CollisionObject3D:
		for prev in _links:
			end_plug.add_collision_exception_with(prev)

#func _build_circular_profile(t: float) -> PackedVector2Array:
#var circle_points := PackedVector2Array()
#for i in range(8):
#var angle := (i / 8.0) * TAU
#circle_points.append(Vector2(cos(angle), sin(angle)) * t)
#return circle_points
