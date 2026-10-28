@tool
## Handles the compute pipeline for wave spectra generation and inverse FFT.
class_name WaveGenerator
extends Node

## Emitted when GPU resources and cascade textures have been fully allocated.
signal textures_created(displacement_rid: RID, normal_rid: RID)

## Gravitational acceleration constant used in wave dispersion mathematics.
const G: float = 9.81
## Assumed water depth in meters for finite-depth dispersion calculations.
const DEPTH: float = 20.0

## Pre-allocated compute pipeline and descriptor keys.
const KEY_SPECTRUM: StringName = &"spectrum"
const KEY_BUTTERFLY: StringName = &"butterfly_factors"
const KEY_FFT_BUFFER: StringName = &"fft_buffer"
const KEY_DISPLACEMENT: StringName = &"displacement_map"
const KEY_NORMAL: StringName = &"normal_map"
const KEY_DOWNSAMPLED: StringName = &"downsampled_map"

const PIPE_SPECTRUM_COMPUTE: StringName = &"spectrum_compute"
const PIPE_SPECTRUM_MODULATE: StringName = &"spectrum_modulate"
const PIPE_FFT_BUTTERFLY: StringName = &"fft_butterfly"
const PIPE_FFT_COMPUTE: StringName = &"fft_compute"
const PIPE_TRANSPOSE: StringName = &"transpose"
const PIPE_FFT_UNPACK: StringName = &"fft_unpack"
const PIPE_DOWNSAMPLE: StringName = &"downsample"

## Resolution of the generated wave maps.
var map_size: int
## Resolution of the downsampled CPU map used for buoyancy queries.
var cpu_map_size: int = 128
## Compute rendering context wrapping [RenderingDevice] operations.
var context: RenderingContext
## Cache holding compiled compute pipelines.
var pipelines: Dictionary[StringName, Callable] = {}
## Cache holding texture and buffer descriptors.
var descriptors: Dictionary[StringName, RenderingContext.Descriptor] = {}
## Cached cascade parameters passed down from the parent ocean simulation.
var pass_parameters: Array[WaveCascadeParameters] = []
## Tracks whether the compute context and descriptors are allocated and ready.
var is_initialized: bool = false


## Disables per-frame node polling in favor of parent-driven lockstep updates.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)


## Releases GPU context when leaving tree to avoid dangling RD resources.
func _exit_tree() -> void:
	is_initialized = false
	pipelines.clear()
	descriptors.clear()
	if context:
		context.free()
		context = null


## Cleans up allocated rendering context memory when deleted.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if context:
			context.free()
			context = null


