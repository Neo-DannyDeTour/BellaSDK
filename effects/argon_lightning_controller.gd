@tool
class_name LightningController
extends Node3D

## Manages procedural 3D lightning strikes with forked child branches, custom
## FBM shader noise, dynamic impact lighting, and distance-delayed thunder.

const LIGHTNING_SHADER: Shader = preload("res://vfx/argon_lightning_strike.gdshader")
const PARAM_ENERGY: StringName = &"energy_multiplier"
const PARAM_SEED: StringName = &"strike_seed"
const PARAM_COLOR: StringName = &"bolt_color"

@export_category("Targets")
## Array of start [Marker3D] node paths representing high atmospheric points.
@export var start_markers: Array[NodePath] = []
## Array of end [Marker3D] node paths representing ground impact targets.
@export var end_markers: Array[NodePath] = []

@export_category("Appearance & Shape")
## Base color of the lightning outer plasma halo.
@export var lightning_color: Color = Color(0.35, 0.65, 1.0, 1.0)
## Peak HDR emission multiplier at the instant of strike.
@export var peak_energy: float = 14.0
## Number of jagged segments along the primary bolt trunk.
@export var segment_count: int = 22
## Maximum random displacement of intermediate trunk points.
@export var chaos_factor: float = 1.8
## Width / thickness of the primary lightning trunk in meters.
@export var bolt_width: float = 0.35

@export_category("Branching")
## Probability (0.0 to 1.0) of spawning a forked branch at each trunk segment.
@export var branch_chance: float = 0.32
## Maximum number of forked branches per strike.
@export var max_branches: int = 6
## Number of segments in each forked child branch.
@export var branch_segments: int = 9
## Length of child branches relative to the main trunk length.
@export var branch_length_ratio: float = 0.35
## Width multiplier for child branches relative to [member bolt_width].
@export var branch_width_scale: float = 0.45

@export_category("Timing & Frequency")
## Enable automated background storm strikes on random intervals.
@export var auto_strike: bool = true
## Minimum time in seconds between automated lightning strikes.
@export var min_interval: float = 2.0
## Maximum time in seconds between automated lightning strikes.
@export var max_interval: float = 6.0

@export_category("Audio")
## Optional thunder clap sound stream played after speed-of-sound delay.
@export var thunder_stream: AudioStream = null
## Speed of sound in meters per second (~343 m/s on Earth).
@export var speed_of_sound: float = 343.0

var _strike_timer: SceneTreeTimer = null
var _thunder_timer: SceneTreeTimer = null
var _active_tween: Tween = null
var _mesh_instance: MeshInstance3D = null
var _imm_mesh: ImmediateMesh = null
var _shader_mat: ShaderMaterial = null
var _impact_light: OmniLight3D = null
var _thunder_player: AudioStreamPlayer3D = null


## Initializes mesh, shader material, light, audio node, and storm loop.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(not start_markers.is_empty(), "Requires start_markers!")
	assert(not end_markers.is_empty(), "Requires end_markers!")

	_imm_mesh = ImmediateMesh.new()
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = LIGHTNING_SHADER
	_shader_mat.set_shader_parameter(PARAM_COLOR, lightning_color)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.top_level = true
	_mesh_instance.layers = 1
	_mesh_instance.mesh = _imm_mesh
	_mesh_instance.material_override = _shader_mat
	_mesh_instance.set_instance_shader_parameter(PARAM_ENERGY, 0.0)
	_mesh_instance.set_instance_shader_parameter(PARAM_SEED, 0.0)
	add_child(_mesh_instance)

	_impact_light = OmniLight3D.new()
	_impact_light.top_level = true
	_impact_light.light_color = lightning_color
	_impact_light.light_energy = 0.0
	_impact_light.omni_range = 45.0
	add_child(_impact_light)

	_thunder_player = AudioStreamPlayer3D.new()
	_thunder_player.top_level = true
	_thunder_player.stream = thunder_stream
	_thunder_player.max_distance = 500.0
	_thunder_player.unit_size = 30.0
	add_child(_thunder_player)

	if auto_strike:
		_schedule_next_strike()


