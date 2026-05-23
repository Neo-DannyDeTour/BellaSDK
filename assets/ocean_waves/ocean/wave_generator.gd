@tool
class_name WaveGenerator extends Node
## Handles the compute pipeline for wave spectra generation/FFT.

const G: float = 9.81
const DEPTH: float = 20.0

var map_size: int
var cpu_map_size: int = 128  # The tiny map for CPU physics
var context: RenderingContext
var pipelines: Dictionary = {}
var descriptors: Dictionary = {}

# Generator state per invocation of `update()`.
var pass_parameters: Array[WaveCascadeParameters]
var pass_num_cascades_remaining: int


func init_gpu(num_cascades: int) -> void:
	# --- MEMORY FLUSH ---
	if context:
		context.free()
	pipelines.clear()
	descriptors.clear()

	# --- DEVICE/SHADER CREATION ---
	context = RenderingContext.create(RenderingServer.get_rendering_device())
	var spectrum_compute_shader: RID = context.load_shader(
		"res://assets/ocean_waves/shaders/compute/spectrum_compute.glsl"
	)
	var fft_butterfly_shader: RID = context.load_shader("res://assets/ocean_waves/shaders/compute/fft_butterfly.glsl")
	var spectrum_modulate_shader: RID = context.load_shader(
		"res://assets/ocean_waves/shaders/compute/spectrum_modulate.glsl"
	)
	var fft_compute_shader: RID = context.load_shader("res://assets/ocean_waves/shaders/compute/fft_compute.glsl")
	var transpose_shader: RID = context.load_shader("res://assets/ocean_waves/shaders/compute/transpose.glsl")
	var fft_unpack_shader: RID = context.load_shader("res://assets/ocean_waves/shaders/compute/fft_unpack.glsl")
	var downsample_shader: RID = context.load_shader("res://assets/ocean_waves/shaders/compute/downsample_compute.glsl")

	# --- DESCRIPTOR PREPARATION ---
	var dims: Vector2i = Vector2i(map_size, map_size)
	var num_fft_stages: int = int(log(float(map_size)) / log(2.0))
	var cpu_dims: Vector2i = Vector2i(cpu_map_size, cpu_map_size)

	descriptors[&"spectrum"] = context.create_texture(
		dims,
		RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT,
		num_cascades
	)
	descriptors[&"butterfly_factors"] = context.create_storage_buffer(num_fft_stages * map_size * 4 * 4)
	descriptors[&"fft_buffer"] = context.create_storage_buffer(num_cascades * map_size * map_size * 4 * 2 * 2 * 4)
	descriptors[&"displacement_map"] = context.create_texture(
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
	descriptors[&"normal_map"] = context.create_texture(
		dims,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		(
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		),
		num_cascades
	)
	descriptors[&"downsampled_map"] = context.create_texture(
		cpu_dims,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT,
		num_cascades
	)

	# --- STRICT DESCRIPTOR SET BINDINGS ---
	var spectrum_set: RID = context.create_descriptor_set([descriptors[&"spectrum"]], spectrum_compute_shader, 0)

	var spectrum_modulate_set_0: RID = context.create_descriptor_set(
		[descriptors[&"spectrum"]], spectrum_modulate_shader, 0
	)
	var spectrum_modulate_set_1: RID = context.create_descriptor_set(
		[descriptors[&"fft_buffer"]], spectrum_modulate_shader, 1
	)

	var fft_butterfly_set: RID = context.create_descriptor_set(
		[descriptors[&"butterfly_factors"]], fft_butterfly_shader, 0
	)
	var fft_compute_set: RID = context.create_descriptor_set(
		[descriptors[&"butterfly_factors"], descriptors[&"fft_buffer"]], fft_compute_shader, 0
	)
	var transpose_set: RID = context.create_descriptor_set(
		[descriptors[&"butterfly_factors"], descriptors[&"fft_buffer"]], transpose_shader, 0
	)

	var unpack_set_0: RID = context.create_descriptor_set(
		[descriptors[&"displacement_map"], descriptors[&"normal_map"]], fft_unpack_shader, 0
	)
	var unpack_set_1: RID = context.create_descriptor_set([descriptors[&"fft_buffer"]], fft_unpack_shader, 1)

	var downsample_set: RID = context.create_descriptor_set(
		[descriptors[&"displacement_map"], descriptors[&"downsampled_map"]], downsample_shader, 0
	)

	# --- COMPUTE PIPELINE CREATION ---
	pipelines[&"spectrum_compute"] = context.create_pipeline(
		[map_size / 16.0, map_size / 16.0, 1], [spectrum_set], spectrum_compute_shader
	)
	pipelines[&"spectrum_modulate"] = context.create_pipeline(
		[map_size / 16.0, map_size / 16.0, 1],
		[spectrum_modulate_set_0, spectrum_modulate_set_1],
		spectrum_modulate_shader
	)
	pipelines[&"fft_butterfly"] = context.create_pipeline(
		[map_size / 2.0 / 64.0, num_fft_stages, 1], [fft_butterfly_set], fft_butterfly_shader
	)
	pipelines[&"fft_compute"] = context.create_pipeline([1, map_size, 4], [fft_compute_set], fft_compute_shader)
	pipelines[&"transpose"] = context.create_pipeline(
		[map_size / 32.0, map_size / 32.0, 4], [transpose_set], transpose_shader
	)
	pipelines[&"fft_unpack"] = context.create_pipeline(
		[map_size / 16.0, map_size / 16.0, 1], [unpack_set_0, unpack_set_1], fft_unpack_shader
	)
	pipelines[&"downsample"] = context.create_pipeline(
		[cpu_map_size / 16.0, cpu_map_size / 16.0, 1], [downsample_set], downsample_shader
	)

	# We only need to generate butterfly factors once for each map_size.
	var compute_list: int = context.compute_list_begin()
	pipelines[&"fft_butterfly"].call(context, compute_list)
	context.compute_list_end()


func _process(_delta: float) -> void:
	# --- NEW: Safety valve to prevent editor error spam ---
	if pipelines.is_empty() or not pipelines.has(&"spectrum_compute"):
		return

	# Update one cascade each frame for load balancing.
	if pass_num_cascades_remaining == 0:
		return
	pass_num_cascades_remaining -= 1

	var compute_list: int = context.compute_list_begin()
	_update(compute_list, pass_num_cascades_remaining, pass_parameters)
	context.compute_list_end()


func _update(compute_list: int, cascade_index: int, parameters: Array[WaveCascadeParameters]) -> void:
	var params: WaveCascadeParameters = parameters[cascade_index]

	## --- WAVE SPECTRA UPDATE ---
	if params.should_generate_spectrum:
		var alpha: float = JONSWAP_alpha(float(params.wind_speed), float(params.fetch_length) * 1e3)
		var omega: float = JONSWAP_peak_angular_frequency(float(params.wind_speed), float(params.fetch_length) * 1e3)

		# STRICT CASTING: Forces Godot to pack these as correct IEEE 754 floats and 32-bit ints
		pipelines[&"spectrum_compute"].call(
			context,
			compute_list,
			RenderingContext.create_push_constant(
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
					int(cascade_index)
				]
			)
		)
		params.should_generate_spectrum = false

	pipelines[&"spectrum_modulate"].call(
		context,
		compute_list,
		RenderingContext.create_push_constant(
			[
				float(params.tile_length.x),
				float(params.tile_length.y),
				float(DEPTH),
				float(params.time),
				int(cascade_index),
				float(params.loop_period)
			]
		)
	)

	## --- WAVE SPECTRA INVERSE FOURIER TRANSFORM ---
	var fft_push_constant: PackedByteArray = RenderingContext.create_push_constant([int(cascade_index)])
	pipelines[&"fft_compute"].call(context, compute_list, fft_push_constant)
	pipelines[&"transpose"].call(context, compute_list, fft_push_constant)

	context.compute_list_add_barrier(compute_list)

	pipelines[&"fft_compute"].call(context, compute_list, fft_push_constant)

	## --- DISPLACEMENT/NORMAL MAP UPDATE ---
	pipelines[&"fft_unpack"].call(
		context,
		compute_list,
		RenderingContext.create_push_constant(
			[int(cascade_index), float(params.whitecap), float(params.foam_grow_rate), float(params.foam_decay_rate)]
		)
	)

	# --- NEW: Run the downsampler ---
	context.compute_list_add_barrier(compute_list)
	var ratio: float = float(map_size) / float(cpu_map_size)
	pipelines[&"downsample"].call(
		context, compute_list, RenderingContext.create_push_constant([int(cascade_index), float(ratio)])
	)


