## Volumetric clouds compositor effect for rendering multi-layered atmospheric clouds.
##
## Manages compute shaders, temporal accumulation, downsampled depth generation,
## and fullscreen raster compositing within the Godot rendering pipeline.
@tool
class_name SunshineCloudsGD
extends CompositorEffect

## Triggers a manual compute pipeline and resource refresh.
@export_tool_button("Refresh Compute", "Clear")
var refresh_action: Callable = refresh_compute

@export_group("Basic Settings")
## Normalized coverage threshold defining cloud formation boundaries.
@export_range(0.0, 1.0) var clouds_coverage: float = 0.874

## Global density multiplier controlling the thickness and opacity of the cloud volume.
@export_range(0.0, 20.0) var clouds_density: float = 0.14

## Density factor for atmospheric Rayleigh and Mie scattering interactions.
@export_range(0.0, 2.0) var atmospheric_density: float = 0.503

## Multiplier for directional and ambient light absorption within the cloud volume.
@export_range(0.0, 10.0) var lighting_density: float = 0.982

## Controls the vertical ground fog influence and height attenuation.
@export_range(0.0, 1.0) var fog_effect_ground: float = 1.0

## Blend weight for sampling environment background fog into the cloud volume.
@export_range(0.0, 1.0) var use_environment_fog: float = 0.0

@export_subgroup("Colors")
## Forward/backward scattering asymmetry factor for the Henyey-Greenstein phase function.
@export_range(0.0, 1.0) var clouds_anisotropy: float = 0.16

## Multiplier for the powder sugar forward-scattering effect at cloud boundaries.
@export_range(0.0, 1.0) var clouds_powder: float = 0.5

## Primary ambient skylight color applied to indirect lighting.
@export var cloud_ambient_color: Color = Color(0.761, 0.784, 0.824, 1.0)

## Ambient tint color modulating the secondary bounce illumination.
@export var cloud_ambient_tint: Color = Color(0.133, 0.2, 0.243, 1.0)

## Base color utilized for physical atmospheric sky scattering.
@export var atmosphere_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Sampled fog color retrieved from the active [Environment].
@export var sampled_environment_fog_color: Color = Color(0.518, 0.553, 0.608, 1.0)

## Color tint applied to ambient occlusion shadowing in dense cloud pockets.
@export var ambient_occlusion_color: Color = Color(1.0, 0.0, 0.0, 1.0)

@export_subgroup("Structure")
## Temporal history blend weight for accumulation between consecutive frames.
@export_range(0.0, 1.0) var accumulation_decay: float = 0.7

## World-space spatial scale for the extra-large cloud structure noise texture.
@export_range(100.0, 1000000.0) var extra_large_noise_scale: float = 320000.0

## World-space spatial scale for the large macro cloud shape noise texture.
@export_range(100.0, 500000.0) var large_noise_scale: float = 120000.0

## World-space spatial scale for the medium erosion noise texture.
@export_range(100.0, 100000.0) var medium_noise_scale: float = 20000.0

## World-space spatial scale for high-frequency small detail noise.
@export_range(100.0, 10000.0) var small_noise_scale: float = 8500.0

## Density contrast exponent sharpening cloud surface transitions.
@export_range(0.0, 2.0) var clouds_sharpness: float = 0.746

## Power multiplier for detail noise subtractive carving.
@export_range(0.0, 3.0) var clouds_detail_power: float = 1.075

## Displacement strength applied by the curl noise vector field.
@export_range(0.0, 50000.0) var curl_noise_strength: float = 4500.0

## Falloff exponent controlling light absorption sharpness along sun rays.
@export_range(0.0, 2.0) var lighting_sharpness: float = 0.38

## Vertical normalized height range affected by wind displacement.
@export_range(0.0, 1.0) var wind_swept_range: float = 0.54

## Horizontal wind displacement strength applied across the cloud altitude.
@export_range(0.0, 5000.0) var wind_swept_strength: float = 0.0

## Lower altitude boundary in world units where cloud formation begins.
@export var cloud_floor: float = 1500.0

## Upper altitude boundary in world units where cloud formation terminates.
@export var cloud_ceiling: float = 25000.0

@export_subgroup("Performance")
## Maximum primary raymarch step iterations evaluated per pixel.
@export var max_step_count: float = 300.0

## Maximum secondary shadow ray iterations marched toward directional lights.
@export var max_lighting_steps: float = 32.0

## Viewport downsampling divisor applied to the raymarching compute pass.
@export_enum("Native", "Half", "Quarter", "Eighth") var resolution_scale: int = 1:
	get:
		return resolution_scale
	set(value):
		resolution_scale = value
		last_size = Vector2i.ZERO
		lights_updated = true

## Distance-based level-of-detail bias accelerating raymarching at far ranges.
@export_range(0.0, 2.0) var lod_bias: float = 1.0

@export_subgroup("Noise Textures")
## Blue noise dither texture utilized to randomize ray step offsets.
@export var dither_noise: Texture2D

## Vertical density profile gradient mapped across the cloud layer altitude.
@export var height_gradient: Texture2D

## 2D texture mask defining macro-scale cloud distribution patterns.
@export var extra_large_noise_patterns: Texture2D

## 3D volumetric noise texture providing primary cloud base shapes.
@export var large_scale_noise: Texture3D

## 3D volumetric noise texture providing medium-scale structural erosion.
@export var medium_scale_noise: Texture3D

## 3D volumetric noise texture providing micro-scale high-frequency detail.
@export var small_scale_noise: Texture3D

## 3D volumetric curl noise field applying turbulent displacement.
@export var curl_noise: Texture3D

@export_group("Advanced Settings")
@export_subgroup("Visuals")
## Playback speed multiplier for temporal dither jitter cycling.
@export_range(0.0, 1000.0) var dither_speed: float = 15.111

## Filter radius for spatial bilateral reconstruction and blur.
@export_range(0.0, 20.0) var blur_power: float = 2.0

## Sample tap quality multiplier for the post-pass bilateral filter.
@export_range(0.0, 6.0) var blur_quality: float = 1.0

@export_subgroup("Reflections")
## Global shader parameter name where the downsampled cloud reflection buffer is bound.
@export var reflections_globalshaderparam: String = ""

@export_subgroup("Performance")
## Minimum step distance in world units for close-range raymarching.
@export var min_step_distance: float = 400.0

