@tool
## Procedural lightning arc generator optimized for consistent 60 FPS.
class_name LightningManager
extends Node3D

## Emitted when lightning discharge starts via [method strike].
signal strike_started

## Emitted when lightning discharge halts via [method stop_strike].
signal strike_finished

## Segment count for the primary trunk arc.
const TRUNK_SEGMENTS: int = 14

## Segment count for secondary fork branches.
const BRANCH_SEGMENTS: int = 6

## Segment count for companion braided filaments.
const COMPANION_SEGMENTS: int = 10

## Maximum number of fork branches allowed per receiver bolt.
const MAX_BRANCHES_PER_BOLT: int = 2

## Number of vertices per ribbon slice across both planes.
const VERTS_PER_SLICE: int = 4

@export_group("Required Assignments")
## Origin node where the lightning bolt begins.
@export var source_marker: Node3D

## Receiver nodes terminating lightning arcs.
@export var receiver_markers: Array[Node3D]:
	set(value):
		receiver_markers = value
		if is_inside_tree():
			_rebuild_static_buffers()

## Shader material applied to lightning mesh.
@export var lightning_material: ShaderMaterial:
	set(value):
		lightning_material = value
		if is_instance_valid(_mesh_instance):
			_mesh_instance.material_override = lightning_material

@export_group("Strike Control")
## Controls active lightning discharge state.
@export var strike_enabled: bool = false:
	set(value):
		strike_enabled = value
		if not is_inside_tree():
			return
		if value:
			strike()
		else:
			stop_strike()

## Playback speed scalar modifying flicker cycle timings.
@export_range(0.1, 5.0, 0.1) var speed: float = 1.0

## Duration in seconds between geometry redraws (12.5 Hz default).
@export_range(0.02, 0.2, 0.01) var flicker_rate: float = 0.08

@export_group("Shape Parameters")
## Primary displacement distance applied to midpoints.
@export_range(0.1, 3.0, 0.1) var displacement: float = 0.9

## Parabolic vertical apex offset bowing the arc upward.
@export var arc_height: float = 1.2

## Core ribbon diameter at source marker origin.
@export_range(0.02, 0.5, 0.01) var bolt_width: float = 0.09

## Width scaling multiplier applied at arc termination.
@export_range(0.05, 1.0, 0.05) var taper_ratio: float = 0.3

## Enables secondary braided companion arc alongside main trunk.
@export var enable_companion: bool = true

## Indicates whether lightning is currently active.
var is_striking: bool = false

var _array_mesh: ArrayMesh = null
var _mesh_instance: MeshInstance3D = null
var _flicker_timer: float = 0.0

var _vertices: PackedVector3Array = PackedVector3Array()
var _uvs: PackedVector2Array = PackedVector2Array()
var _indices: PackedInt32Array = PackedInt32Array()
var _mesh_arrays: Array = []

var _point_buffer: PackedVector3Array = PackedVector3Array()


## Prepares mesh hierarchy, allocates static buffers, and sets initial state.
func _ready() -> void:
	print("LightningManager: _ready() initializing high-performance pipeline.")
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
	_point_buffer.resize(TRUNK_SEGMENTS + 1)
	_rebuild_static_buffers()
	set_process(false)

	if strike_enabled:
		strike()


## Ticks flicker timer and refreshes geometry at [member flicker_rate] intervals.
func _process(delta: float) -> void:
	if not is_striking:
		return

	_flicker_timer += delta * speed
	if _flicker_timer >= flicker_rate:
		_flicker_timer = 0.0
		_update_lightning_vertices()


## Activates lightning discharge and emits [signal strike_started].
func strike() -> void:
	print("LightningManager: strike() called. Starting discharge.")
	is_striking = true
	_flicker_timer = flicker_rate
	if is_instance_valid(_mesh_instance):
		_mesh_instance.visible = true
	set_process(true)
	strike_started.emit()


## Deactivates lightning discharge and emits [signal strike_finished].
func stop_strike() -> void:
	print("LightningManager: stop_strike() called. Stopping discharge.")
	is_striking = false
	set_process(false)
	if is_instance_valid(_array_mesh) and _array_mesh.get_surface_count() > 0:
		_array_mesh.clear_surfaces()
	if is_instance_valid(_mesh_instance):
		_mesh_instance.visible = false
	strike_finished.emit()


