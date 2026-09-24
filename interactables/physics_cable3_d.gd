@tool
## Physics-driven catenary cable using Verlet particle integration and batched MultiMesh.
##
## Connects two endpoints without instantiating child bodies, solving catenary curves
## and rendering all visual cylindrical segments in a single batched GPU draw call.
class_name PhysicsCable3D
extends Node3D

@export_category("Cable Connections")
## Starting anchor [Node3D] point where the cable originates.
@export var start_anchor: Node3D

## Ending plug [RigidBody3D] point where the cable terminates and interacts with physics.
@export var end_plug: RigidBody3D

@export_category("Physics Properties")
## Total physical length of the cable in meters when fully extended.
@export var cable_length_meters: float = 3.0:
	set(value):
		cable_length_meters = maxf(0.5, value)
		if Engine.is_editor_hint():
			_update_debug_sphere_transform()

## Target distance spacing in meters between consecutive simulated particle nodes.
@export var link_spacing: float = 0.2:
	set(value):
		link_spacing = maxf(0.05, value)

## Gravitational acceleration vector applied to free-hanging cable particles.
@export var gravity: Vector3 = Vector3(0.0, -9.8, 0.0)

## Velocity damping factor per simulation step to prevent endless oscillation.
@export_range(0.8, 0.999) var damping: float = 0.98

## Number of relaxation solver iterations per physics frame for cable stiffness.
@export_range(1, 16) var constraint_iterations: int = 5

## Elastic tension stiffness pulling on the plug when the cable is stretched taut.
@export var tension_force: float = 60.0

@export_category("Appearance")
## Base albedo color applied to the instanced cable cylinder mesh segments.
@export var cable_color: Color = Color(0.1, 0.1, 0.1):
	set(value):
		cable_color = value
		if is_instance_valid(_material):
			_material.albedo_color = cable_color

## Radial thickness of the visual cable cylinder instances in meters.
@export var thickness: float = 0.04:
	set(value):
		thickness = value
		if is_instance_valid(_base_mesh):
			_base_mesh.top_radius = thickness
			_base_mesh.bottom_radius = thickness

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

## Current world-space positions of simulated Verlet particles.
var _positions: PackedVector3Array = PackedVector3Array()

## World-space positions of simulated Verlet particles from the previous frame.
var _prev_positions: PackedVector3Array = PackedVector3Array()

## Single [MultiMeshInstance3D] node rendering all cable segments in one draw call.
var _multimesh_instance: MultiMeshInstance3D

## The [MultiMesh] resource containing per-instance transformation matrices.
var _multimesh: MultiMesh

## Shared cylinder mesh resource used across all segment instances.
var _base_mesh: CylinderMesh

## Shared material resource applied to the instanced cable mesh.
var _material: StandardMaterial3D

## Editor visualizer mesh indicating maximum cable extension range.
var _debug_sphere: MeshInstance3D

## Cached position of the start anchor from the previous frame.
var _last_start_pos: Vector3 = Vector3.ZERO

## Cached position of the end plug from the previous frame.
var _last_end_pos: Vector3 = Vector3.ZERO

## Desired rest distance between adjacent particles.
var _segment_length: float = 0.2

## Total count of simulated particle points along the cable.
var _point_count: int = 0


## Initializes simulation particles, batched mesh instances, or editor debug helpers.
func _ready() -> void:
	print("PhysicsCable3D: _ready() called.")
	if not Engine.is_editor_hint():
		if is_instance_valid(_editor_icon):
			_editor_icon.queue_free()

		_setup_cable_system()
	else:
		_setup_debug_sphere()


## Updates editor debug visuals or propagates cable transforms to the GPU instance buffer.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_debug_sphere_transform()
		return

	if _point_count < 2 or not is_instance_valid(_multimesh):
		return

	_update_multimesh_transforms()


## Advances the Verlet particle integration and constraint solver steps.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not is_instance_valid(start_anchor) or not is_instance_valid(end_plug):
		return

	var start_pos: Vector3 = start_anchor.global_position
	var end_pos: Vector3 = end_plug.global_position

	var last_idx: int = _point_count - 1
	_positions[0] = start_pos
	_positions[last_idx] = end_pos

	var dt_sq: float = delta * delta
	for i: int in range(1, last_idx):
		var current: Vector3 = _positions[i]
		var vel: Vector3 = (current - _prev_positions[i]) * damping
		_prev_positions[i] = current
		_positions[i] = current + vel + (gravity * dt_sq)

	for iter: int in range(constraint_iterations):
		_positions[0] = start_pos
		_positions[last_idx] = end_pos

		for i: int in range(last_idx):
			var p_a: Vector3 = _positions[i]
			var p_b: Vector3 = _positions[i + 1]
			var delta_vec: Vector3 = p_b - p_a
			var dist: float = delta_vec.length()

			if dist > 0.0001:
				var diff: float = (dist - _segment_length) / dist
				var correction: Vector3 = delta_vec * (0.5 * diff)

				if i != 0:
					_positions[i] += correction
				if (i + 1) != last_idx:
					_positions[i + 1] -= correction

	var total_dist: float = start_pos.distance_to(end_pos)
	if total_dist > cable_length_meters:
		var stretch: float = total_dist - cable_length_meters
		var pull_dir: Vector3 = (start_pos - end_pos).normalized()
		end_plug.apply_central_force(pull_dir * (stretch * tension_force))