## Maximum step distance in world units for empty-space raymarching.
@export var max_step_distance: float = 500.0

## Maximum distance in world units evaluated for shadow ray transmission.
@export var lighting_travel_distance: float = 10000.0

@export_subgroup("Mask")
## Whether to override procedural macro noise with an authored mask texture.
@export var extra_large_used_as_mask: bool = false

## World-space width of the authored mask projection in kilometers.
@export var mask_width_km: float = 32.0

@export_group("Compute Shaders")
## Compute shader performing conservative reversed-Z depth downsampling.
@export var pre_pass_compute_shader: RDShaderFile

## Primary compute shader performing volumetric raymarching and temporal accumulation.
@export var compute_shader: RDShaderFile

## Compute shader performing bilateral upsampling, filtering, and atmospheric blend.
@export var post_pass_compute_shader: RDShaderFile

@export_group("Internal Use")
## World-space translation offset applied to the entire cloud volume.
@export var origin_offset: Vector3 = Vector3.ZERO

@export_subgroup("Positions")
## Normalized horizontal wind movement direction vector.
@export var wind_direction: Vector3 = Vector3.ZERO

## Extra-large noise sampling position offset in world coordinates.
var extra_large_scale_clouds_position: Vector3 = Vector3.ZERO

## Large noise sampling position offset in world coordinates.
var large_scale_clouds_position: Vector3 = Vector3.ZERO

## Medium noise sampling position offset in world coordinates.
var medium_scale_clouds_position: Vector3 = Vector3.ZERO

## Small detail noise sampling position offset in world coordinates.
var detail_clouds_position: Vector3 = Vector3.ZERO

## Accumulated animation time passed into shader uniforms.
var current_time: float = 0.0

@export_subgroup("Lights")
## Packed directional light uniform vectors (direction, shadow steps, color, intensity).
@export var directional_lights_data: Array[Vector4] = []

## Packed omni light uniform vectors (position, radius, color, intensity).
@export var point_lights_data: Array[Vector4] = []

## Packed point effector uniform vectors (position, radius, power, attenuation).
@export var point_effector_data: Array[Vector4] = []

## Position query request buffer for asynchronous density sampling.
var position_queries: Array[Vector3] = []

## Callback handles dispatched when asynchronous point queries resolve.
var position_query_callables: Array[Callable] = []

## Whether an asynchronous point query readback is currently in flight.
var position_querying: bool = false

## Whether the point query buffer is currently resetting.
var position_resetting: bool = false

## Flags that light uniform buffers require GPU re-upload.
var lights_updated: bool = false

## Cached projection matrix from the preceding frame.
var _prev_cam_proj: Projection

## Cached inverse projection matrix from the preceding frame.
var _prev_cam_inv_proj: Projection

## Cached view matrix from the preceding frame.
var _prev_cam_view: Projection

## Cached inverse view matrix from the preceding frame.
var _prev_cam_inv_view: Projection

## Tracks whether previous camera matrices have been populated.
var _has_prev_matrices: bool = false

## Rendering device handle for the external painted mask texture.
var mask_drawn_rid: RID = RID()

## Primary rendering device handle.
var rd: RenderingDevice

## Main compute shader handle.
var shader: RID = RID()

## Main compute pipeline handle.
var pipeline: RID = RID()

## Depth downsampling prepass compute shader handle.
var prepass_shader: RID = RID()

## Depth downsampling prepass compute pipeline handle.
var prepass_pipeline: RID = RID()

## Bilateral postpass compute shader handle.
var postpass_shader: RID = RID()

## Bilateral postpass compute pipeline handle.
var postpass_pipeline: RID = RID()

## Fullscreen display raster shader handle.
var display_shader: RID = RID()

## Fullscreen display raster pipeline handle.
var display_pipeline: RID = RID()

## Vertex format identifier for the fullscreen quad mesh.
var display_vertex_format: int = -1

## Vertex buffer handle storing fullscreen quad geometry.
var display_vertex_buffer: RID = RID()

## Vertex array handle binding the display vertex buffer.
var display_vertex_array: RID = RID()

## Framebuffer format identifier matching the active viewport color/depth targets.
var framebuffer_format: int = -1

## Nearest-neighbor texture sampler handle.
var nearest_sampler: RID = RID()

## Linear filtering texture sampler handle with repeat wrapping.
var linear_sampler: RID = RID()

## Linear filtering texture sampler handle with edge clamping.
var linear_sampler_no_repeat: RID = RID()

## Uniform buffer handle storing global cloud settings and camera matrices.
var general_data_buffer: RID = RID()

## Uniform buffer handle storing packed light and effector arrays.
var light_data_buffer: RID = RID()

## Storage buffer handle receiving asynchronous sample query results.
var point_sample_data_buffer: RID = RID()

## Double-buffered accumulation textures storing color and raymarch metrics.
var accumulation_textures: Array[RID] = []

## Intermediate texture handle storing conservative downsampled depth.
var resized_depth: RID = RID()

## Viewport internal render resolution recorded during the previous frame.
var last_size: Vector2i = Vector2i.ZERO

## Cached color buffer RIDs used to detect engine render target recreation.
var color_images: Array[RID] = []

## Intermediate storage texture handles receiving filtered post-pass color.
var blit_screen_images: Array[RID] = []

## RD uniform set handles for prepass, compute, postpass, and display dispatches.
var uniform_sets: Array[RID] = []

## Ping-pong toggle selecting between accumulation buffer pair A and B.
var accumulation_is_a: bool = false

## Flags whether accumulation history should be temporarily ignored.
var ignore_accumilation: bool = false

## Tracks whether the first execution frame is active.
var first_run: bool = true

## Frame filter counter cycling through temporal sub-frame patterns.
var filter_index: int = 0

## Viewport render target handle from the previous frame.
var last_render_target: RID = RID()

## Multisample anti-aliasing mode recorded during the previous frame.
var last_msaa_mode: RenderingServer.ViewportMSAA = (
	RenderingServer.ViewportMSAA.VIEWPORT_MSAA_DISABLED
)

## Active multisample anti-aliasing mode of the current viewport.
var msaa_mode: RenderingServer.ViewportMSAA = (
	RenderingServer.ViewportMSAA.VIEWPORT_MSAA_DISABLED
)