## Pre-allocates vertex, UV, and index arrays based on receiver count.
func _rebuild_static_buffers() -> void:
	var receiver_count: int = receiver_markers.size()
	if receiver_count == 0:
		_vertices.clear()
		_uvs.clear()
		_indices.clear()
		return

	var verts_per_receiver: int = (
		(TRUNK_SEGMENTS + 1) * VERTS_PER_SLICE
		+ MAX_BRANCHES_PER_BOLT * (BRANCH_SEGMENTS + 1) * VERTS_PER_SLICE
	)
	var indices_per_receiver: int = (
		TRUNK_SEGMENTS * 12 + MAX_BRANCHES_PER_BOLT * BRANCH_SEGMENTS * 12
	)

	if enable_companion:
		verts_per_receiver += (COMPANION_SEGMENTS + 1) * VERTS_PER_SLICE
		indices_per_receiver += COMPANION_SEGMENTS * 12

	var total_verts: int = receiver_count * verts_per_receiver
	var total_indices: int = receiver_count * indices_per_receiver

	_vertices.resize(total_verts)
	_uvs.resize(total_verts)
	_indices.resize(total_indices)

	var v_offset: int = 0
	var i_offset: int = 0

	for r_idx: int in range(receiver_count):
		# Trunk layout
		_build_static_topology(TRUNK_SEGMENTS, v_offset, i_offset)
		v_offset += (TRUNK_SEGMENTS + 1) * VERTS_PER_SLICE
		i_offset += TRUNK_SEGMENTS * 12

		# Branch layouts
		for b: int in range(MAX_BRANCHES_PER_BOLT):
			_build_static_topology(BRANCH_SEGMENTS, v_offset, i_offset)
			v_offset += (BRANCH_SEGMENTS + 1) * VERTS_PER_SLICE
			i_offset += BRANCH_SEGMENTS * 12

		# Companion layout
		if enable_companion:
			_build_static_topology(COMPANION_SEGMENTS, v_offset, i_offset)
			v_offset += (COMPANION_SEGMENTS + 1) * VERTS_PER_SLICE
			i_offset += COMPANION_SEGMENTS * 12

	_mesh_arrays[Mesh.ARRAY_TEX_UV] = _uvs
	_mesh_arrays[Mesh.ARRAY_INDEX] = _indices


## Populates UV coordinates and index triangles for a single ribbon strip.
func _build_static_topology(segments: int, base_v: int, base_i: int) -> void:
	var slices: int = segments + 1
	for s: int in range(slices):
		var t: float = float(s) / float(segments)
		var v_idx: int = base_v + s * VERTS_PER_SLICE
		_uvs[v_idx + 0] = Vector2(0.0, t)
		_uvs[v_idx + 1] = Vector2(1.0, t)
		_uvs[v_idx + 2] = Vector2(0.0, t)
		_uvs[v_idx + 3] = Vector2(1.0, t)

		if s > 0:
			var prev_v: int = base_v + (s - 1) * VERTS_PER_SLICE
			var curr_v: int = v_idx
			var seg_i: int = base_i + (s - 1) * 12

			# Plane 1
			_indices[seg_i + 0] = prev_v + 0
			_indices[seg_i + 1] = curr_v + 0
			_indices[seg_i + 2] = curr_v + 1
			_indices[seg_i + 3] = prev_v + 0
			_indices[seg_i + 4] = curr_v + 1
			_indices[seg_i + 5] = prev_v + 1

			# Plane 2
			_indices[seg_i + 6] = prev_v + 2
			_indices[seg_i + 7] = curr_v + 2
			_indices[seg_i + 8] = curr_v + 3
			_indices[seg_i + 9] = prev_v + 2
			_indices[seg_i + 10] = curr_v + 3
			_indices[seg_i + 11] = prev_v + 3