## Triggers a lightning strike between specific marker array indices.
func strike_between_markers(start_idx: int, end_idx: int) -> void:
	if start_idx < 0 or start_idx >= start_markers.size():
		return
	if end_idx < 0 or end_idx >= end_markers.size():
		return

	var start_path: NodePath = start_markers[start_idx]
	var end_path: NodePath = end_markers[end_idx]
	var start_node: Marker3D = get_node_or_null(start_path) as Marker3D
	var end_node: Marker3D = get_node_or_null(end_path) as Marker3D

	if is_instance_valid(start_node) and is_instance_valid(end_node):
		strike_custom(start_node.global_position, end_node.global_position)


## Triggers a lightning strike between two arbitrary world-space coordinates.
func strike_custom(start_pos: Vector3, end_pos: Vector3) -> void:
	print("Lightning strike: ", start_pos, " -> ", end_pos)
	_generate_bolt(start_pos, end_pos)
	_schedule_thunder(end_pos)


## Schedules the timer for the next random strike interval.
func _schedule_next_strike() -> void:
	if not auto_strike or not is_inside_tree():
		return
	var interval: float = randf_range(min_interval, max_interval)
	_strike_timer = get_tree().create_timer(interval)
	if not _strike_timer.timeout.is_connected(_on_strike_timeout):
		_strike_timer.timeout.connect(_on_strike_timeout)


## Executes a single lightning strike between randomly chosen markers.
func _on_strike_timeout() -> void:
	if not auto_strike:
		return
	if not start_markers.is_empty() and not end_markers.is_empty():
		var s_idx: int = randi() % start_markers.size()
		var e_idx: int = randi() % end_markers.size()
		strike_between_markers(s_idx, e_idx)

	_schedule_next_strike()


## Builds trunk and forked child branches into a single triangle surface.
func _generate_bolt(start_pos: Vector3, end_pos: Vector3) -> void:
	_imm_mesh.clear_surfaces()
	_imm_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var cam: Camera3D = get_viewport().get_camera_3d()
	var cam_pos: Vector3 = Vector3.ZERO
	if is_instance_valid(cam):
		cam_pos = cam.global_position

	var trunk_points: Array[Vector3] = _build_point_chain(
		start_pos, end_pos, segment_count, chaos_factor, true
	)
	_append_ribbon_to_surface(trunk_points, cam_pos, bolt_width * 0.5, 1.0)

	var trunk_dir: Vector3 = (end_pos - start_pos).normalized()
	var trunk_len: float = sqrt(start_pos.distance_squared_to(end_pos))
	var spawned_branches: int = 0

	for i: int in range(2, trunk_points.size() - 2):
		if spawned_branches >= max_branches:
			break
		if randf() > branch_chance:
			continue

		spawned_branches += 1
		var origin: Vector3 = trunk_points[i]
		var spread: Vector3 = Vector3(
			randf_range(-0.75, 0.75), randf_range(-0.4, -0.1), randf_range(-0.75, 0.75)
		)
		var b_dir: Vector3 = (trunk_dir + spread).normalized()
		var b_len: float = trunk_len * branch_length_ratio * randf_range(0.6, 1.1)
		var b_end: Vector3 = origin + b_dir * b_len

		var branch_points: Array[Vector3] = _build_point_chain(
			origin, b_end, branch_segments, chaos_factor * 0.45, false
		)
		_append_ribbon_to_surface(
			branch_points, cam_pos, bolt_width * 0.5 * branch_width_scale, 0.65
		)

	_imm_mesh.surface_end()

	_impact_light.global_position = end_pos
	_mesh_instance.set_instance_shader_parameter(PARAM_SEED, randf() * 100.0)
	_mesh_instance.set_instance_shader_parameter(PARAM_ENERGY, peak_energy)

	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_impact_light.light_energy = 30.0
	_active_tween.tween_property(_impact_light, "light_energy", 0.0, 0.18)
	_active_tween.tween_method(_set_bolt_energy, peak_energy, 0.0, 0.22)
	_active_tween.chain().tween_callback(_clear_bolt_mesh)