# --- Player Interaction & Public Methods ---


## Resets viewport dimensions and triggers a complete compute resource refresh.
func refresh_compute() -> void:
	print("SunshineCloudsGD: System requesting compute refresh.")
	mask_drawn_rid = RID()
	last_size = Vector2i.ZERO


## Updates the authored external mask texture handle [param new_mask].
func update_mask(new_mask: RID) -> void:
	print("SunshineCloudsGD: External mask updated.")
	mask_drawn_rid = new_mask
	last_size = Vector2i.ZERO


## Enqueues an asynchronous cloud density query at world [param position] dispatched to [param callable].
func add_sample(callable: Callable, position: Vector3) -> void:
	print("SunshineCloudsGD: Sampling requested at position: ", position)
	position_queries.append(position)
	position_query_callables.append(callable)


# --- Lifecycle & Pipeline Initialization ---


## Initializes compositor callback timing and requests render-thread compute setup.
func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	access_resolved_depth = true
	access_resolved_color = true
	needs_motion_vectors = true
	RenderingServer.call_on_render_thread(initialize_compute)


## Frees rendering device allocations when the resource is destroyed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(self):
		RenderingServer.call_on_render_thread(clear_compute)


## Frees all allocated [RenderingDevice] buffers, textures, samplers, and pipelines.
func clear_compute() -> void:
	if rd:
		if pipeline.is_valid():
			rd.free_rid(pipeline)
		if shader.is_valid():
			rd.free_rid(shader)
		if prepass_pipeline.is_valid():
			rd.free_rid(prepass_pipeline)
		if prepass_shader.is_valid():
			rd.free_rid(prepass_shader)
		if postpass_pipeline.is_valid():
			rd.free_rid(postpass_pipeline)
		if postpass_shader.is_valid():
			rd.free_rid(postpass_shader)
		if display_pipeline.is_valid():
			rd.free_rid(display_pipeline)
		if display_shader.is_valid():
			rd.free_rid(display_shader)
		if display_vertex_array.is_valid():
			rd.free_rid(display_vertex_array)
		if display_vertex_buffer.is_valid():
			rd.free_rid(display_vertex_buffer)
		if nearest_sampler.is_valid():
			rd.free_rid(nearest_sampler)
		if linear_sampler.is_valid():
			rd.free_rid(linear_sampler)
		if linear_sampler_no_repeat.is_valid():
			rd.free_rid(linear_sampler_no_repeat)
		if general_data_buffer.is_valid():
			rd.free_rid(general_data_buffer)
		if light_data_buffer.is_valid():
			rd.free_rid(light_data_buffer)
		if point_sample_data_buffer.is_valid():
			rd.free_rid(point_sample_data_buffer)
		if resized_depth.is_valid():
			rd.free_rid(resized_depth)

		for item: RID in accumulation_textures:
			if item.is_valid():
				rd.free_rid(item)
		accumulation_textures.clear()

		for item: RID in blit_screen_images:
			if item.is_valid():
				rd.free_rid(item)
		blit_screen_images.clear()

		pipeline = RID()
		shader = RID()
		prepass_pipeline = RID()
		prepass_shader = RID()
		postpass_pipeline = RID()
		postpass_shader = RID()
		display_pipeline = RID()
		display_shader = RID()
		display_vertex_array = RID()
		display_vertex_buffer = RID()
		nearest_sampler = RID()
		linear_sampler = RID()
		linear_sampler_no_repeat = RID()
		general_data_buffer = RID()
		light_data_buffer = RID()
		point_sample_data_buffer = RID()
		resized_depth = RID()


