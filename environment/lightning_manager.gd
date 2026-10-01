@tool
## Generates procedural electric arcs between source and receiver nodes.
class_name LightningManager
extends Node3D

@export_group("Required Assignments")
## Origin node where the lightning bolt begins.
@export var source_marker: Node3D

## Receiver nodes terminating lightning arcs.
@export var receiver_markers: Array[Node3D]

## Shader material applied to lightning mesh.
@export var lightning_material: ShaderMaterial

@export_group("Strike Control")
## Controls active lightning discharge state.
@export var strike_enabled: bool = false:
	set(value):
		strike_enabled = value
		if is_node_ready():
			if value:
				strike()
			else:
				stop_strike()

## Speed factor affecting flicker update rate.
@export var speed: float = 1.0

## Duration in seconds between geometry redraws.
@export var flicker_rate: float = 0.05

## Segment subdivisions count per lightning arc.
@export var subdivisions: int = 20

@export_group("Variation Ranges")
## Base vertical arc height at mid-trajectory.
@export var arc_height_base: float = 2.0

## Maximum random deviation added to arc apex.
@export var arc_height_variance: float = 1.0

## Base displacement amplitude for jitter noise.
@export var jitter_base: float = 0.3

## Maximum random deviation added to jitter noise.
@export var jitter_variance: float = 0.2

## Indicates whether lightning is currently active.
var is_striking: bool = false

## Procedural array mesh containing line geometry.
var _array_mesh: ArrayMesh = null

## Mesh instance displaying procedural lines in scene.
var _mesh_instance: MeshInstance3D = null

## Elapsed timer accumulator tracking next redraw.
var _flicker_timer: float = 0.0

## Current calculated vertical arc height offset.
var _current_arc_height: float = 0.0

## Current calculated displacement jitter amount.
var _current_jitter: float = 0.0

## Pre-allocated line vertices buffer to eliminate per-draw heap allocations.
var _vertices: PackedVector3Array = PackedVector3Array()

## Pre-allocated mesh array container sized to Mesh.ARRAY_MAX.
var _mesh_arrays: Array = []


## Prepares mesh instances, arrays, and initial strike state.
func _ready() -> void:
	print("LightningManager: _ready() initializing procedural mesh hierarchy.")
	var sprite_icon: Sprite3D = get_node_or_null("Sprite3D") as Sprite3D
	if is_instance_valid(sprite_icon):
		sprite_icon.visible = Engine.is_editor_hint()

	_array_mesh = ArrayMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _array_mesh

	if lightning_material != null:
		_mesh_instance.material_override = lightning_material

	_mesh_instance.visible = false
	add_child(_mesh_instance)

	_mesh_arrays.resize(Mesh.ARRAY_MAX)
	set_process(false)

	if strike_enabled:
		strike()


## Ticks flicker timer and redraws arcs at interval.
func _process(delta: float) -> void:
	if not is_striking:
		return

	_flicker_timer += delta * speed
	if _flicker_timer >= flicker_rate:
		_flicker_timer = 0.0
		_randomize_parameters()
		_draw_lightning()


## Initiates procedural lightning discharge rendering.
func strike() -> void:
	print("LightningManager: strike() called. Initiating lightning emission.")
	is_striking = true
	_flicker_timer = flicker_rate
	if _mesh_instance != null:
		_mesh_instance.visible = true
	set_process(true)


## Halts lightning discharge and clears geometry.
func stop_strike() -> void:
	print("LightningManager: stop_strike() called. Halting lightning emission.")
	is_striking = false
	set_process(false)
	if is_instance_valid(_array_mesh) and _array_mesh.get_surface_count() > 0:
		_array_mesh.clear_surfaces()
	if is_instance_valid(_mesh_instance):
		_mesh_instance.visible = false


## Randomizes arc apex height and jitter parameters.
func _randomize_parameters() -> void:
	_current_arc_height = arc_height_base + randf_range(-arc_height_variance, arc_height_variance)
	_current_jitter = jitter_base + randf_range(-jitter_variance, jitter_variance)


## Builds cubic Bezier arc lines into mesh arrays via [MathUtils].
func _draw_lightning() -> void:
	if not is_instance_valid(_array_mesh):
		return

	if source_marker == null or receiver_markers.is_empty():
		if _array_mesh.get_surface_count() > 0:
			_array_mesh.clear_surfaces()
		return

	var start_pos: Vector3 = to_local(source_marker.global_position)
	var active_receivers: int = 0
	for receiver: Node3D in receiver_markers:
		if is_instance_valid(receiver):
			active_receivers += 1

	if active_receivers == 0:
		if _array_mesh.get_surface_count() > 0:
			_array_mesh.clear_surfaces()
		return

	var total_verts: int = active_receivers * subdivisions * 2
	if _vertices.size() != total_verts:
		_vertices.resize(total_verts)

	var write_idx: int = 0

	for receiver: Node3D in receiver_markers:
		if not is_instance_valid(receiver):
			continue

		var end_pos: Vector3 = to_local(receiver.global_position)
		var current_pos: Vector3 = start_pos
		var seg_vector: Vector3 = end_pos - start_pos
		var p0: Vector3 = start_pos
		var p1: Vector3 = start_pos + (seg_vector * 0.25) + (Vector3.UP * _current_arc_height)
		var p2: Vector3 = start_pos + (seg_vector * 0.75) + (Vector3.UP * _current_arc_height)
		var p3: Vector3 = end_pos

		for i: int in range(1, subdivisions + 1):
			var t: float = float(i) / float(subdivisions)
			var target_pos: Vector3 = MathUtils.cubic_bezier(p0, p1, p2, p3, t)

			if i < subdivisions:
				target_pos.x += randf_range(-_current_jitter, _current_jitter)
				target_pos.y += randf_range(-_current_jitter, _current_jitter)
				target_pos.z += randf_range(-_current_jitter, _current_jitter)

			_vertices[write_idx] = current_pos
			_vertices[write_idx + 1] = target_pos
			write_idx += 2
			current_pos = target_pos

	_mesh_arrays[Mesh.ARRAY_VERTEX] = _vertices
	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, _mesh_arrays)