## Allocates GPU textures, buffers, and compute pipelines for the wave system.
func init_gpu(num_cascades: int) -> void:
	is_initialized = false
	if context:
		context.free()
		context = null
	pipelines.clear()
	descriptors.clear()

	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if not rd:
		return

	context = RenderingContext.create(rd)
	var spectrum_compute_shader: RID = context.load_shader(
		"res://dynamic_ocean/shaders/compute/spectrum_compute.glsl"
	)
	var fft_butterfly_shader: RID = context.load_shader(
		"res://dynamic_ocean/shaders/compute/fft_butterfly.glsl"
	)
	var spectrum_modulate_shader: RID = context.load_shader(
		"res://dynamic_ocean/shaders/compute/spectrum_modulate.glsl"
	)
	var fft_compute_shader: RID = context.load_shader(
		"res://dynamic_ocean/shaders/compute/fft_compute.glsl"
	)
	var transpose_shader: RID = context.load_shader(
		"res://dynamic_ocean/shaders/compute/transpose.glsl"
	)
	var fft_unpack_shader: RID = context.load_shader(
		"res://dynamic_ocean/shaders/compute/fft_unpack.glsl"
	)
	var downsample_shader: RID = context.load_shader(
		"res://dynamic_ocean/shaders/compute/downsample_compute.glsl"
	)

	var dims: Vector2i = Vector2i(map_size, map_size)
	var num_fft_stages: int = int(log(float(map_size)) / log(2.0))
	var cpu_dims: Vector2i = Vector2i(cpu_map_size, cpu_map_size)

	descriptors[KEY_SPECTRUM] = context.create_texture(
		dims,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT,
		num_cascades
	)
	descriptors[KEY_BUTTERFLY] = context.create_storage_buffer(num_fft_stages * map_size * 4 * 4)
	descriptors[KEY_FFT_BUFFER] = context.create_storage_buffer(
		num_cascades * map_size * map_size * 4 * 2 * 2 * 4
	)
	descriptors[KEY_DISPLACEMENT] = context.create_texture(
		dims,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		(
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		),
		num_cascades
	)
	descriptors[KEY_NORMAL] = context.create_texture(
		dims,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		(
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		),
		num_cascades
	)
	descriptors[KEY_DOWNSAMPLED] = context.create_texture(
		cpu_dims,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT,
		num_cascades
	)

	var spectrum_set: RID = context.create_descriptor_set(
		[descriptors[KEY_SPECTRUM]], spectrum_compute_shader, 0
	)
	var spectrum_modulate_set_0: RID = context.create_descriptor_set(
		[descriptors[KEY_SPECTRUM]], spectrum_modulate_shader, 0
	)
	var spectrum_modulate_set_1: RID = context.create_descriptor_set(
		[descriptors[KEY_FFT_BUFFER]], spectrum_modulate_shader, 1
	)
	var fft_butterfly_set: RID = context.create_descriptor_set(
		[descriptors[KEY_BUTTERFLY]], fft_butterfly_shader, 0
	)
	var fft_compute_set: RID = context.create_descriptor_set(
		[descriptors[KEY_BUTTERFLY], descriptors[KEY_FFT_BUFFER]], fft_compute_shader, 0
	)
	var transpose_set: RID = context.create_descriptor_set(
		[descriptors[KEY_BUTTERFLY], descriptors[KEY_FFT_BUFFER]], transpose_shader, 0
	)
	var unpack_set_0: RID = context.create_descriptor_set(
		[descriptors[KEY_DISPLACEMENT], descriptors[KEY_NORMAL]], fft_unpack_shader, 0
	)
	var unpack_set_1: RID = context.create_descriptor_set(
		[descriptors[KEY_FFT_BUFFER]], fft_unpack_shader, 1
	)
	var downsample_set: RID = context.create_descriptor_set(
		[descriptors[KEY_DISPLACEMENT], descriptors[KEY_DOWNSAMPLED]], downsample_shader, 0
	)

	var group_16: int = int(map_size / 16.0)
	var group_32: int = int(map_size / 32.0)
	var group_butterfly: int = maxi(1, int(map_size / 2.0 / 64.0))
	var group_cpu: int = int(cpu_map_size / 16.0)

	pipelines[PIPE_SPECTRUM_COMPUTE] = context.create_pipeline(
		[group_16, group_16, 1], [spectrum_set], spectrum_compute_shader
	)
	pipelines[PIPE_SPECTRUM_MODULATE] = context.create_pipeline(
		[group_16, group_16, 1],
		[spectrum_modulate_set_0, spectrum_modulate_set_1],
		spectrum_modulate_shader
	)
	pipelines[PIPE_FFT_BUTTERFLY] = context.create_pipeline(
		[group_butterfly, num_fft_stages, 1], [fft_butterfly_set], fft_butterfly_shader
	)
	pipelines[PIPE_FFT_COMPUTE] = context.create_pipeline(
		[1, map_size, 4], [fft_compute_set], fft_compute_shader
	)
	pipelines[PIPE_TRANSPOSE] = context.create_pipeline(
		[group_32, group_32, 4], [transpose_set], transpose_shader
	)
	pipelines[PIPE_FFT_UNPACK] = context.create_pipeline(
		[group_16, group_16, 1], [unpack_set_0, unpack_set_1], fft_unpack_shader
	)
	pipelines[PIPE_DOWNSAMPLE] = context.create_pipeline(
		[group_cpu, group_cpu, 1], [downsample_set], downsample_shader
	)

	var compute_list: int = context.compute_list_begin()
	pipelines[PIPE_FFT_BUTTERFLY].call(context, compute_list)
	context.compute_list_end()

	is_initialized = true
	var disp_desc: RenderingContext.Descriptor = descriptors[KEY_DISPLACEMENT]
	var norm_desc: RenderingContext.Descriptor = descriptors[KEY_NORMAL]
	textures_created.emit(disp_desc.rid, norm_desc.rid)