## Compiles compute and raster pipelines and initializes static sampling states.
func initialize_compute() -> void:
	first_run = true
	if not rd:
		rd = RenderingServer.get_rendering_device()
		if not rd:
			enabled = false
			printerr("SunshineCloudsGD: No rendering device available on initialization.")
			return

	clear_compute()

	var sampler_state: RDSamplerState = RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	nearest_sampler = rd.sampler_create(sampler_state)

	var linear_sampler_state: RDSamplerState = RDSamplerState.new()
	linear_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	linear_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	linear_sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	linear_sampler = rd.sampler_create(linear_sampler_state)

	var linear_sampler_state_no_repeat: RDSamplerState = RDSamplerState.new()
	linear_sampler_state_no_repeat.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler_state_no_repeat.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler_state_no_repeat.repeat_u = (
		RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	)
	linear_sampler_state_no_repeat.repeat_v = (
		RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	)
	linear_sampler_state_no_repeat.repeat_w = (
		RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	)
	linear_sampler_no_repeat = rd.sampler_create(linear_sampler_state_no_repeat)

	# Load required noise textures
	if not dither_noise:
		dither_noise = ResourceLoader.load(
			"res://addons/SunshineClouds2/NoiseTextures/bluenoise_Dither.png"
		)
	if not height_gradient:
		height_gradient = ResourceLoader.load(
			"res://addons/SunshineClouds2/NoiseTextures/HeightGradient.tres"
		)
	if not extra_large_noise_patterns:
		extra_large_noise_patterns = ResourceLoader.load(
			"res://addons/SunshineClouds2/NoiseTextures/ExtraLargeScaleNoise.tres"
		)
	if not large_scale_noise:
		large_scale_noise = ResourceLoader.load(
			"res://addons/SunshineClouds2/NoiseTextures/LargeScaleNoise.tres"
		)
	if not medium_scale_noise:
		medium_scale_noise = ResourceLoader.load(
			"res://addons/SunshineClouds2/NoiseTextures/MediumScaleNoise.tres"
		)
	if not small_scale_noise:
		small_scale_noise = ResourceLoader.load(
			"res://addons/SunshineClouds2/NoiseTextures/SmallScaleNoise.tres"
		)
	if not curl_noise:
		curl_noise = ResourceLoader.load(
			"res://addons/SunshineClouds2/NoiseTextures/curl_noise_varied.tga"
		)
	if not compute_shader:
		compute_shader = ResourceLoader.load(
			"res://addons/SunshineClouds2/SunshineCloudsCompute.glsl"
		)
	if not pre_pass_compute_shader:
		pre_pass_compute_shader = ResourceLoader.load(
			"res://addons/SunshineClouds2/SunshineCloudsPreCompute.glsl"
		)

	var display_shader_file: RDShaderFile
	if msaa_mode == RenderingServer.ViewportMSAA.VIEWPORT_MSAA_DISABLED:
		post_pass_compute_shader = ResourceLoader.load(
			"res://addons/SunshineClouds2/SunshineCloudsPostCompute.glsl"
		)
		display_shader_file = ResourceLoader.load(
			"res://addons/SunshineClouds2/SunshineCloudsDisplay.glsl"
		)
	else:
		post_pass_compute_shader = ResourceLoader.load(
			"res://addons/SunshineClouds2/SunshineCloudsPostCompute.msaa.glsl"
		)
		display_shader_file = ResourceLoader.load(
			"res://addons/SunshineClouds2/SunshineCloudsDisplay.msaa.glsl"
		)

	if (
		not compute_shader
		or not pre_pass_compute_shader
		or not post_pass_compute_shader
		or not display_shader_file
	):
		enabled = false
		printerr("SunshineCloudsGD: Missing required shader resources.")
		clear_compute()
		return

	var prepass_spirv: RDShaderSPIRV = pre_pass_compute_shader.get_spirv()
	prepass_shader = rd.shader_create_from_spirv(prepass_spirv)
	if prepass_shader.is_valid():
		prepass_pipeline = rd.compute_pipeline_create(prepass_shader)
	else:
		enabled = false
		printerr("SunshineCloudsGD: Prepass compute shader failed to compile.")
		clear_compute()
		return

	var shader_spirv: RDShaderSPIRV = compute_shader.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	if shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)
	else:
		enabled = false
		printerr("SunshineCloudsGD: Main compute shader failed to compile.")
		clear_compute()
		return

	var postpass_spirv: RDShaderSPIRV = post_pass_compute_shader.get_spirv()
	postpass_shader = rd.shader_create_from_spirv(postpass_spirv)
	if postpass_shader.is_valid():
		postpass_pipeline = rd.compute_pipeline_create(postpass_shader)
	else:
		enabled = false
		printerr("SunshineCloudsGD: Postpass compute shader failed to compile.")
		clear_compute()
		return

	var display_spirv: RDShaderSPIRV = display_shader_file.get_spirv()
	display_shader = rd.shader_create_from_spirv(display_spirv)
	if not display_shader.is_valid():
		enabled = false
		printerr("SunshineCloudsGD: Display raster shader failed to compile.")
		clear_compute()
		return

	var display_vertex_attributes: Array[RDVertexAttribute] = [RDVertexAttribute.new()]
	display_vertex_attributes[0].format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	display_vertex_attributes[0].frequency = RenderingDevice.VERTEX_FREQUENCY_VERTEX
	display_vertex_attributes[0].location = 0
	display_vertex_attributes[0].offset = 0
	display_vertex_attributes[0].stride = 8
	display_vertex_format = rd.vertex_format_create(display_vertex_attributes)

	var display_vertex_data: PackedByteArray = (
		PackedFloat32Array(
			[
				-1.0, -1.0, 1.0, -1.0, -1.0, 1.0,
				-1.0, 1.0, 1.0, -1.0, 1.0, 1.0
			]
		).to_byte_array()
	)

	display_vertex_buffer = rd.vertex_buffer_create(
		display_vertex_data.size(), display_vertex_data
	)
	display_vertex_array = rd.vertex_array_create(
		6, display_vertex_format, [display_vertex_buffer]
	)

	# std140 GenericData buffer (192 floats * 4 = 768 bytes)
	general_data_buffer = rd.uniform_buffer_create(768)
	light_data_buffer = rd.uniform_buffer_create(6272)

	var sample_data: PackedByteArray = PackedByteArray()
	sample_data.resize(512)
	point_sample_data_buffer = rd.storage_buffer_create(512, sample_data)

	last_msaa_mode = msaa_mode


## Configures the fullscreen raster display pipeline for color target [param color_texture] and [param depth_texture].
func initialize_raster_pipelines(color_texture: RID, depth_texture: RID) -> void:
	assert(rd != null)
	var framebuffer_attachmentformats: Array[RDAttachmentFormat] = [
		RDAttachmentFormat.new(), RDAttachmentFormat.new()
	]

	framebuffer_attachmentformats[0].format = rd.texture_get_format(color_texture).format
	framebuffer_attachmentformats[0].samples = rd.texture_get_format(color_texture).samples
	framebuffer_attachmentformats[0].usage_flags = rd.texture_get_format(color_texture).usage_bits

	framebuffer_attachmentformats[1].format = rd.texture_get_format(depth_texture).format
	framebuffer_attachmentformats[1].samples = rd.texture_get_format(depth_texture).samples
	framebuffer_attachmentformats[1].usage_flags = rd.texture_get_format(depth_texture).usage_bits

	framebuffer_format = rd.framebuffer_format_create(framebuffer_attachmentformats)

	var pipeline_rasterization_state: RDPipelineRasterizationState = (
		RDPipelineRasterizationState.new()
	)
	var pipeline_multisample_state: RDPipelineMultisampleState = (
		RDPipelineMultisampleState.new()
	)

	match msaa_mode:
		RenderingServer.ViewportMSAA.VIEWPORT_MSAA_2X:
			pipeline_multisample_state.sample_count = (
				RenderingDevice.TEXTURE_SAMPLES_2
			)
		RenderingServer.ViewportMSAA.VIEWPORT_MSAA_4X:
			pipeline_multisample_state.sample_count = (
				RenderingDevice.TEXTURE_SAMPLES_4
			)
		RenderingServer.ViewportMSAA.VIEWPORT_MSAA_8X:
			pipeline_multisample_state.sample_count = (
				RenderingDevice.TEXTURE_SAMPLES_8
			)
		_:
			pipeline_multisample_state.sample_count = (
				RenderingDevice.TEXTURE_SAMPLES_1
			)

	var pipeline_depthstencil_state: RDPipelineDepthStencilState = (
		RDPipelineDepthStencilState.new()
	)
	var pipeline_colorblend_state: RDPipelineColorBlendState = (
		RDPipelineColorBlendState.new()
	)
	var colorblend_attachment: RDPipelineColorBlendStateAttachment = (
		RDPipelineColorBlendStateAttachment.new()
	)
	pipeline_colorblend_state.attachments.append(colorblend_attachment)

	display_pipeline = rd.render_pipeline_create(
		display_shader,
		framebuffer_format,
		display_vertex_format,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
		pipeline_rasterization_state,
		pipeline_multisample_state,
		pipeline_depthstencil_state,
		pipeline_colorblend_state
	)


