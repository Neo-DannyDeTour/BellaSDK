## Manages GPU compute dispatches and bullet hole simulation buffers for [FogVolume].
extends Node

## Maximum number of concurrent bullet holes tracked in the compute buffer.
const MAX_HOLES: int = 50

## Byte size of a single hole data struct (8 floats: 32 bytes) in std430 layout.
const HOLE_STRIDE_BYTES: int = 32

## Total byte capacity of the GPU storage buffer holding bullet hole data.
const BUFFER_SIZE: int = MAX_HOLES * HOLE_STRIDE_BYTES

## Total byte capacity of the push constants buffer (20 floats * 4 bytes).
const PUSH_CONSTANTS_SIZE: int = 80

@export_group("System Controls")
## Time in seconds before a bullet hole completely heals and dissipates.
@export var heal_time_seconds: float = 4.0

## Radius around the player that dynamically clears volumetric smoke.
@export var player_trail_radius: float = 3.5

@export_group("Cinematic Pellet Effects")
## Intensity factor for clearing smoke inside bullet cavities.
@export_range(0.0, 1.0) var hole_clear_intensity: float = 0.8

## Strength of turbulent rotational swirls around bullet cavities.
@export var swirl_strength: float = 1.8

## Spatial frequency of the rotational turbulence around bullet cavities.
@export var swirl_frequency: float = 0.5

@export_group("Optimizations")
## Precomputed 3D noise texture used for volumetric turbulence.
@export var precomputed_noise: Texture3D

## Pre-allocated byte buffer for GPU storage buffer updates without heap allocations.
var _hole_byte_buffer: PackedByteArray = PackedByteArray()

## Pre-allocated byte buffer for push constant data dispatched to [RenderingDevice].
var _push_constants_buffer: PackedByteArray = PackedByteArray()

## Flat array storing elapsed lifetimes in seconds for each active hole.
var _hole_lifetimes: PackedFloat32Array = PackedFloat32Array()

## Current count of active bullet holes tracked in the buffer.
var _active_hole_count: int = 0

## Cached world position of the player for local fog clearing.
var current_player_pos: Vector3 = Vector3.ZERO

## Total accumulated simulation time in seconds.
var global_time: float = 0.0

## The [RenderingDevice] used for compute operations. Needs manual cleanup.
var rd: RenderingDevice

## The compiled compute shader [RID]. Needs manual cleanup.
var shader: RID

## The compute pipeline instance [RID]. Needs manual cleanup.
var pipeline: RID

## The 3D texture [RID] used for density storage. Needs manual cleanup.
var texture_rid: RID

## The storage buffer [RID] for hole data. Needs manual cleanup.
var buffer_rid: RID

## The uniform set [RID] binding all resources. Freed first in cleanup.
var uniform_set: RID

## Holds the GPU texture [RID] for generated noise. Needs manual cleanup.
var noise_rd_rid: RID

## Holds the GPU sampler [RID]. Needs manual cleanup.
var sampler_rid: RID

## The currently bound [FogVolume] receiving computed smoke density.
var active_fog_volume: FogVolume

## Indicates whether the compute pipeline is ready for dispatch.
var is_initialized: bool = false

## The [Texture3DRD] wrapper bridging the compute texture to materials.
var godot_texture: Texture3DRD


## Initializes the compute buffer, textures, and pipeline on [Node] ready.
func _ready() -> void:
	print("SmokeManager: Initializing smoke manager node.")
	rd = RenderingServer.get_rendering_device()

	_hole_byte_buffer.resize(BUFFER_SIZE)
	_hole_byte_buffer.fill(0)
	_push_constants_buffer.resize(PUSH_CONSTANTS_SIZE)
	_push_constants_buffer.fill(0)
	_hole_lifetimes.resize(MAX_HOLES)
	_hole_lifetimes.fill(0.0)

	if precomputed_noise == null:
		precomputed_noise = preload("res://vfx/smoke_noise_3d.tres") as Texture3D

	assert(precomputed_noise != null, "SmokeManager requires smoke_noise_3d.tres!")

	while not precomputed_noise.get_rid().is_valid():
		await precomputed_noise.changed

	if DisplayServer.get_name() == "headless":
		print("SmokeManager: Headless mode detected, skipping GPU initialization.")
		return

	_initialize_gpu()