## Updates cascade timing and dispatches all cascades in a single compute list.
func update(delta: float, parameters: Array[WaveCascadeParameters]) -> void:
	if parameters.is_empty():
		return

	if not is_initialized or pipelines.is_empty():
		init_gpu(maxi(2, parameters.size()))
		return

	pass_parameters = parameters
	var compute_list: int = context.compute_list_begin()

	for i: int in range(parameters.size()):
		var params: WaveCascadeParameters = parameters[i]
		if params == null:
			continue

		var f_amount: float = float(params.foam_amount)
		params.time += delta
		params.foam_grow_rate = delta * f_amount * 7.5
		params.foam_decay_rate = delta * maxf(0.5, 10.0 - f_amount) * 1.15
		_update(compute_list, i, parameters)

	context.compute_list_end()


## Calculates the JONSWAP wave energy scale factor.
func jonswap_alpha(wind_speed: float = 20.0, fetch_length: float = 550e3) -> float:
	return 0.076 * pow(pow(wind_speed, 2.0) / (fetch_length * G), 0.22)


## Calculates the JONSWAP peak angular frequency.
func jonswap_peak_angular_frequency(wind_speed: float = 20.0, fetch_length: float = 550e3) -> float:
	return 22.0 * pow((G * G) / (wind_speed * fetch_length), 1.0 / 3.0)


## Executes compute passes for an individual wave cascade layer.
func _update(
	compute_list: int, cascade_index: int, params_array: Array[WaveCascadeParameters]
) -> void:
	var params: WaveCascadeParameters = params_array[cascade_index]

	if params.should_generate_spectrum:
		var alpha: float = jonswap_alpha(float(params.wind_speed), float(params.fetch_length) * 1e3)
		var omega: float = jonswap_peak_angular_frequency(
			float(params.wind_speed), float(params.fetch_length) * 1e3
		)

		(
			pipelines[PIPE_SPECTRUM_COMPUTE]
			. call(
				context,
				compute_list,
				(
					RenderingContext
					. create_push_constant(
						[
							int(params.spectrum_seed.x),
							int(params.spectrum_seed.y),
							float(params.tile_length.x),
							float(params.tile_length.y),
							float(alpha),
							float(omega),
							float(params.wind_speed),
							float(deg_to_rad(float(params.wind_direction))),
							float(DEPTH),
							float(params.swell),
							float(params.detail),
							float(params.spread),
							int(cascade_index),
							0.0,
							0.0,
							0.0,
						]
					)
				)
			)
		)
		context.compute_list_add_barrier(compute_list)
		params.should_generate_spectrum = false

	(
		pipelines[PIPE_SPECTRUM_MODULATE]
		. call(
			context,
			compute_list,
			(
				RenderingContext
				. create_push_constant(
					[
						float(params.tile_length.x),
						float(params.tile_length.y),
						float(DEPTH),
						float(params.time),
						int(cascade_index),
						float(params.loop_period),
						0.0,
						0.0,
					]
				)
			)
		)
	)
	context.compute_list_add_barrier(compute_list)

	var fft_push_constant: PackedByteArray = RenderingContext.create_push_constant(
		[int(cascade_index), 0.0, 0.0, 0.0]
	)

	pipelines[PIPE_FFT_COMPUTE].call(context, compute_list, fft_push_constant)
	context.compute_list_add_barrier(compute_list)
	pipelines[PIPE_TRANSPOSE].call(context, compute_list, fft_push_constant)
	context.compute_list_add_barrier(compute_list)
	pipelines[PIPE_FFT_COMPUTE].call(context, compute_list, fft_push_constant)
	context.compute_list_add_barrier(compute_list)

	(
		pipelines[PIPE_FFT_UNPACK]
		. call(
			context,
			compute_list,
			(
				RenderingContext
				. create_push_constant(
					[
						int(cascade_index),
						float(params.whitecap),
						float(params.foam_grow_rate),
						float(params.foam_decay_rate),
					]
				)
			)
		)
	)
	context.compute_list_add_barrier(compute_list)

	var ratio: float = float(map_size) / float(cpu_map_size)
	pipelines[PIPE_DOWNSAMPLE].call(
		context,
		compute_list,
		RenderingContext.create_push_constant([int(cascade_index), float(ratio), 0.0, 0.0])
	)
	context.compute_list_add_barrier(compute_list)