## Reallocates resolution-dependent storage and accumulation textures when viewport dimensions change.
func reallocate_textures(
	new_size: Vector2i, view_count: int, is_msaa_on: bool, buffers: RenderSceneBuffersRD
) -> void:
	for item: RID in accumulation_textures:
		if item.is_valid():
			rd.free_rid(item)
	accumulation_textures.clear()

	for item: RID in blit_screen_images:
		if item.is_valid():
			rd.free_rid(item)
	blit_screen_images.clear()

	if resized_depth.is_valid():
		rd.free_rid(resized_depth)

	color_images.clear()

	for view in range(view_count):
		color_images.append(buffers.get_color_layer(view, false))
		var depth_image: RID = buffers.get_depth_layer(view, false)

		var blank_image_data: PackedByteArray = PackedByteArray()
		blank_image_data.resize(new_size.x * new_size.y * 16)

		var base_colorformat: RDTextureFormat = rd.texture_get_format(
			color_images[view]
		)
		var blit_screen_format: RDTextureFormat = rd.texture_get_format(
			buffers.get_color_layer(view, is_msaa_on)
		)
		blit_screen_format.usage_bits |= (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		)

		blit_screen_images.append(
			rd.texture_create(blit_screen_format, RDTextureView.new())
		)

		base_colorformat.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		base_colorformat.width = new_size.x
		base_colorformat.height = new_size.y

		for _i in range(7):
			accumulation_textures.append(
				rd.texture_create(
					base_colorformat, RDTextureView.new(), [blank_image_data]
				)
			)

		var depthformat: RDTextureFormat = rd.texture_get_format(depth_image)
		depthformat.width = new_size.x
		depthformat.height = new_size.y
		depthformat.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
		depthformat.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		)
		resized_depth = rd.texture_create(depthformat, RDTextureView.new(), [])


## Rebuilds uniform set bindings for view [param view] using current buffer [param buffers] and [param render_scene_data].
func build_view_uniform_sets(
	view: int,
	new_size: Vector2i,
	is_msaa_on: bool,
	buffers: RenderSceneBuffersRD,
	render_scene_data: RenderSceneData
) -> void:
	var depth_image: RID = buffers.get_depth_layer(view, false)
	var camera_data: RID = render_scene_data.get_uniform_buffer()

	# 1. Prepass Uniforms
	var prepass_uniforms: Array[RDUniform] = []
	var prepass_depth: RDUniform = RDUniform.new()
	prepass_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	prepass_depth.binding = 0
	prepass_depth.add_id(nearest_sampler)
	prepass_depth.add_id(depth_image)
	prepass_uniforms.append(prepass_depth)

	var prepass_out_depth: RDUniform = RDUniform.new()
	prepass_out_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	prepass_out_depth.binding = 1
	prepass_out_depth.add_id(resized_depth)
	prepass_uniforms.append(prepass_out_depth)

	var prepass_cam: RDUniform = RDUniform.new()
	prepass_cam.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	prepass_cam.binding = 2
	prepass_cam.add_id(general_data_buffer)
	prepass_uniforms.append(prepass_cam)

	uniform_sets.append(rd.uniform_set_create(prepass_uniforms, prepass_shader, 0))

	# 2. Main Compute Uniforms
	var compute_uniforms: Array[RDUniform] = []
	for i in range(6):
		var accum_uniform: RDUniform = RDUniform.new()
		accum_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		accum_uniform.binding = i
		accum_uniform.add_id(accumulation_textures[(view * 7) + i])
		compute_uniforms.append(accum_uniform)

	var depth_uniform: RDUniform = RDUniform.new()
	depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	depth_uniform.binding = 6
	depth_uniform.add_id(nearest_sampler)
	depth_uniform.add_id(resized_depth)
	compute_uniforms.append(depth_uniform)

	var extra_noise_uniform: RDUniform = RDUniform.new()
	extra_noise_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	extra_noise_uniform.binding = 7
	extra_noise_uniform.add_id(linear_sampler)
	if extra_large_used_as_mask and mask_drawn_rid.is_valid():
		extra_noise_uniform.add_id(mask_drawn_rid)
	else:
		extra_noise_uniform.add_id(
			RenderingServer.texture_get_rd_texture(
				extra_large_noise_patterns.get_rid()
			)
		)
	compute_uniforms.append(extra_noise_uniform)

	var noise_samplers: Array = [
		large_scale_noise, medium_scale_noise, small_scale_noise, curl_noise
	]
	for i in range(4):
		var noise_uniform: RDUniform = RDUniform.new()
		noise_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		noise_uniform.binding = 8 + i
		noise_uniform.add_id(linear_sampler)
		noise_uniform.add_id(
			RenderingServer.texture_get_rd_texture(noise_samplers[i].get_rid())
		)
		compute_uniforms.append(noise_uniform)

	var dither_uniform: RDUniform = RDUniform.new()
	dither_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	dither_uniform.binding = 12
	dither_uniform.add_id(nearest_sampler)
	dither_uniform.add_id(
		RenderingServer.texture_get_rd_texture(dither_noise.get_rid())
	)
	compute_uniforms.append(dither_uniform)

	var height_uniform: RDUniform = RDUniform.new()
	height_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	height_uniform.binding = 13
	height_uniform.add_id(linear_sampler_no_repeat)
	height_uniform.add_id(
		RenderingServer.texture_get_rd_texture(height_gradient.get_rid())
	)
	compute_uniforms.append(height_uniform)

	var cam_uniform: RDUniform = RDUniform.new()
	cam_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	cam_uniform.binding = 14
	cam_uniform.add_id(general_data_buffer)
	compute_uniforms.append(cam_uniform)

	var light_uniform: RDUniform = RDUniform.new()
	light_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	light_uniform.binding = 15
	light_uniform.add_id(light_data_buffer)
	compute_uniforms.append(light_uniform)

	var sample_uniform: RDUniform = RDUniform.new()
	sample_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	sample_uniform.binding = 16
	sample_uniform.add_id(point_sample_data_buffer)
	compute_uniforms.append(sample_uniform)

	var scene_cam_uniform: RDUniform = RDUniform.new()
	scene_cam_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	scene_cam_uniform.binding = 17
	scene_cam_uniform.add_id(camera_data)
	compute_uniforms.append(scene_cam_uniform)

	uniform_sets.append(rd.uniform_set_create(compute_uniforms, shader, 0))

	# 3. Postpass Uniforms
	var postpass_uniforms: Array[RDUniform] = []
	var post_color_data: RDUniform = RDUniform.new()
	post_color_data.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	post_color_data.binding = 0
	post_color_data.add_id(linear_sampler_no_repeat)
	post_color_data.add_id(accumulation_textures[view * 7])
	postpass_uniforms.append(post_color_data)

	var post_color: RDUniform = RDUniform.new()
	post_color.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	post_color.binding = 1
	post_color.add_id(linear_sampler_no_repeat)
	post_color.add_id(accumulation_textures[(view * 7) + 1])
	postpass_uniforms.append(post_color)

	var post_refl: RDUniform = RDUniform.new()
	post_refl.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	post_refl.binding = 2
	post_refl.add_id(accumulation_textures[(view * 7) + 6])
	postpass_uniforms.append(post_refl)

	if reflections_globalshaderparam != "":
		var new_texture: Texture2DRD = Texture2DRD.new()
		new_texture.texture_rd_rid = accumulation_textures[(view * 7) + 6]
		RenderingServer.global_shader_parameter_set(
			reflections_globalshaderparam, new_texture
		)

	var post_screen_in: RDUniform = RDUniform.new()
	post_screen_in.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	post_screen_in.binding = 3
	post_screen_in.add_id(nearest_sampler)
	post_screen_in.add_id(buffers.get_color_layer(view, is_msaa_on))
	postpass_uniforms.append(post_screen_in)

	var post_screen_out: RDUniform = RDUniform.new()
	post_screen_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	post_screen_out.binding = 4
	post_screen_out.add_id(blit_screen_images[view])
	postpass_uniforms.append(post_screen_out)

	var post_depth: RDUniform = RDUniform.new()
	post_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	post_depth.binding = 5
	post_depth.add_id(nearest_sampler)
	post_depth.add_id(buffers.get_depth_layer(view, is_msaa_on))
	postpass_uniforms.append(post_depth)

	var post_cam: RDUniform = RDUniform.new()
	post_cam.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	post_cam.binding = 6
	post_cam.add_id(general_data_buffer)
	postpass_uniforms.append(post_cam)

	var post_lights: RDUniform = RDUniform.new()
	post_lights.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	post_lights.binding = 7
	post_lights.add_id(light_data_buffer)
	postpass_uniforms.append(post_lights)

	var post_scene_cam: RDUniform = RDUniform.new()
	post_scene_cam.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	post_scene_cam.binding = 8
	post_scene_cam.add_id(camera_data)
	postpass_uniforms.append(post_scene_cam)

	uniform_sets.append(rd.uniform_set_create(postpass_uniforms, postpass_shader, 0))

	# 4. Display Uniforms
	var display_uniforms: Array[RDUniform] = []
	var disp_screen: RDUniform = RDUniform.new()
	disp_screen.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	disp_screen.binding = 0
	disp_screen.add_id(nearest_sampler)
	disp_screen.add_id(blit_screen_images[view])
	display_uniforms.append(disp_screen)

	uniform_sets.append(rd.uniform_set_create(display_uniforms, display_shader, 0))


