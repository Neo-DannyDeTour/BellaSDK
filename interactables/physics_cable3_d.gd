@tool
## Generates a physics-driven catenary cable with dynamic [PinJoint3D] chains and visual meshes.
##
## Connects two endpoints using a segmented chain of [RigidBody3D] links, updating
## orientational transforms of visual cylinder segments to match physics bodies at runtime.
class_name PhysicsCable3D
extends Node3D

## Configuration references for attachment endpoints.
@export_category("Cable Connections")
## Starting anchor [Node3D] point for the cable.
@export var start_anchor: Node3D

## Ending plug [RigidBody3D] point where the cable terminates.
@export var end_plug: RigidBody3D

## Physics simulation properties.
@export_category("Physics Properties")
## The [PackedScene] template instantiated for each rigid link in the physics chain.
@export var link_scene: PackedScene = preload("res://interactables/cable_link.tscn")

## Total physical length of the cable in meters.
@export var cable_length_meters: float = 3.0

## Distance spacing between consecutive physics link nodes.
@export var link_spacing: float = 0.2

## Visual styling options.
@export_category("Appearance")
## Base tint color applied to cable mesh segments.
@export var cable_color: Color = Color(0.1, 0.1, 0.1)

## Radial thickness of the visual cable cylinders.
@export var thickness: float = 0.04

## In-editor debug tools.
@export_category("Debug")
## Toggles visibility of the editor distance reach sphere visualizer.
@export var show_debug_sphere: bool = true:
	set(value):
		show_debug_sphere = value
		if is_instance_valid(_debug_sphere):
			_debug_sphere.visible = show_debug_sphere
			print("PhysicsCable3D: show_debug_sphere toggled to ", show_debug_sphere)

## Editor-only placeholder icon node.
@onready var _editor_icon: Node3D = get_node_or_null("%EditorIcon") as Node3D

## Shared material cache keyed by [Color] to prevent duplicate shader pipeline states.
static var _material_cache: Dictionary[Color, StandardMaterial3D] = {}

## Collection of instantiated physics link bodies.
var _links: Array[RigidBody3D] = []

## Collection of visual cylinder mesh instances bridging the links.
var _visual_segments: Array[MeshInstance3D] = []

## Shared cylinder mesh resource used by all visual segment instances.
var _base_mesh: CylinderMesh

## Editor visualizer mesh indicating maximum cable extension range.
var _debug_sphere: MeshInstance3D

## Cached position of the start anchor from the previous frame.
var _last_start_pos: Vector3 = Vector3.ZERO

## Cached position of the end plug from the previous frame.
var _last_end_pos: Vector3 = Vector3.ZERO


## Initializes runtime physics chains or editor debug spheres based on context.
func _ready() -> void:
	print("PhysicsCable3D: _ready() called.")
	if not Engine.is_editor_hint():
		if is_instance_valid(_editor_icon):
			_editor_icon.queue_free()

		_create_base_mesh()
		_setup_cable_system()
	else:
		_setup_debug_sphere()


## Updates visual segment transforms or editor debug sphere positions each frame.
## [param _delta] Frame time elapsed in seconds.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_debug_sphere_transform()
		return

	if _links.is_empty() or _visual_segments.is_empty():
		return

	if not is_instance_valid(start_anchor) or not is_instance_valid(end_plug):
		return

	var start_pos: Vector3 = start_anchor.global_position
	var end_pos: Vector3 = end_plug.global_position

	var needs_update: bool = false
	if not start_pos.is_equal_approx(_last_start_pos) or not end_pos.is_equal_approx(_last_end_pos):
		needs_update = true
	else:
		for link: RigidBody3D in _links:
			if is_instance_valid(link) and not link.is_sleeping():
				needs_update = true
				break

	if not needs_update:
		return

	_last_start_pos = start_pos
	_last_end_pos = end_pos

	var p1: Vector3 = start_pos
	var segment_index: int = 0

	for link: RigidBody3D in _links:
		if not is_instance_valid(link):
			continue
		var p2: Vector3 = link.global_position
		_update_visual_segment(_visual_segments[segment_index], p1, p2)
		p1 = p2
		segment_index += 1

	if segment_index < _visual_segments.size():
		_update_visual_segment(_visual_segments[segment_index], p1, end_pos)


## Generates shared cylinder mesh and caches material resources by color.
func _create_base_mesh() -> void:
	print("PhysicsCable3D: Generating base mesh for visual segments.")
	_base_mesh = CylinderMesh.new()
	_base_mesh.top_radius = thickness
	_base_mesh.bottom_radius = thickness
	_base_mesh.height = 1.0
	_base_mesh.radial_segments = 8
	_base_mesh.rings = 1

	if not _material_cache.has(cable_color):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = cable_color
		mat.roughness = 0.8
		_material_cache[cable_color] = mat

	_base_mesh.material = _material_cache[cable_color]


## Combines physics chain generation and visual segment creation in a single immediate pass.
func _setup_cable_system() -> void:
	_generate_physics_chain()
	_generate_visual_segments()