## Generates a list of jittered 3D points between two coordinates.
func _build_point_chain(
	from_pos: Vector3, to_pos: Vector3, steps: int, chaos: float, pin_end: bool
) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	pts.append(from_pos)

	for i: int in range(1, steps):
		var t: float = float(i) / float(steps)
		var base_pos: Vector3 = from_pos.lerp(to_pos, t)
		var envelope: float = 1.0 - absf(t - 0.5) * 1.5 if pin_end else t
		var rand_vec: Vector3 = Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
		)
		pts.append(base_pos + rand_vec * (chaos * maxf(envelope, 0.15)))

	pts.append(to_pos)
	return pts


## Appends camera-facing ribbon triangles for a point chain into [_imm_mesh].
func _append_ribbon_to_surface(
	pts: Array[Vector3], cam_pos: Vector3, half_width: float, intensity: float
) -> void:
	var count: int = pts.size()
	var vert_col: Color = Color(intensity, 1.0, 1.0, 1.0)

	for i: int in range(count - 1):
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var v1: float = float(i) / float(count - 1)
		var v2: float = float(i + 1) / float(count - 1)

		var taper1: float = 1.0 - (v1 * 0.65 * (1.0 - intensity))
		var taper2: float = 1.0 - (v2 * 0.65 * (1.0 - intensity))

		var dir: Vector3 = (p2 - p1).normalized()
		var to_cam: Vector3 = (cam_pos - p1).normalized()
		var perp: Vector3 = dir.cross(to_cam).normalized()
		if perp.length_squared() < 0.0001:
			perp = Vector3.RIGHT

		var off1: Vector3 = perp * (half_width * taper1)
		var off2: Vector3 = perp * (half_width * taper2)

		var a: Vector3 = p1 - off1
		var b: Vector3 = p1 + off1
		var c: Vector3 = p2 - off2
		var d: Vector3 = p2 + off2

		_imm_mesh.surface_set_color(vert_col)
		_imm_mesh.surface_set_uv(Vector2(0.0, v1))
		_imm_mesh.surface_add_vertex(a)

		_imm_mesh.surface_set_color(vert_col)
		_imm_mesh.surface_set_uv(Vector2(1.0, v1))
		_imm_mesh.surface_add_vertex(b)

		_imm_mesh.surface_set_color(vert_col)
		_imm_mesh.surface_set_uv(Vector2(0.0, v2))
		_imm_mesh.surface_add_vertex(c)

		_imm_mesh.surface_set_color(vert_col)
		_imm_mesh.surface_set_uv(Vector2(1.0, v1))
		_imm_mesh.surface_add_vertex(b)

		_imm_mesh.surface_set_color(vert_col)
		_imm_mesh.surface_set_uv(Vector2(1.0, v2))
		_imm_mesh.surface_add_vertex(d)

		_imm_mesh.surface_set_color(vert_col)
		_imm_mesh.surface_set_uv(Vector2(0.0, v2))
		_imm_mesh.surface_add_vertex(c)


## Updates the per-instance shader energy parameter during fade-out tween.
func _set_bolt_energy(val: float) -> void:
	if is_instance_valid(_mesh_instance):
		_mesh_instance.set_instance_shader_parameter(PARAM_ENERGY, val)


## Clears the [ImmediateMesh] surfaces after the flash tween completes.
func _clear_bolt_mesh() -> void:
	if is_instance_valid(_imm_mesh):
		_imm_mesh.clear_surfaces()


## Computes distance to camera via [method Vector3.distance_squared_to] and
## delays thunder playback based on [member speed_of_sound].
func _schedule_thunder(impact_pos: Vector3) -> void:
	if not is_instance_valid(thunder_stream) or not is_inside_tree():
		return

	_thunder_player.global_position = impact_pos
	var cam: Camera3D = get_viewport().get_camera_3d()
	var delay: float = 0.0
	if is_instance_valid(cam) and speed_of_sound > 0.0:
		var dist_sq: float = cam.global_position.distance_squared_to(impact_pos)
		delay = sqrt(dist_sq) / speed_of_sound

	if delay <= 0.02:
		_play_thunder()
	else:
		_thunder_timer = get_tree().create_timer(delay)
		if not _thunder_timer.timeout.is_connected(_play_thunder):
			_thunder_timer.timeout.connect(_play_thunder)


## Plays the thunder clap with slight pitch variation.
func _play_thunder() -> void:
	if is_instance_valid(_thunder_player) and is_inside_tree():
		_thunder_player.pitch_scale = randf_range(0.85, 1.15)
		_thunder_player.play()