## Engine render thread entry point orchestrating compute dispatches and screen composition.
func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
	if rd == null:
		initialize_compute()
		return

	if not (
		pipeline.is_valid()
		and height_gradient
		and extra_large_noise_patterns
		and large_scale_noise
		and medium_scale_noise
		and small_scale_noise
		and dither_noise
		and curl_noise
	):
		return

	var buffers: RenderSceneBuffersRD = (
		render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	)
	if not buffers:
		return

	msaa_mode = buffers.get_msaa_3d()
	var is_msaa_on: bool = (
		msaa_mode != RenderingServer.ViewportMSAA.VIEWPORT_MSAA_DISABLED
	)
	var size: Vector2i = buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	var resscale: int = int(pow(2.0, float(resolution_scale)))
	var new_size: Vector2i = size / resscale
	var view_count: int = buffers.get_view_count()
	var render_scene_data: RenderSceneData = render_data.get_render_scene_data()

	# Recompile pipelines ONLY if MSAA mode changes
	if msaa_mode != last_msaa_mode:
		initialize_compute()
		initialize_raster_pipelines(
			buffers.get_color_layer(0, is_msaa_on),
			buffers.get_depth_layer(0, is_msaa_on)
		)

	# Reallocate textures ONLY if viewport resolution changes
	if size != last_size or accumulation_textures.is_empty():
		reallocate_textures(new_size, view_count, is_msaa_on, buffers)
		initialize_raster_pipelines(
			buffers.get_color_layer(0, is_msaa_on),
			buffers.get_depth_layer(0, is_msaa_on)
		)
		uniform_sets.clear()

	# Rebuild uniform sets if invalidated by engine buffer swaps (SDFGI/SSR)
	var current_color_layer: RID = buffers.get_color_layer(0, is_msaa_on)
	var needs_uniform_rebuild: bool = (
		uniform_sets.is_empty()
		or uniform_sets.size() != view_count * 4
		or color_images.is_empty()
		or color_images[0] != buffers.get_color_layer(0, false)
	)

	if needs_uniform_rebuild:
		color_images.clear()
		for v in range(view_count):
			color_images.append(buffers.get_color_layer(v, false))

		uniform_sets.clear()
		for view in range(view_count):
			build_view_uniform_sets(
				view, new_size, is_msaa_on, buffers, render_scene_data
			)
		lights_updated = true

	var color_layer: RID = buffers.get_color_layer(0, is_msaa_on)
	var depth_layer: RID = buffers.get_depth_layer(0, is_msaa_on)
	var framebuffer: RID = FramebufferCacheRD.get_cache_multipass(
		[color_layer, depth_layer], [], view_count
	)

	var rendertarget: RID = buffers.get_render_target()
	if rendertarget != last_render_target:
		last_render_target = rendertarget
		ignore_accumilation = true
	else:
		ignore_accumilation = false

	last_size = size

	update_matrices(render_scene_data, new_size)
	if lights_updated or directional_lights_data.is_empty():
		update_lights()

	if not position_querying and not position_resetting and not position_queries.is_empty():
		encode_sample_points()

	var prepass_x_groups: int = ((size.x - 1) / 8) + 1
	var prepass_y_groups: int = ((size.y - 1) / 8) + 1
	var x_groups: int = ((size.x - 1) / 8 / resscale) + 1
	var y_groups: int = ((size.y - 1) / 8 / resscale) + 1

	for view in range(view_count):
		# 1. Prepass Compute Dispatch
		var prepass_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(prepass_list, prepass_pipeline)
		rd.compute_list_bind_uniform_set(prepass_list, uniform_sets[view * 4], 0)
		rd.compute_list_dispatch(prepass_list, x_groups, y_groups, 1)
		rd.compute_list_end()

		# 2. Main Compute Raymarch Dispatch
		var compute_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_sets[(view * 4) + 1], 0)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()

		# 3. Postpass Bilateral Filter Dispatch
		var postpass_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(postpass_list, postpass_pipeline)
		rd.compute_list_bind_uniform_set(postpass_list, uniform_sets[(view * 4) + 2], 0)
		rd.compute_list_dispatch(postpass_list, prepass_x_groups, prepass_y_groups, 1)
		rd.compute_list_end()

		# 4. Display Raster Composition Draw
		var display_list: int = rd.draw_list_begin(
			framebuffer, RenderingDevice.DRAW_DEFAULT_ALL
		)
		rd.draw_list_bind_render_pipeline(display_list, display_pipeline)
		rd.draw_list_bind_uniform_set(display_list, uniform_sets[(view * 4) + 3], 0)
		rd.draw_list_bind_vertex_array(display_list, display_vertex_array)
		rd.draw_list_draw(display_list, false, 1)
		rd.draw_list_end()

	if not position_resetting and position_querying:
		position_resetting = true
		rd.buffer_get_data_async(
			point_sample_data_buffer, retrieve_position_queries.bind()
		)