## Creates a [RenderingDevice] texture [RID] from a [Texture3D] resource.
func _create_rd_noise_texture(tex: Texture3D) -> RID:
	print("SmokeManager: _create_rd_noise_texture() called.")
	var images: Array[Image] = tex.get_data()
	if images.is_empty():
		push_error("SmokeManager: Noise texture is empty!")
		return RID()

	var base_image: Image = images[0]
	var fmt: RDTextureFormat = RDTextureFormat.new()
	fmt.width = base_image.get_width()
	fmt.height = base_image.get_height()
	fmt.depth = images.size()
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	)

	var bytes: PackedByteArray = PackedByteArray()
	for img: Image in images:
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		bytes.append_array(img.get_data())

	var view: RDTextureView = RDTextureView.new()
	return rd.texture_create(fmt, view, [bytes])


## Compiles compute shader, initializes textures, buffers, and uniform sets.
func _initialize_gpu() -> void:
	print("SmokeManager: _initialize_gpu() called.")
	const SHADER_FILE: RDShaderFile = preload("res://vfx/smoke_compute.glsl")
	var shader_spirv: RDShaderSPIRV = SHADER_FILE.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

	var fmt: RDTextureFormat = RDTextureFormat.new()
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

	var view: RDTextureView = RDTextureView.new()
	texture_rid = rd.texture_create(fmt, view)

	godot_texture = Texture3DRD.new()
	godot_texture.texture_rd_rid = texture_rid

	buffer_rid = rd.storage_buffer_create(BUFFER_SIZE, _hole_byte_buffer)

	noise_rd_rid = _create_rd_noise_texture(precomputed_noise)
	assert(noise_rd_rid.is_valid(), "Failed to create GPU noise texture!")

	var sampler_state: RDSamplerState = RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR

	sampler_rid = rd.sampler_create(sampler_state)

	var tex_uniform: RDUniform = RDUniform.new()
	tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	tex_uniform.binding = 0
	tex_uniform.add_id(texture_rid)

	var buf_uniform: RDUniform = RDUniform.new()
	buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	buf_uniform.binding = 1
	buf_uniform.add_id(buffer_rid)

	var noise_uniform: RDUniform = RDUniform.new()
	noise_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	noise_uniform.binding = 2
	noise_uniform.add_id(sampler_rid)
	noise_uniform.add_id(noise_rd_rid)

	uniform_set = rd.uniform_set_create([tex_uniform, buf_uniform, noise_uniform], shader, 0)
	assert(uniform_set.is_valid(), "SmokeManager: uniform_set_create failed.")

	is_initialized = true

	if is_instance_valid(active_fog_volume):
		active_fog_volume.assign_compute_texture(godot_texture)


## Handles engine notifications to clean up GPU resources on deletion.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_gpu()


## Releases all allocated [RenderingDevice] resources and [RID] instances.
func _cleanup_gpu() -> void:
	print("SmokeManager: _cleanup_gpu() called.")
	if not rd:
		return
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	if shader.is_valid():
		rd.free_rid(shader)
	if buffer_rid.is_valid():
		rd.free_rid(buffer_rid)
	if texture_rid.is_valid():
		rd.free_rid(texture_rid)
	if noise_rd_rid.is_valid():
		rd.free_rid(noise_rd_rid)
	if sampler_rid.is_valid():
		rd.free_rid(sampler_rid)


## Binds an active [FogVolume] and assigns the computed [Texture3DRD].
func register_fog_volume(volume: FogVolume) -> void:
	print("SmokeManager: register_fog_volume() called with: ", volume.name)
	active_fog_volume = volume
	if is_initialized and is_instance_valid(godot_texture):
		if volume.has_method("assign_compute_texture"):
			volume.assign_compute_texture(godot_texture)


## Clears the registered [FogVolume] reference if it matches the current volume.
func clear_fog_volume(volume: FogVolume) -> void:
	print("SmokeManager: clear_fog_volume() called.")
	if active_fog_volume == volume:
		active_fog_volume = null


## Updates the cached player position used for volumetric clearing.
func update_player_position(pos: Vector3) -> void:
	current_player_pos = pos


## Adds a bullet hole cavity by writing directly into pre-allocated memory.
func add_bullet_hole(start: Vector3, dir: Vector3, length: float, radius: float = 1.0) -> void:
	print("SmokeManager: add_bullet_hole() called.")
	var target_idx: int = _active_hole_count

	if _active_hole_count >= MAX_HOLES:
		var oldest_idx: int = 0
		var max_age: float = -1.0
		for i: int in range(_active_hole_count):
			if _hole_lifetimes[i] > max_age:
				max_age = _hole_lifetimes[i]
				oldest_idx = i
		target_idx = oldest_idx
	else:
		_active_hole_count += 1

	_hole_lifetimes[target_idx] = 0.0
	var end_pos: Vector3 = start + (dir * length)
	var offset: int = target_idx * HOLE_STRIDE_BYTES

	_hole_byte_buffer.encode_float(offset, start.x)
	_hole_byte_buffer.encode_float(offset + 4, start.y)
	_hole_byte_buffer.encode_float(offset + 8, start.z)
	_hole_byte_buffer.encode_float(offset + 12, radius)
	_hole_byte_buffer.encode_float(offset + 16, end_pos.x)
	_hole_byte_buffer.encode_float(offset + 20, end_pos.y)
	_hole_byte_buffer.encode_float(offset + 24, end_pos.z)
	_hole_byte_buffer.encode_float(offset + 28, 0.0)


