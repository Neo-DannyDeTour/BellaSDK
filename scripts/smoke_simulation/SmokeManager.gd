extends Node

const MAX_HOLES: int = 50
const BUFFER_SIZE: int = MAX_HOLES * 32

@export_group("System Controls")
@export var heal_time_seconds: float = 4.0
@export var player_trail_radius: float = 3.5

@export_group("Cinematic Pellet Effects")
@export_range(0.0, 1.0) var hole_clear_intensity: float = 0.8
@export var swirl_strength: float = 1.8
@export var swirl_frequency: float = 0.5

@export_group("Optimizations")
@export var precomputed_noise: Texture3D

var active_holes: Array[Dictionary] = []
var current_player_pos: Vector3 = Vector3.ZERO
var global_time: float = 0.0

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var texture_rid: RID
var buffer_rid: RID
var uniform_set: RID
var active_fog_volume: FogVolume
var is_initialized: bool = false


func _ready() -> void:
	rd = RenderingServer.get_rendering_device()

	if precomputed_noise == null:
		precomputed_noise = load("res://scripts/smoke_simulation/smoke_noise_3d.tres") as Texture3D

	assert(precomputed_noise != null, "SmokeManager requires smoke_noise_3d.tres to be valid!")

	# THE FINAL FIX: Check the raw internal RID instead of get_data().
	# If the RID is invalid, the background thread is still generating the noise.
	while not precomputed_noise.get_rid().is_valid():
		await precomputed_noise.changed

	_initialize_gpu()


# ---------------------------------------------------------
# Extracts raw bytes from Godot's Texture3D to create a
# dedicated Vulkan RDTexture, avoiding sync/flag errors.
# ---------------------------------------------------------
func _create_rd_noise_texture(tex: Texture3D) -> RID:
	var images: Array[Image] = tex.get_data()
	if images.is_empty():
		push_error("SmokeManager: Noise texture is empty!")
		return RID()

	var base_image: Image = images[0]
	var fmt := RDTextureFormat.new()
	fmt.width = base_image.get_width()
	fmt.height = base_image.get_height()
	fmt.depth = images.size()
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	)

	var bytes := PackedByteArray()
	for img: Image in images:
		# Force uniform RGBA8 format mapping to match our RDTextureFormat
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		bytes.append_array(img.get_data())

	var view := RDTextureView.new()
	return rd.texture_create(fmt, view, [bytes])


func _initialize_gpu() -> void:
	var shader_file: RDShaderFile = load("res://scripts/smoke_simulation/smoke_compute.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

	# 1. Output 3D Storage Image
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

	# 2. Holes Data Buffer
	var empty_bytes := PackedByteArray()
	empty_bytes.resize(BUFFER_SIZE)
	buffer_rid = rd.storage_buffer_create(BUFFER_SIZE, empty_bytes)

	# 3. Dedicated Noise Sampler and Texture
	var noise_rd_rid: RID = _create_rd_noise_texture(precomputed_noise)
	assert(noise_rd_rid.is_valid(), "Failed to create GPU noise texture!")

	var sampler_state := RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR

	var sampler_rid: RID = rd.sampler_create(sampler_state)

	# --- Bind Uniforms ---
	var tex_uniform := RDUniform.new()
	tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	tex_uniform.binding = 0
	tex_uniform.add_id(texture_rid)

	var buf_uniform := RDUniform.new()
	buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	buf_uniform.binding = 1
	buf_uniform.add_id(buffer_rid)

	var noise_uniform := RDUniform.new()
	noise_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	noise_uniform.binding = 2
	noise_uniform.add_id(sampler_rid)
	noise_uniform.add_id(noise_rd_rid)

	uniform_set = rd.uniform_set_create([tex_uniform, buf_uniform, noise_uniform], shader, 0)

	# Catch shader layout mismatches immediately upon initialization
	assert(
		uniform_set.is_valid(),
		"SmokeManager: uniform_set_create returned null. Check your GLSL layouts!"
	)

	is_initialized = true


func update_player_position(pos: Vector3) -> void:
	current_player_pos = pos


func add_bullet_hole(start: Vector3, dir: Vector3, length: float, radius: float = 1.0) -> void:
	if active_holes.size() >= MAX_HOLES:
		active_holes.pop_front()

	active_holes.append(
		{"start": start, "end": start + (dir * length), "radius": radius, "time_alive": 0.0}
	)


func _process(delta: float) -> void:
	if not is_initialized:
		return

	global_time += delta

	for i: int in range(active_holes.size() - 1, -1, -1):
		var hole: Dictionary = active_holes[i]
		hole["time_alive"] += delta
		if hole["time_alive"] > heal_time_seconds:
			active_holes.remove_at(i)

	var safe_holes: Array[Dictionary] = active_holes.duplicate(true)
	var safe_fog_size: Vector3 = Vector3.ZERO
	var safe_fog_pos: Vector3 = Vector3.ZERO

	if is_instance_valid(active_fog_volume) and active_fog_volume.is_inside_tree():
		safe_fog_size = active_fog_volume.size
		safe_fog_pos = active_fog_volume.global_position

	var safe_player_pos: Vector3 = current_player_pos
	var safe_time: float = global_time

	RenderingServer.call_on_render_thread(
		_dispatch_to_compute_shader.bind(
			delta, safe_holes, safe_fog_size, safe_fog_pos, safe_player_pos, safe_time
		)
	)


func _dispatch_to_compute_shader(
	delta: float,
	compute_holes: Array[Dictionary],
	fog_size: Vector3,
	fog_pos: Vector3,
	player_pos: Vector3,
	current_time: float
) -> void:
	# Double-check initialization to prevent runtime bind crashes
	if not is_initialized or not uniform_set.is_valid():
		return

	if fog_size == Vector3.ZERO:
		return

	var grid_pos: Vector3 = fog_pos - (fog_size / 2.0)
	var hole_data := PackedFloat32Array()
	var holes_to_process: int = mini(compute_holes.size(), MAX_HOLES)

	for i: int in range(holes_to_process):
		var hole: Dictionary = compute_holes[i]

		hole_data.append(hole.start.x)
		hole_data.append(hole.start.y)
		hole_data.append(hole.start.z)
		hole_data.append(hole.radius)
		hole_data.append(hole.end.x)
		hole_data.append(hole.end.y)
		hole_data.append(hole.end.z)
		hole_data.append(hole.time_alive)

	var hole_bytes: PackedByteArray = hole_data.to_byte_array()
	if hole_bytes.size() > 0:
		rd.buffer_update(buffer_rid, 0, hole_bytes.size(), hole_bytes)

	var heal_rate: float = 1.0 / heal_time_seconds
	var is_even_frame: bool = Engine.get_process_frames() % 2 == 0
	var z_offset: float = 64.0 if is_even_frame else 0.0

	var push_constants_array := PackedFloat32Array(
		[
			player_pos.x,
			player_pos.y,
			player_pos.z,
			float(holes_to_process),
			grid_pos.x,
			grid_pos.y,
			grid_pos.z,
			delta * 2.0,
			fog_size.x,
			fog_size.y,
			fog_size.z,
			current_time,
			hole_clear_intensity,
			swirl_strength,
			swirl_frequency,
			player_trail_radius,
			z_offset,
			heal_rate,
			0.0,
			0.0
		]
	)

	var push_constants_bytes: PackedByteArray = push_constants_array.to_byte_array()

	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

	rd.compute_list_set_push_constant(
		compute_list, push_constants_bytes, push_constants_bytes.size()
	)

	rd.compute_list_dispatch(compute_list, 16, 16, 8)
	rd.compute_list_end()