## Refreshes vertex positions without allocating new heap memory.
func _update_lightning_vertices() -> void:
	if not is_instance_valid(_array_mesh):
		return

	if not is_instance_valid(source_marker) or receiver_markers.is_empty():
		if _array_mesh.get_surface_count() > 0:
			_array_mesh.clear_surfaces()
		return

	var start_pos: Vector3 = to_local(source_marker.global_position)
	var write_v: int = 0

	for receiver: Node3D in receiver_markers:
		if not is_instance_valid(receiver):
			continue

		var end_pos: Vector3 = to_local(receiver.global_position)

		# 1. Main trunk points and mesh
		_generate_points_iterative(start_pos, end_pos, TRUNK_SEGMENTS, displacement, arc_height)
		_write_ribbon_vertices(TRUNK_SEGMENTS, bolt_width, bolt_width * taper_ratio, write_v)
		write_v += (TRUNK_SEGMENTS + 1) * VERTS_PER_SLICE

		# 2. Budgeted secondary branches
		for b: int in range(MAX_BRANCHES_PER_BOLT):
			var fork_idx: int = randi_range(3, TRUNK_SEGMENTS - 4)
			var fork_start: Vector3 = _point_buffer[fork_idx]
			var fwd: Vector3 = (end_pos - start_pos).normalized()
			var perp: Vector3 = _get_perpendicular_vector(fwd)
			var branch_dir: Vector3 = (fwd.rotated(perp, randf_range(-0.6, 0.6))).normalized()
			var branch_len: float = start_pos.distance_to(end_pos) * randf_range(0.2, 0.45)
			var branch_end: Vector3 = fork_start + branch_dir * branch_len

			_generate_points_iterative(
				fork_start, branch_end, BRANCH_SEGMENTS, displacement * 0.5, 0.0
			)
			_write_ribbon_vertices(BRANCH_SEGMENTS, bolt_width * 0.45, bolt_width * 0.05, write_v)
			write_v += (BRANCH_SEGMENTS + 1) * VERTS_PER_SLICE

		# 3. Companion filament
		if enable_companion:
			_generate_points_iterative(
				start_pos, end_pos, COMPANION_SEGMENTS, displacement * 1.3, arc_height * 0.8
			)
			_write_ribbon_vertices(COMPANION_SEGMENTS, bolt_width * 0.4, bolt_width * 0.1, write_v)
			write_v += (COMPANION_SEGMENTS + 1) * VERTS_PER_SLICE

	_mesh_arrays[Mesh.ARRAY_VERTEX] = _vertices
	_mesh_arrays[Mesh.ARRAY_TEX_UV] = _uvs
	_mesh_arrays[Mesh.ARRAY_INDEX] = _indices

	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _mesh_arrays)


## Generates jittered points along a linear trajectory into target buffer.
func _generate_points_iterative(
	p_start: Vector3, p_end: Vector3, segments: int, disp: float, arc: float
) -> void:
	_point_buffer[0] = p_start
	_point_buffer[segments] = p_end

	var forward: Vector3 = (p_end - p_start).normalized()
	if forward.is_zero_approx():
		forward = Vector3.UP

	for i: int in range(1, segments):
		var t: float = float(i) / float(segments)
		var base_pos: Vector3 = p_start.lerp(p_end, t)

		# Parabolic vertical apex bow
		var arc_offset: float = sin(t * PI) * arc
		base_pos.y += arc_offset

		# Lateral jitter
		var perp: Vector3 = _get_perpendicular_vector(forward)
		var jitter_amt: float = randf_range(-disp, disp) * sin(t * PI)
		_point_buffer[i] = base_pos + perp * jitter_amt


## Emits cross-quad ribbon vertex positions into the flat vertex buffer.
func _write_ribbon_vertices(segments: int, start_w: float, end_w: float, v_offset: int) -> void:
	var count: int = segments + 1
	for i: int in range(count):
		var curr_pos: Vector3 = _point_buffer[i]
		var t: float = float(i) / float(segments)
		var current_w: float = lerpf(start_w, end_w, t)

		var fwd: Vector3
		if i == 0:
			fwd = (_point_buffer[1] - curr_pos).normalized()
		elif i == count - 1:
			fwd = (curr_pos - _point_buffer[i - 1]).normalized()
		else:
			fwd = (_point_buffer[i + 1] - _point_buffer[i - 1]).normalized()

		if fwd.is_zero_approx():
			fwd = Vector3.UP

		var ref: Vector3 = Vector3.UP if absf(fwd.y) < 0.9 else Vector3.RIGHT
		var n: Vector3 = fwd.cross(ref).normalized()
		var b: Vector3 = fwd.cross(n).normalized()

		var v_idx: int = v_offset + i * VERTS_PER_SLICE

		# Plane 1 (Normal)
		_vertices[v_idx + 0] = curr_pos + n * current_w
		_vertices[v_idx + 1] = curr_pos - n * current_w

		# Plane 2 (Binormal)
		_vertices[v_idx + 2] = curr_pos + b * current_w
		_vertices[v_idx + 3] = curr_pos - b * current_w


## Computes a randomized orthogonal vector relative to direction vector.
func _get_perpendicular_vector(dir: Vector3) -> Vector3:
	var ref: Vector3 = Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
	var n: Vector3 = dir.cross(ref).normalized()
	var b: Vector3 = dir.cross(n).normalized()
	var angle: float = randf() * TAU
	return (n * cos(angle) + b * sin(angle)).normalized()