## Updates hole lifetimes and dispatches the compute pass per frame.
func _process(delta: float) -> void:
	if not is_initialized:
		return

	global_time += delta

	var i: int = _active_hole_count - 1
	while i >= 0:
		_hole_lifetimes[i] += delta
		if _hole_lifetimes[i] >= heal_time_seconds:
			var last_idx: int = _active_hole_count - 1
			if i < last_idx:
				_hole_lifetimes[i] = _hole_lifetimes[last_idx]
				var src_offset: int = last_idx * HOLE_STRIDE_BYTES
				var dst_offset: int = i * HOLE_STRIDE_BYTES
				for b: int in range(HOLE_STRIDE_BYTES):
					_hole_byte_buffer[dst_offset + b] = _hole_byte_buffer[src_offset + b]
			_active_hole_count -= 1
		else:
			var norm_age: float = _hole_lifetimes[i] / heal_time_seconds
			_hole_byte_buffer.encode_float(i * HOLE_STRIDE_BYTES + 28, norm_age)
		i -= 1

	if not is_instance_valid(active_fog_volume):
		return
	if not active_fog_volume.is_inside_tree():
		return

	var safe_fog_size: Vector3 = active_fog_volume.size
	var safe_fog_pos: Vector3 = active_fog_volume.global_position
	var is_even_frame: bool = Engine.get_process_frames() % 2 == 0

	RenderingServer.call_on_render_thread(
		_dispatch_to_compute_shader.bind(
			delta,
			_active_hole_count,
			safe_fog_size,
			safe_fog_pos,
			current_player_pos,
			global_time,
			is_even_frame
		)
	)


## Dispatches the compute shader pass on the render thread.
func _dispatch_to_compute_shader(
	delta: float,
	holes_count: int,
	fog_size: Vector3,
	fog_pos: Vector3,
	player_pos: Vector3,
	current_time: float,
	is_even_frame: bool
) -> void:
	if not is_initialized or not uniform_set.is_valid() or fog_size == Vector3.ZERO:
		return

	if holes_count > 0:
		var bytes_to_upload: int = holes_count * HOLE_STRIDE_BYTES
		rd.buffer_update(buffer_rid, 0, bytes_to_upload, _hole_byte_buffer)

	var grid_pos: Vector3 = fog_pos - (fog_size / 2.0)
	var heal_rate: float = 1.0 / heal_time_seconds
	var z_offset: float = 64.0 if is_even_frame else 0.0

	_push_constants_buffer.encode_float(0, player_pos.x)
	_push_constants_buffer.encode_float(4, player_pos.y)
	_push_constants_buffer.encode_float(8, player_pos.z)
	_push_constants_buffer.encode_float(12, float(holes_count))
	_push_constants_buffer.encode_float(16, grid_pos.x)
	_push_constants_buffer.encode_float(20, grid_pos.y)
	_push_constants_buffer.encode_float(24, grid_pos.z)
	_push_constants_buffer.encode_float(28, delta * 2.0)
	_push_constants_buffer.encode_float(32, fog_size.x)
	_push_constants_buffer.encode_float(36, fog_size.y)
	_push_constants_buffer.encode_float(40, fog_size.z)
	_push_constants_buffer.encode_float(44, current_time)
	_push_constants_buffer.encode_float(48, hole_clear_intensity)
	_push_constants_buffer.encode_float(52, swirl_strength)
	_push_constants_buffer.encode_float(56, swirl_frequency)
	_push_constants_buffer.encode_float(60, player_trail_radius)
	_push_constants_buffer.encode_float(64, z_offset)
	_push_constants_buffer.encode_float(68, heal_rate)
	_push_constants_buffer.encode_float(72, 0.0)
	_push_constants_buffer.encode_float(76, 0.0)

	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, _push_constants_buffer, PUSH_CONSTANTS_SIZE)
	rd.compute_list_dispatch(compute_list, 16, 16, 8)
	rd.compute_list_end()
