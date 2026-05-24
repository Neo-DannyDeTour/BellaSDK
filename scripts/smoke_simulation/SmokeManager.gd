extends Node
# SmokeManager.gd (Autoload)
# Now supports cinematic turbulence (swirls) and editor controls.

var active_holes: Array[Dictionary] = []
var current_player_pos: Vector3 = Vector3.ZERO
var global_time: float = 0.0

@export_group("System Controls")
# How long the holes and swirls persist in seconds
@export var heal_time_seconds: float = 4.0
# Radius around the player that automatically clears fog
@export var player_trail_radius: float = 3.5

@export_group("Cinematic Pellet Effects")
# How cleanly pellets carve through the smoke (0.0 = no hole, 1.0 = clean cut)
@export_range(0.0, 1.0) var hole_clear_intensity: float = 0.8
# The strength of the swirling turbulence kicked up by pellets (0.0 = no swirl)
@export var swirl_strength: float = 1.8
# Controls the complexity of the swirl pattern. Lower is tighter, higher is more turbulent.
@export var swirl_frequency: float = 0.5

# GPU Variables
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var texture_rid: RID

# Buffer and Uniforms
var buffer_rid: RID
var uniform_set: RID

const MAX_HOLES = 50
const BUFFER_SIZE = MAX_HOLES * 32

var active_fog_volume: FogVolume


func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	_initialize_gpu()


func _initialize_gpu() -> void:
	var shader_file: RDShaderFile = load("res://scripts/smoke_simulation/smoke_compute.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

	# 1. Create 3D Texture (rgba8)
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	fmt.width = 128
	fmt.height = 128
	fmt.depth = 128
	fmt.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	)

	var view := RDTextureView.new()
	texture_rid = rd.texture_create(fmt, view)

	# 2. Create Storage Buffer
	var empty_bytes := PackedByteArray()
	empty_bytes.resize(BUFFER_SIZE)
	buffer_rid = rd.storage_buffer_create(BUFFER_SIZE, empty_bytes)

	# 3. Create Uniforms
	var tex_uniform := RDUniform.new()
	tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	tex_uniform.binding = 0
	tex_uniform.add_id(texture_rid)

	var buf_uniform := RDUniform.new()
	buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	buf_uniform.binding = 1
	buf_uniform.add_id(buffer_rid)

	uniform_set = rd.uniform_set_create([tex_uniform, buf_uniform], shader, 0)


func update_player_position(pos: Vector3) -> void:
	current_player_pos = pos


func add_bullet_hole(start: Vector3, dir: Vector3, length: float, radius: float = 1.0) -> void:
	# --- OPTIMIZATION: Enforce strict cap so the array never bloats ---
	if active_holes.size() >= MAX_HOLES:
		active_holes.pop_front()  # Instantly remove the oldest hole
	# ------------------------------------------------------------------

	# We've removed 'intensity' argument. It's now handled globally in the editor.
	active_holes.append(
		{"start": start, "end": start + (dir * length), "radius": radius, "time_alive": 0.0}
	)


func _process(delta: float) -> void:
	global_time += delta

	# Update and cull old bullet holes
	for i in range(active_holes.size() - 1, -1, -1):
		active_holes[i].time_alive += delta
		if active_holes[i].time_alive > heal_time_seconds:
			active_holes.remove_at(i)

	RenderingServer.call_on_render_thread(_dispatch_to_compute_shader.bind(delta))


func _dispatch_to_compute_shader(delta: float) -> void:
	if not rd or not pipeline:
		return

	# --- DYNAMIC FOG BOUNDS ---
	var grid_pos := Vector3.ZERO
	var volume_size := Vector3(128.0, 128.0, 128.0)

	if is_instance_valid(active_fog_volume) and active_fog_volume.is_inside_tree():
		volume_size = active_fog_volume.size
		grid_pos = active_fog_volume.global_position - (volume_size / 2.0)
	else:
		# Safely skip the entire compute pass if the fog volume doesn't exist
		return

	# --- UPDATE BUFFER SAFELY ---
	var hole_data := PackedFloat32Array()
	var holes_to_process: int = min(active_holes.size(), MAX_HOLES)

	for i in range(holes_to_process):
		var hole := active_holes[i]
		hole_data.append(hole.start.x)
		hole_data.append(hole.start.y)
		hole_data.append(hole.start.z)
		hole_data.append(hole.radius)
		hole_data.append(hole.end.x)
		hole_data.append(hole.end.y)
		hole_data.append(hole.end.z)
		hole_data.append(hole.time_alive)

	var hole_bytes := hole_data.to_byte_array()
	if hole_bytes.size() > 0:
		rd.buffer_update(buffer_rid, 0, hole_bytes.size(), hole_bytes)

	var heal_rate := 1.0 / heal_time_seconds
	var is_even_frame := Engine.get_process_frames() % 2 == 0
	var z_offset: float = 64.0 if is_even_frame else 0.0

	# --- PACK PUSH CONSTANTS PERFECTLY (Strict 16-byte alignment, 80 BYTES TOTAL) ---
	# NOTE: Ensure your GLSL shader expects exactly 5 vec4s (20 floats / 80 bytes)
	var push_constants_array := PackedFloat32Array(
		[
			# 1. Vec4 (player_pos, num_holes)
			current_player_pos.x,
			current_player_pos.y,
			current_player_pos.z,
			float(holes_to_process),
			# 2. Vec4 (grid_pos, delta)
			grid_pos.x,
			grid_pos.y,
			grid_pos.z,
			delta * 2.0,
			# 3. Vec4 (grid_size, time)
			volume_size.x,
			volume_size.y,
			volume_size.z,
			global_time,
			# 4. Vec4 (global_configs)
			hole_clear_intensity,
			swirl_strength,
			swirl_frequency,
			player_trail_radius,
			# 5. Vec4 (system_offset + heal_rate + padding to fulfill alignment)
			z_offset,
			heal_rate,
			0.0,
			0.0
		]
	)

	# CRITICAL FIX: Convert the float array to a byte array for the GPU
	var push_constants_bytes := push_constants_array.to_byte_array()

	# --- DISPATCH TO GPU ---
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

	# CRITICAL FIX: Pass the byte array, and use its exact size
	rd.compute_list_set_push_constant(
		compute_list, push_constants_bytes, push_constants_bytes.size()
	)

	rd.compute_list_dispatch(compute_list, 16, 16, 8)
	rd.compute_list_end()
