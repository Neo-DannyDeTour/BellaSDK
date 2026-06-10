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
var godot_texture: Texture3DRD


func _ready() -> void:
	print("SmokeManager: _ready() called. Initializing atmospheric manager.")
	rd = RenderingServer.get_rendering_device()

	if precomputed_noise == null:
		precomputed_noise = preload("res://vfx/smoke_noise_3d.tres") as Texture3D

	assert(precomputed_noise != null, "SmokeManager requires smoke_noise_3d.tres to be valid!")

	while not precomputed_noise.get_rid().is_valid():
		await precomputed_noise.changed

	_initialize_gpu()


func _create_rd_noise_texture(tex: Texture3D) -> RID:
	print("SmokeManager: _create_rd_noise_texture() called.")
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
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		bytes.append_array(img.get_data())

	var view := RDTextureView.new()
	return rd.texture_create(fmt, view, [bytes])


func _initialize_gpu() -> void:
	print("SmokeManager: _initialize_gpu() called.")
	var shader_file: RDShaderFile = preload("res://vfx/smoke_compute.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

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

	# --- THE MISSING BRIDGE ---
	# Wrap the raw RenderingDevice texture so Godot materials can read it
	godot_texture = Texture3DRD.new()
	godot_texture.texture_rd_rid = texture_rid

	var empty_bytes := PackedByteArray()
	empty_bytes.resize(BUFFER_SIZE)
	buffer_rid = rd.storage_buffer_create(BUFFER_SIZE, empty_bytes)

	var noise_rd_rid: RID = _create_rd_noise_texture(precomputed_noise)
	assert(noise_rd_rid.is_valid(), "Failed to create GPU noise texture!")

	var sampler_state := RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR

	var sampler_rid: RID = rd.sampler_create(sampler_state)

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
	assert(uniform_set.is_valid(), "SmokeManager: uniform_set_create returned null.")

	is_initialized = true


func register_fog_volume(volume: FogVolume) -> void:
	print("SmokeManager: register_fog_volume() called with volume: " + volume.name)
	active_fog_volume = volume
	if is_instance_valid(godot_texture) and volume.has_method("assign_compute_texture"):
		volume.assign_compute_texture(godot_texture)


func clear_fog_volume(volume: FogVolume) -> void:
	print("SmokeManager: clear_fog_volume() called.")
	if active_fog_volume == volume:
		active_fog_volume = null


func update_player_position(pos: Vector3) -> void:
	current_player_pos = pos


func add_bullet_hole(start: Vector3, dir: Vector3, length: float, radius: float = 1.0) -> void:
	print("SmokeManager: add_bullet_hole() called.")
	if active_holes.size() >= MAX_HOLES:
		active_holes.pop_front()

	active_holes.append(
		{"start": start, "end": start + (dir * length), "radius": radius, "time_alive": 0.0}
	)


func _process(delta: float) -> void:
	if not is_initialized:
		return

	global_time += delta

	# 1. Update lifetimes and prune old holes directly
	for i: int in range(active_holes.size() - 1, -1, -1):
		active_holes[i].time_alive += delta
		if active_holes[i].time_alive > heal_time_seconds:
			active_holes.remove_at(i)

	# 2. Extract safe state on MAIN THREAD
	var safe_fog_size: Vector3 = Vector3.ZERO
	var safe_fog_pos: Vector3 = Vector3.ZERO

	if is_instance_valid(active_fog_volume) and active_fog_volume.is_inside_tree():
		safe_fog_size = active_fog_volume.size
		safe_fog_pos = active_fog_volume.global_position

	# Evaluate frames on the Main Thread to guarantee it flips properly
	var is_even_frame: bool = Engine.get_process_frames() % 2 == 0
	var holes_to_process: int = mini(active_holes.size(), MAX_HOLES)

	# 3. Pre-allocate and build buffer on MAIN THREAD to prevent Render Thread locking
	var hole_data := PackedFloat32Array()
	hole_data.resize(holes_to_process * 8)

	for i: int in range(holes_to_process):
		var hole: Dictionary = active_holes[i]
		var offset: int = i * 8
		hole_data[offset] = hole.start.x
		hole_data[offset + 1] = hole.start.y
		hole_data[offset + 2] = hole.start.z
		hole_data[offset + 3] = hole.radius
		hole_data[offset + 4] = hole.end.x
		hole_data[offset + 5] = hole.end.y
		hole_data[offset + 6] = hole.end.z
		hole_data[offset + 7] = hole.time_alive

	var safe_hole_bytes: PackedByteArray = hole_data.to_byte_array()

	# 4. Dispatch with fully prepared, thread-safe primitives
	RenderingServer.call_on_render_thread(
		_dispatch_to_compute_shader.bind(
			delta, safe_hole_bytes, holes_to_process, safe_fog_size,
			safe_fog_pos, current_player_pos, global_time, is_even_frame
		)
	)


func _dispatch_to_compute_shader(
	delta: float,
	hole_bytes: PackedByteArray,
	holes_count: int,
	fog_size: Vector3,
	fog_pos: Vector3,
	player_pos: Vector3,
	current_time: float,
	is_even_frame: bool
) -> void:
	if not is_initialized or not uniform_set.is_valid() or fog_size == Vector3.ZERO:
		return

	# Buffer updates are safe here, but we no longer allocate memory to do it
	if hole_bytes.size() > 0:
		rd.buffer_update(buffer_rid, 0, hole_bytes.size(), hole_bytes)

	var grid_pos: Vector3 = fog_pos - (fog_size / 2.0)
	var heal_rate: float = 1.0 / heal_time_seconds
	var z_offset: float = 64.0 if is_even_frame else 0.0

	var push_constants_array := PackedFloat32Array([
		player_pos.x, player_pos.y, player_pos.z,
		float(holes_count),
		grid_pos.x, grid_pos.y, grid_pos.z,
		delta * 2.0,
		fog_size.x, fog_size.y, fog_size.z,
		current_time, hole_clear_intensity, swirl_strength, swirl_frequency,
		player_trail_radius, z_offset, heal_rate, 0.0, 0.0
	])

	var push_constants_bytes: PackedByteArray = push_constants_array.to_byte_array()

	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(
		compute_list, push_constants_bytes, push_constants_bytes.size()
	)
	rd.compute_list_dispatch(compute_list, 16, 16, 8)
	rd.compute_list_end()