## Instantiates editor range sphere visualizer.
func _setup_debug_sphere() -> void:
	print("PhysicsCable3D: Setting up editor debug sphere.")
	for child: Node in get_children():
		if child.name == "DebugSphereMesh":
			child.queue_free()

	_debug_sphere = MeshInstance3D.new()
	_debug_sphere.name = "DebugSphereMesh"

	var sphere_mesh: SphereMesh = SphereMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.7, 0.0, 0.15)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	sphere_mesh.material = mat
	_debug_sphere.mesh = sphere_mesh
	_debug_sphere.top_level = true
	_debug_sphere.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_debug_sphere.visible = show_debug_sphere

	add_child(_debug_sphere)


## Updates orientation and scale of a visual cylinder segment spanning two points.
## [param segment] The target [MeshInstance3D] to position and stretch.
## [param p1] Starting 3D position.
## [param p2] Ending 3D position.
func _update_visual_segment(segment: MeshInstance3D, p1: Vector3, p2: Vector3) -> void:
	var dist: float = p1.distance_to(p2)
	segment.global_position = p1.lerp(p2, 0.5)

	var dir: Vector3 = p2 - p1
	if dir.length_squared() > 0.000001:
		var up: Vector3 = Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
		segment.look_at(p2, up)
		segment.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	segment.scale = Vector3(1.0, dist, 1.0)


## Keeps the debug sphere anchored to the start position and scaled to cable reach.
func _update_debug_sphere_transform() -> void:
	if show_debug_sphere and is_instance_valid(_debug_sphere) and is_instance_valid(start_anchor):
		_debug_sphere.global_position = start_anchor.global_position
		var diameter: float = cable_length_meters * 2.0
		_debug_sphere.scale = Vector3(diameter, diameter, diameter)


## Instantiates visual segment meshes corresponding to gaps between physics links.
func _generate_visual_segments() -> void:
	print("PhysicsCable3D: Spawning visual cylinder segments.")
	var total_points: int = _links.size() + 1

	for i: int in range(total_points):
		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.mesh = _base_mesh
		segment.top_level = true
		add_child(segment)
		_visual_segments.append(segment)


## Builds the dynamic physics chain using instantiated link scenes and pin joints.
func _generate_physics_chain() -> void:
	print("PhysicsCable3D: _generate_physics_chain() generating bi-directional cable.")

	if not link_scene:
		push_error("PhysicsCable3D: link_scene is not assigned in the inspector.")
		return

	if not is_instance_valid(start_anchor) or not is_instance_valid(end_plug):
		return

	var total_links: int = int(cable_length_meters / link_spacing)

	if end_plug.get_class() == "TetheredPlug" or end_plug.has_method("get_class"):
		if "max_cable_length" in end_plug:
			end_plug.max_cable_length = cable_length_meters
		if "anchor_point" in end_plug:
			end_plug.anchor_point = start_anchor
		if "partner_plug" in end_plug and "partner_plug" in start_anchor:
			end_plug.partner_plug = start_anchor

	if start_anchor.get_class() == "TetheredPlug" or start_anchor.has_method("get_class"):
		if "max_cable_length" in start_anchor:
			start_anchor.max_cable_length = cable_length_meters
		if "anchor_point" in start_anchor:
			start_anchor.anchor_point = end_plug
		if "partner_plug" in start_anchor:
			start_anchor.partner_plug = end_plug

	var start_pos: Vector3 = start_anchor.global_position
	var end_pos: Vector3 = end_plug.global_position
	var previous_body: Node3D = start_anchor

	var straight_dist: float = start_pos.distance_to(end_pos)
	var droop_amount: float = maxf(0.0, cable_length_meters - straight_dist) * 0.5

	for i: int in range(total_links):
		var link: RigidBody3D = link_scene.instantiate() as RigidBody3D
		link.mass = 0.05
		add_child(link)

		for prev: RigidBody3D in _links:
			link.add_collision_exception_with(prev)

		if start_anchor is PhysicsBody3D:
			link.add_collision_exception_with(start_anchor as PhysicsBody3D)

		var fraction: float = float(i + 1) / float(total_links + 1)
		var drop_offset: Vector3 = Vector3.DOWN * (4.0 * droop_amount * fraction * (1.0 - fraction))
		link.global_position = (start_pos.lerp(end_pos, fraction) + drop_offset)

		if not link.global_position.is_equal_approx(previous_body.global_position):
			link.look_at(previous_body.global_position)

		_links.append(link)

		var joint: PinJoint3D = PinJoint3D.new()
		add_child(joint)
		joint.global_position = previous_body.global_position.lerp(link.global_position, 0.5)

		if previous_body is PhysicsBody3D:
			joint.node_a = joint.get_path_to(previous_body)

		joint.node_b = joint.get_path_to(link)
		previous_body = link

	var final_joint: PinJoint3D = PinJoint3D.new()
	add_child(final_joint)
	final_joint.global_position = previous_body.global_position.lerp(end_pos, 0.5)
	final_joint.node_a = final_joint.get_path_to(previous_body)
	final_joint.node_b = final_joint.get_path_to(end_plug)

	if end_plug is CollisionObject3D:
		for prev: RigidBody3D in _links:
			end_plug.add_collision_exception_with(prev)