## Configures cable particle positions and initializes the [MultiMeshInstance3D].
func _setup_cable_system() -> void:
	print("PhysicsCable3D: _setup_cable_system() initializing Verlet system.")
	if not is_instance_valid(start_anchor) or not is_instance_valid(end_plug):
		push_error("PhysicsCable3D: Start anchor or End plug is unassigned!")
		return

	var segment_count: int = maxi(2, int(cable_length_meters / link_spacing))
	_point_count = segment_count + 1
	_segment_length = cable_length_meters / float(segment_count)

	_positions.resize(_point_count)
	_prev_positions.resize(_point_count)

	var start_pos: Vector3 = start_anchor.global_position
	var end_pos: Vector3 = end_plug.global_position

	for i: int in range(_point_count):
		var t: float = float(i) / float(segment_count)
		var pos: Vector3 = start_pos.lerp(end_pos, t)
		_positions[i] = pos
		_prev_positions[i] = pos

	_last_start_pos = start_pos
	_last_end_pos = end_pos

	_create_resources(segment_count)
	_configure_plug_tether()


## Sets up shared mesh, material, and the [MultiMeshInstance3D] node.
func _create_resources(segment_count: int) -> void:
	print("PhysicsCable3D: Building MultiMesh for ", segment_count, " segments.")
	_material = StandardMaterial3D.new()
	_material.albedo_color = cable_color
	_material.roughness = 0.8

	_base_mesh = CylinderMesh.new()
	_base_mesh.top_radius = thickness
	_base_mesh.bottom_radius = thickness
	_base_mesh.height = 1.0
	_base_mesh.radial_segments = 8
	_base_mesh.rings = 1
	_base_mesh.material = _material

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.instance_count = segment_count
	_multimesh.mesh = _base_mesh

	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = _multimesh
	_multimesh_instance.top_level = true
	_multimesh_instance.layers = 4
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	add_child(_multimesh_instance)


## Updates instance transforms in the [MultiMesh] to align segments with particles.
func _update_multimesh_transforms() -> void:
	var segment_count: int = _point_count - 1
	for i: int in range(segment_count):
		var p1: Vector3 = _positions[i]
		var p2: Vector3 = _positions[i + 1]
		var dir: Vector3 = p2 - p1
		var dist: float = dir.length()

		if dist < 0.0001:
			continue

		var y_axis: Vector3 = dir / dist
		var up_hint: Vector3 = Vector3.UP if absf(y_axis.y) < 0.99 else Vector3.RIGHT
		var x_axis: Vector3 = up_hint.cross(y_axis).normalized()
		var z_axis: Vector3 = y_axis.cross(x_axis).normalized()

		var mesh_basis: Basis = Basis(x_axis, y_axis * dist, z_axis)
		var center: Vector3 = (p1 + p2) * 0.5
		_multimesh.set_instance_transform(i, Transform3D(mesh_basis, center))


## Synchronizes tether parameters if endpoints implement plug interface contracts.
func _configure_plug_tether() -> void:
	print("PhysicsCable3D: Configuring plug endpoints.")
	if "max_cable_length" in end_plug:
		end_plug.max_cable_length = cable_length_meters
	if "anchor_point" in end_plug:
		end_plug.anchor_point = start_anchor
	if "partner_plug" in end_plug and "partner_plug" in start_anchor:
		end_plug.partner_plug = start_anchor

	if "max_cable_length" in start_anchor:
		start_anchor.max_cable_length = cable_length_meters
	if "anchor_point" in start_anchor:
		start_anchor.anchor_point = end_plug
	if "partner_plug" in start_anchor:
		start_anchor.partner_plug = end_plug


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
	_debug_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_sphere.visible = show_debug_sphere

	add_child(_debug_sphere)


## Keeps the debug sphere anchored to the start position and scaled to cable reach.
func _update_debug_sphere_transform() -> void:
	if show_debug_sphere and is_instance_valid(_debug_sphere) and is_instance_valid(start_anchor):
		_debug_sphere.global_position = start_anchor.global_position
		var diameter: float = cable_length_meters * 2.0
		_debug_sphere.scale = Vector3(diameter, diameter, diameter)