func update(delta: float, parameters: Array[WaveCascadeParameters]) -> void:
	assert(parameters.size() != 0)
	if not context or pipelines.is_empty():
		init_gpu(maxi(2, parameters.size()))

	# --- NEW: STRICT SAFETY SHIELD ---
	# If the pipeline failed to compile, silently abort to prevent error spam!
	if not pipelines.has(&"spectrum_compute") or not pipelines[&"spectrum_compute"].is_valid():
		return
	# ---------------------------------

	if pass_num_cascades_remaining != 0:
		var compute_list: int = context.compute_list_begin()
		for i: int in range(pass_num_cascades_remaining):
			_update(compute_list, i, pass_parameters)
		context.compute_list_end()

	for i: int in range(parameters.size()):
		var params: WaveCascadeParameters = parameters[i]
		if params == null:
			continue

		# Force cast everything out of the old Variant/Null cache
		var f_amount: float = float(params.foam_amount)
		var f_time: float = float(params.time)

		params.time = f_time + delta
		params.foam_grow_rate = delta * f_amount * 7.5
		params.foam_decay_rate = float(delta * max(0.5, 10.0 - f_amount) * 1.15)

	pass_parameters = parameters
	pass_num_cascades_remaining = parameters.size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if context:
			context.free()


func JONSWAP_alpha(wind_speed: float = 20.0, fetch_length: float = 550e3) -> float:
	return 0.076 * pow(pow(wind_speed, 2.0) / (fetch_length * G), 0.22)


func JONSWAP_peak_angular_frequency(wind_speed: float = 20.0, fetch_length: float = 550e3) -> float:
	return 22.0 * pow((G * G) / (wind_speed * fetch_length), 1.0 / 3.0)