## Decodes asynchronous sample density readback [param data] and triggers registered callbacks.
func retrieve_position_queries(data: PackedByteArray) -> void:
	var idx: int = 0
	while idx < 512 and not position_query_callables.is_empty():
		var pos: Vector3 = Vector3(
			data.decode_float(idx),
			data.decode_float(idx + 4),
			data.decode_float(idx + 8)
		)
		var density: float = data.decode_float(idx + 12)
		idx += 16

		position_query_callables[0].call(pos, density)
		position_query_callables.remove_at(0)

	position_querying = false
	position_resetting = false


## Encodes camera transform matrices and uniform parameters into [member general_data_buffer].
func update_matrices(render_scene_data: RenderSceneData, new_size: Vector2i) -> void:
	var float_data: PackedFloat32Array = PackedFloat32Array()
	float_data.resize(192)
	var idx: int = 0

	filter_index = (filter_index + 1) % 16
	accumulation_is_a = not accumulation_is_a
	first_run = false

	var width: float = mask_width_km * 1000.0

	if extra_large_used_as_mask:
		float_data[idx] = origin_offset.x + ((width * 0.5) * -1.0)
		float_data[idx + 1] = origin_offset.y + ((width * 0.5) * -1.0)
		float_data[idx + 2] = origin_offset.z + ((width * 0.5) * -1.0)
		float_data[idx + 3] = width
	else:
		float_data[idx] = extra_large_scale_clouds_position.x
		float_data[idx + 1] = extra_large_scale_clouds_position.y
		float_data[idx + 2] = extra_large_scale_clouds_position.z
		float_data[idx + 3] = extra_large_noise_scale
	idx += 4

	float_data[idx] = large_scale_clouds_position.x
	float_data[idx + 1] = large_scale_clouds_position.y
	float_data[idx + 2] = large_scale_clouds_position.z
	float_data[idx + 3] = lighting_sharpness
	idx += 4

	float_data[idx] = medium_scale_clouds_position.x
	float_data[idx + 1] = medium_scale_clouds_position.y
	float_data[idx + 2] = medium_scale_clouds_position.z
	float_data[idx + 3] = lighting_travel_distance
	idx += 4

	float_data[idx] = detail_clouds_position.x
	float_data[idx + 1] = detail_clouds_position.y
	float_data[idx + 2] = detail_clouds_position.z
	float_data[idx + 3] = atmospheric_density
	idx += 4

	float_data[idx] = cloud_ambient_color.r * cloud_ambient_tint.r
	float_data[idx + 1] = cloud_ambient_color.g * cloud_ambient_tint.g
	float_data[idx + 2] = cloud_ambient_color.b * cloud_ambient_tint.b
	float_data[idx + 3] = cloud_ambient_color.a * cloud_ambient_tint.a
	idx += 4

	float_data[idx] = ambient_occlusion_color.r
	float_data[idx + 1] = ambient_occlusion_color.g
	float_data[idx + 2] = ambient_occlusion_color.b
	float_data[idx + 3] = ambient_occlusion_color.a
	idx += 4

	float_data[idx] = lerpf(
		atmosphere_color.r, sampled_environment_fog_color.r, use_environment_fog
	)
	float_data[idx + 1] = lerpf(
		atmosphere_color.g, sampled_environment_fog_color.g, use_environment_fog
	)
	float_data[idx + 2] = lerpf(
		atmosphere_color.b, sampled_environment_fog_color.b, use_environment_fog
	)
	float_data[idx + 3] = lerpf(
		atmosphere_color.a, sampled_environment_fog_color.a, use_environment_fog
	)
	idx += 4

	float_data[idx] = small_noise_scale
	float_data[idx + 1] = min_step_distance
	float_data[idx + 2] = max_step_distance
	float_data[idx + 3] = lod_bias
	idx += 4

	float_data[idx] = clouds_sharpness
	float_data[idx + 1] = float(directional_lights_data.size()) / 2.0
	float_data[idx + 2] = clouds_powder
	float_data[idx + 3] = clouds_anisotropy
	idx += 4

	float_data[idx] = cloud_floor
	float_data[idx + 1] = cloud_ceiling
	float_data[idx + 2] = float(max_step_count)
	float_data[idx + 3] = float(max_lighting_steps)
	idx += 4

	float_data[idx] = use_environment_fog
	float_data[idx + 1] = float(blur_power)
	float_data[idx + 2] = float(blur_quality)
	float_data[idx + 3] = float(curl_noise_strength)
	idx += 4

	float_data[idx] = wind_direction.x
	float_data[idx + 1] = wind_direction.z
	float_data[idx + 2] = fog_effect_ground
	float_data[idx + 3] = float(position_queries.size())
	idx += 4

	float_data[idx] = float(point_lights_data.size()) / 2.0
	float_data[idx + 1] = float(point_effector_data.size()) / 2.0
	float_data[idx + 2] = wind_swept_range
	float_data[idx + 3] = wind_swept_strength
	idx += 4

	float_data[idx] = float(new_size.x)
	float_data[idx + 1] = float(new_size.y)
	float_data[idx + 2] = large_noise_scale
	float_data[idx + 3] = medium_noise_scale
	idx += 4

	float_data[idx] = current_time
	float_data[idx + 1] = clouds_coverage
	float_data[idx + 2] = clouds_density
	float_data[idx + 3] = clouds_detail_power
	idx += 4

	float_data[idx] = lighting_density
	float_data[idx + 1] = accumulation_decay if not ignore_accumilation else 0.0
	float_data[idx + 2] = 1.0 if accumulation_is_a else 0.0
	float_data[idx + 3] = float(pow(2.0, float(resolution_scale)))
	idx += 4

	var cam_proj: Projection = render_scene_data.get_cam_projection()
	var cam_inv_proj: Projection = cam_proj.inverse()
	var cam_view_tr: Transform3D = render_scene_data.get_cam_transform().inverse()
	var cam_inv_view_tr: Transform3D = cam_view_tr.inverse()

	var cam_view: Projection = Projection(cam_view_tr)
	var cam_inv_view: Projection = Projection(cam_inv_view_tr)

	var prev_cam_proj: Projection = (
		_prev_cam_proj if _has_prev_matrices else cam_proj
	)
	var prev_cam_inv_proj: Projection = (
		_prev_cam_inv_proj if _has_prev_matrices else cam_inv_proj
	)
	var prev_cam_view: Projection = (
		_prev_cam_view if _has_prev_matrices else cam_view
	)
	var prev_cam_inv_view: Projection = (
		_prev_cam_inv_view if _has_prev_matrices else cam_inv_view
	)

	_prev_cam_proj = cam_proj
	_prev_cam_inv_proj = cam_inv_proj
	_prev_cam_view = cam_view
	_prev_cam_inv_view = cam_inv_view
	_has_prev_matrices = true

	var mat_idx: int = 64
	for mat in [
		cam_proj,
		cam_inv_proj,
		cam_view,
		cam_inv_view,
		prev_cam_proj,
		prev_cam_inv_proj,
		prev_cam_view,
		prev_cam_inv_view
	]:
		float_data[mat_idx] = mat.x.x
		float_data[mat_idx + 1] = mat.x.y
		float_data[mat_idx + 2] = mat.x.z
		float_data[mat_idx + 3] = mat.x.w
		float_data[mat_idx + 4] = mat.y.x
		float_data[mat_idx + 5] = mat.y.y
		float_data[mat_idx + 6] = mat.y.z
		float_data[mat_idx + 7] = mat.y.w
		float_data[mat_idx + 8] = mat.z.x
		float_data[mat_idx + 9] = mat.z.y
		float_data[mat_idx + 10] = mat.z.z
		float_data[mat_idx + 11] = mat.z.w
		float_data[mat_idx + 12] = mat.w.x
		float_data[mat_idx + 13] = mat.w.y
		float_data[mat_idx + 14] = mat.w.z
		float_data[mat_idx + 15] = mat.w.w
		mat_idx += 16

	var general_byte_data: PackedByteArray = float_data.to_byte_array()
	rd.buffer_update(
		general_data_buffer, 0, general_byte_data.size(), general_byte_data
	)


## Encodes directional lights, point lights, and effectors into [member light_data_buffer].
func update_lights() -> void:
	lights_updated = false

	if directional_lights_data.is_empty():
		directional_lights_data.append(Vector4(0.5, 1.0, 0.5, 16.0))
		directional_lights_data.append(Vector4(1.0, 1.0, 1.0, 1.0))

	# 1568 floats = 6272 bytes
	var float_data: PackedFloat32Array = PackedFloat32Array()
	float_data.resize(1568)

	var idx: int = 0
	var max_dir: int = min(directional_lights_data.size(), 8)
	for i in range(max_dir):
		float_data[idx] = directional_lights_data[i].x
		float_data[idx + 1] = directional_lights_data[i].y
		float_data[idx + 2] = directional_lights_data[i].z
		float_data[idx + 3] = directional_lights_data[i].w
		idx += 4

	idx = 32
	var max_pts: int = min(point_lights_data.size(), 256)
	for i in range(max_pts):
		float_data[idx] = point_lights_data[i].x
		float_data[idx + 1] = point_lights_data[i].y
		float_data[idx + 2] = point_lights_data[i].z
		float_data[idx + 3] = point_lights_data[i].w
		idx += 4

	idx = 1056
	var max_eff: int = min(point_effector_data.size(), 128)
	for i in range(max_eff):
		float_data[idx] = point_effector_data[i].x
		float_data[idx + 1] = point_effector_data[i].y
		float_data[idx + 2] = point_effector_data[i].z
		float_data[idx + 3] = point_effector_data[i].w
		idx += 4

	var light_byte_data: PackedByteArray = float_data.to_byte_array()
	rd.buffer_update(
		light_data_buffer, 0, light_byte_data.size(), light_byte_data
	)


## Encodes pending sample point positions into [member point_sample_data_buffer].
func encode_sample_points() -> void:
	position_querying = true

	var float_data: PackedFloat32Array = PackedFloat32Array()
	float_data.resize(128)

	var idx: int = 0
	while idx < 128 and not position_queries.is_empty():
		var pos: Vector3 = position_queries[0]
		float_data[idx] = pos.x
		float_data[idx + 1] = pos.y
		float_data[idx + 2] = pos.z
		float_data[idx + 3] = 0.0
		idx += 4
		position_queries.remove_at(0)

	var sample_byte_data: PackedByteArray = float_data.to_byte_array()
	rd.buffer_update(
		point_sample_data_buffer, 0, sample_byte_data.size(), sample_byte_data
	)
