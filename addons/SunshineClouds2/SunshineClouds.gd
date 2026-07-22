@tool
class_name SunshineCloudsGD
extends CompositorEffect

## Controls the refresh action behavior.
@export_tool_button("Refresh Compute", "Clear") var refresh_action: Callable = refresh_compute

@export_group("Basic Settings")
@export_range(0, 1) var clouds_coverage: float = 0.874
## Controls the thickness and opacity of the clouds density.
@export_range(0, 20) var clouds_density: float = 0.14
## Controls the thickness and opacity of the atmospheric density.
@export_range(0, 2) var atmospheric_density: float = 0.503
## Controls the thickness and opacity of the lighting density.
@export_range(0, 10) var lighting_density: float = 0.982
## Controls the fog effect ground behavior.
@export_range(0, 1) var fog_effect_ground: float = 1.0
## Controls the use environment fog behavior.
@export_range(0, 1) var use_environment_fog: float = 0.0

@export_subgroup("Colors")
@export_range(0, 1) var clouds_anisotropy: float = 0.16
## Controls the clouds powder behavior.
@export_range(0, 1) var clouds_powder: float = 0.5
## The cloud ambient color used for cloud rendering.
@export var cloud_ambient_color: Color = Color(0.761, 0.784, 0.824, 1.0)
## Controls the cloud ambient tint behavior.
@export var cloud_ambient_tint: Color = Color(0.133, 0.2, 0.243, 1.0)
## The atmosphere color used for cloud rendering.
@export var atmosphere_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## The sampled environment fog color used for cloud rendering.
@export var sampled_environment_fog_color: Color = Color(0.518, 0.553, 0.608, 1.0)
## The ambient occlusion color used for cloud rendering.
@export var ambient_occlusion_color: Color = Color(1.0, 0.0, 0.0, 1.0)

@export_subgroup("Structure")
@export_range(0, 1) var accumulation_decay: float = 0.7
## The extra large noise scale texture map applied to the clouds.
@export_range(100, 1000000) var extra_large_noise_scale: float = 320000.0
## The large noise scale texture map applied to the clouds.
@export_range(100, 500000) var large_noise_scale: float = 120000.0
## The medium noise scale texture map applied to the clouds.
@export_range(100, 100000) var medium_noise_scale: float = 20000.0
## The small noise scale texture map applied to the clouds.
@export_range(100, 10000) var small_noise_scale: float = 8500.0
## Controls the clouds sharpness behavior.
@export_range(0, 2) var clouds_sharpness: float = 0.746
## The intensity multiplier for the clouds detail power effect.
@export_range(0, 3) var clouds_detail_power: float = 1.075
## The curl noise strength texture map applied to the clouds.
@export_range(0, 50000) var curl_noise_strength: float = 4500.0
## Controls the lighting sharpness behavior.
@export_range(0, 2) var lighting_sharpness: float = 0.38
## Controls the wind swept range behavior.
@export_range(0, 1) var wind_swept_range: float = 0.54
## The intensity multiplier for the wind swept strength effect.
@export_range(0, 5000) var wind_swept_strength: float = 0.0
## Controls the cloud floor behavior.
@export var cloud_floor: float = 1500.0
## Controls the cloud ceiling behavior.
@export var cloud_ceiling: float = 25000.0

@export_subgroup("Performance")
@export var max_step_count: float = 300.0
## Controls the max lighting steps behavior.
@export var max_lighting_steps: float = 32.0

## The scaling factor applied to the resolution scale.
@export_enum("Native", "Half", "Quarter", "Eighth") var resolution_scale: int = 1:
	get:
		return resolution_scale
	set(value):
		resolution_scale = value
		last_size = Vector2i.ZERO
		lights_updated = true

## Controls the lod bias behavior.
@export_range(0, 2) var lod_bias: float = 1.0

@export_subgroup("Noise Textures")
@export var dither_noise: Texture3D
## Controls the height gradient behavior.
@export var height_gradient: Texture2D
## The extra large noise patterns texture map applied to the clouds.
@export var extra_large_noise_patterns: Texture2D

## The large scale noise texture map applied to the clouds.
@export var large_scale_noise: Texture3D
## The medium scale noise texture map applied to the clouds.
@export var medium_scale_noise: Texture3D
## The small scale noise texture map applied to the clouds.
@export var small_scale_noise: Texture3D
## The curl noise texture map applied to the clouds.
@export var curl_noise: Texture3D

@export_group("Advanced Settings")
@export_subgroup("Visuals")
@export_range(0, 1000) var dither_speed: float = 15.111
## The intensity multiplier for the blur power effect.
@export_range(0, 20) var blur_power: float = 2.0
## Controls the blur quality behavior.
@export_range(0, 6) var blur_quality: float = 1.0

@export_subgroup("Reflections")
@export var reflections_globalshaderparam: String = ""

@export_subgroup("Performance")
@export var min_step_distance: float = 400.0
## Controls the max step distance behavior.
@export var max_step_distance: float = 500.0
## Controls the lighting travel distance behavior.
@export var lighting_travel_distance: float = 10000.0

@export_subgroup("Mask")
@export var extra_large_used_as_mask: bool = false
## Controls the mask width km behavior.
@export var mask_width_km: float = 32.0

@export_group("Compute Shaders")
@export var pre_pass_compute_shader: RDShaderFile
## The compute shader resource for the compute shader.
@export var compute_shader: RDShaderFile
## The compute shader resource for the post pass compute shader.
@export var post_pass_compute_shader: RDShaderFile

@export_group("Internal Use")
@export var origin_offset: Vector3 = Vector3.ZERO

@export_subgroup("Positions")
@export var wind_direction: Vector3 = Vector3.ZERO

## The 3D world coordinate for the extra large scale clouds position.
var extra_large_scale_clouds_position: Vector3 = Vector3.ZERO
## The 3D world coordinate for the large scale clouds position.
var large_scale_clouds_position: Vector3 = Vector3.ZERO
## The 3D world coordinate for the medium scale clouds position.
var medium_scale_clouds_position: Vector3 = Vector3.ZERO
## The 3D world coordinate for the detail clouds position.
var detail_clouds_position: Vector3 = Vector3.ZERO
## Controls the current time behavior.
var current_time: float = 0.0

@export_subgroup("Lights")
@export var directional_lights_data: Array[Vector4] = []
## Array holding uniform data for point lights data.
@export var point_lights_data: Array[Vector4] = []
## Array holding uniform data for point effector data.
@export var point_effector_data: Array[Vector4] = []

## The 3D world coordinate for the position queries.
var position_queries: Array[Vector3] = []
## The 3D world coordinate for the position query callables.
var position_query_callables: Array[Callable] = []
## The 3D world coordinate for the position querying.
var position_querying: bool = false
## The 3D world coordinate for the position resetting.
var position_resetting: bool = false
## Controls the lights updated behavior.
var lights_updated: bool = false

## Previous frame projection matrix
var _prev_cam_proj: Projection
## Previous frame inverse projection matrix
var _prev_cam_inv_proj: Projection
## Previous frame view matrix
var _prev_cam_view: Projection
## Previous frame inverse view matrix
var _prev_cam_inv_view: Projection
## Whether previous frame matrices are initialized
var _has_prev_matrices: bool = false

## Rendering device handle for the mask drawn rid.
var mask_drawn_rid: RID = RID()
## Controls the rd behavior.
var rd: RenderingDevice
## The compute shader resource for the shader.
var shader: RID = RID()
## Rendering device handle for the pipeline.
var pipeline: RID = RID()
## The compute shader resource for the prepass shader.
var prepass_shader: RID = RID()
## Rendering device handle for the prepass pipeline.
var prepass_pipeline: RID = RID()
## The compute shader resource for the postpass shader.
var postpass_shader: RID = RID()
## Rendering device handle for the postpass pipeline.
var postpass_pipeline: RID = RID()
## The compute shader resource for the display shader.
var display_shader: RID = RID()
## Rendering device handle for the display pipeline.
var display_pipeline: RID = RID()

## Controls the display vertex format behavior.
var display_vertex_format: int
## Rendering device handle for the display vertex buffer.
var display_vertex_buffer: RID = RID()
## Controls the display vertex array behavior.
var display_vertex_array: RID = RID()
## Rendering device handle for the framebuffer format.
var framebuffer_format: int

## Rendering device handle for the nearest sampler.
var nearest_sampler: RID = RID()
## Rendering device handle for the linear sampler.
var linear_sampler: RID = RID()
## Rendering device handle for the linear sampler no repeat.
var linear_sampler_no_repeat: RID = RID()

## Array holding uniform data for general data buffer.
var general_data_buffer: RID = RID()
## Array holding uniform data for light data buffer.
var light_data_buffer: RID = RID()
## Array holding uniform data for point sample data buffer.
var point_sample_data_buffer: RID = RID()
## The accumulation textures texture map applied to the clouds.
var accumulation_textures: Array[RID] = []
## Controls the resized depth behavior.
var resized_depth: RID = RID()

## Controls the last size behavior.
var last_size: Vector2i = Vector2i.ZERO
## The color images used for cloud rendering.
var color_images: Array[RID] = []
## Rendering device handle for the blit screen images.
var blit_screen_images: Array[RID] = []
## Rendering device handle for the buffers.
var buffers: RenderSceneBuffersRD
## Controls the uniform sets behavior.
var uniform_sets: Array[RID] = []

## Controls the accumulation is a behavior.
var accumulation_is_a: bool = false
## Controls the ignore accumilation behavior.
var ignore_accumilation: bool = false
## Controls the first run behavior.
var first_run: bool = true
## Controls the filter index behavior.
var filter_index: int = 0
## Controls the last render target behavior.
var last_render_target: RID

## Controls the last msaa mode behavior.
var last_msaa_mode: RenderingServer.ViewportMSAA = (
	RenderingServer.ViewportMSAA.VIEWPORT_MSAA_DISABLED
)
## Controls the msaa mode behavior.
var msaa_mode: RenderingServer.ViewportMSAA = RenderingServer.ViewportMSAA.VIEWPORT_MSAA_DISABLED

# --- Player Interaction & Public Methods ---


func refresh_compute() -> void:
	print("SunshineCloudsGD: System requesting compute refresh.")
	mask_drawn_rid = RID()
	last_size = Vector2i.ZERO


func update_mask(new_mask: RID) -> void:
	print("SunshineCloudsGD: External mask updated.")
	mask_drawn_rid = new_mask
	last_size = Vector2i.ZERO


func add_sample(callable: Callable, position: Vector3) -> void:
	print("SunshineCloudsGD: Sampling requested at position: ", position)
	position_queries.append(position)
	position_query_callables.append(callable)


# --- Initialization & Rendering Pipeline ---


func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	access_resolved_depth = true
	access_resolved_color = true
	needs_motion_vectors = true
	RenderingServer.call_on_render_thread(initialize_compute)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(self):
		RenderingServer.call_on_render_thread(clear_compute)


func clear_compute() -> void:
	print("SunshineCloudsGD: Freeing rendering resources.")
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


func initialize_compute() -> void:
	print("SunshineCloudsGD: Initializing compute shaders and buffers.")
	first_run = true
	if not rd:
		rd = RenderingServer.get_rendering_device()
		if not rd:
			enabled = false
			printerr("SunshineCloudsGD: No rendering device on load.")
			return

	clear_compute()

	## Rendering device handle for the sampler state.
	var sampler_state: RDSamplerState = RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	nearest_sampler = rd.sampler_create(sampler_state)

	## Rendering device handle for the linear sampler state.
	var linear_sampler_state: RDSamplerState = RDSamplerState.new()
	linear_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	linear_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	linear_sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	linear_sampler = rd.sampler_create(linear_sampler_state)

	## Rendering device handle for the linear sampler state no repeat.
	var linear_sampler_state_no_repeat: RDSamplerState = RDSamplerState.new()
	linear_sampler_state_no_repeat.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler_state_no_repeat.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler_state_no_repeat.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	linear_sampler_state_no_repeat.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	linear_sampler_state_no_repeat.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	linear_sampler_no_repeat = rd.sampler_create(linear_sampler_state_no_repeat)

	# Setup resources
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

	## The compute shader resource for the display shader file.
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
		printerr("SunshineCloudsGD: Missing required shader files.")
		clear_compute()
		return

	## The compute shader resource for the prepass shader spirv.
	var prepass_shader_spirv: RDShaderSPIRV = pre_pass_compute_shader.get_spirv()
	prepass_shader = rd.shader_create_from_spirv(prepass_shader_spirv)
	if prepass_shader.is_valid():
		prepass_pipeline = rd.compute_pipeline_create(prepass_shader)
	else:
		enabled = false
		printerr("SunshineCloudsGD: Prepass Shader failed to compile.")
		clear_compute()
		return

	## The compute shader resource for the shader spirv.
	var shader_spirv: RDShaderSPIRV = compute_shader.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	if shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)
	else:
		enabled = false
		printerr("SunshineCloudsGD: Main Compute Shader failed to compile.")
		clear_compute()
		return

	## The compute shader resource for the postpass shader spirv.
	var postpass_shader_spirv: RDShaderSPIRV = post_pass_compute_shader.get_spirv()
	postpass_shader = rd.shader_create_from_spirv(postpass_shader_spirv)
	if postpass_shader.is_valid():
		postpass_pipeline = rd.compute_pipeline_create(postpass_shader)
	else:
		enabled = false
		printerr("SunshineCloudsGD: Postpass Shader failed to compile.")
		clear_compute()
		return

	## The compute shader resource for the display shader spirv.
	var display_shader_spirv: RDShaderSPIRV = display_shader_file.get_spirv()
	display_shader = rd.shader_create_from_spirv(display_shader_spirv)
	if not display_shader.is_valid():
		enabled = false
		printerr("SunshineCloudsGD: Display Shader failed to compile.")
		clear_compute()
		return

	## Controls the display vertex attributes behavior.
	var display_vertex_attributes: Array[RDVertexAttribute] = [RDVertexAttribute.new()]
	display_vertex_attributes[0].format = RenderingDevice.DataFormat.DATA_FORMAT_R32G32_SFLOAT
	display_vertex_attributes[0].frequency = RenderingDevice.VERTEX_FREQUENCY_VERTEX
	display_vertex_attributes[0].location = 0
	display_vertex_attributes[0].offset = 0
	display_vertex_attributes[0].stride = 8
	display_vertex_format = rd.vertex_format_create(display_vertex_attributes)

	## Array holding uniform data for display vertex data.
	var display_vertex_data: PackedByteArray = (
		PackedFloat32Array(
			[
				-1.0,
				-1.0,
				1.0,
				-1.0,
				-1.0,
				1.0,
				-1.0,
				1.0,
				1.0,
				-1.0,
				1.0,
				1.0,
			]
		)
		. to_byte_array()
	)

	display_vertex_buffer = rd.vertex_buffer_create(display_vertex_data.size(), display_vertex_data)
	display_vertex_array = rd.vertex_array_create(6, display_vertex_format, [display_vertex_buffer])
	last_msaa_mode = msaa_mode


func initialize_raster_pipelines(color_texture: RID, depth_texture: RID) -> void:
	assert(rd != null)
	## Rendering device handle for the framebuffer attachmentformats.
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

	## Rendering device handle for the pipeline rasterization state.
	var pipeline_rasterization_state: RDPipelineRasterizationState = (
		RDPipelineRasterizationState.new()
	)
	## Rendering device handle for the pipeline multisample state.
	var pipeline_multisample_state: RDPipelineMultisampleState = RDPipelineMultisampleState.new()

	match msaa_mode:
		RenderingServer.ViewportMSAA.VIEWPORT_MSAA_2X:
			pipeline_multisample_state.sample_count = (
				RenderingDevice.TextureSamples.TEXTURE_SAMPLES_2
			)
		RenderingServer.ViewportMSAA.VIEWPORT_MSAA_4X:
			pipeline_multisample_state.sample_count = (
				RenderingDevice.TextureSamples.TEXTURE_SAMPLES_4
			)
		RenderingServer.ViewportMSAA.VIEWPORT_MSAA_8X:
			pipeline_multisample_state.sample_count = (
				RenderingDevice.TextureSamples.TEXTURE_SAMPLES_8
			)
		_:
			pipeline_multisample_state.sample_count = (
				RenderingDevice.TextureSamples.TEXTURE_SAMPLES_1
			)

	## Rendering device handle for the pipeline depthstencil state.
	var pipeline_depthstencil_state: RDPipelineDepthStencilState = RDPipelineDepthStencilState.new()
	## The pipeline colorblend state used for cloud rendering.
	var pipeline_colorblend_state: RDPipelineColorBlendState = RDPipelineColorBlendState.new()
	## The pipeline colorblend state attachment used for cloud rendering.
	var pipeline_colorblend_state_attachment: RDPipelineColorBlendStateAttachment = (
		RDPipelineColorBlendStateAttachment.new()
	)
	pipeline_colorblend_state.attachments.append(pipeline_colorblend_state_attachment)

	display_pipeline = rd.render_pipeline_create(
		display_shader,
		framebuffer_format,
		display_vertex_format,
		RenderingDevice.RenderPrimitive.RENDER_PRIMITIVE_TRIANGLES,
		pipeline_rasterization_state,
		pipeline_multisample_state,
		pipeline_depthstencil_state,
		pipeline_colorblend_state
	)


func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
	## The render scene data holding current camera, projection, and depth states.
	var render_scene_data: RenderSceneData = render_data.get_render_scene_data()
	
	if render_scene_data:
		## The active camera projection matrix provided by the renderer.
		var camera_projection: Projection = render_scene_data.get_cam_projection()
		
		# Abort if rendering a shadow map or SDFGI cascade to prevent compute bleed/NaN explosion.
		if camera_projection.is_orthogonal():
			return

	if rd == null:
		initialize_compute()
	elif (
		pipeline.is_valid()
		and height_gradient
		and extra_large_noise_patterns
		and large_scale_noise
		and medium_scale_noise
		and small_scale_noise
		and dither_noise
		and curl_noise
	):
		buffers = render_data.get_render_scene_buffers() as RenderSceneBuffersRD
		if buffers:
			msaa_mode = buffers.get_msaa_3d()
			## Controls the is msaa on behavior.
			var is_msaa_on: bool = msaa_mode != RenderingServer.ViewportMSAA.VIEWPORT_MSAA_DISABLED
			## Controls the size behavior.
			var size: Vector2i = buffers.get_internal_size()
			if size.x == 0 and size.y == 0:
				return

			## The scaling factor applied to the resscale.
			var resscale: int = int(pow(2.0, float(resolution_scale)))
			## Controls the new size behavior.
			var new_size: Vector2i = size / resscale
			## Controls the view count behavior.
			var view_count: int = buffers.get_view_count()

			if (
				size != last_size
				or uniform_sets == null
				or uniform_sets.size() != view_count * 4
				or color_images.size() == 0
				or color_images[0] != buffers.get_color_layer(0)
				or blit_screen_images.size() == 0
				or msaa_mode != last_msaa_mode
			):
				initialize_compute()
				initialize_raster_pipelines(
					buffers.get_color_layer(0, is_msaa_on), buffers.get_depth_layer(0, is_msaa_on)
				)

				accumulation_textures.clear()
				uniform_sets.clear()
				color_images.clear()

				for item: RID in blit_screen_images:
					if item.is_valid():
						rd.free_rid(item)
				blit_screen_images.clear()

				for view in range(view_count):
					color_images.append(buffers.get_color_layer(view, false))
					## Rendering device handle for the depth image.
					var depth_image: RID = buffers.get_depth_layer(view, false)

					## Array holding uniform data for blank image data.
					var blank_image_data: PackedByteArray = PackedByteArray()
					blank_image_data.resize(new_size.x * new_size.y * 16)  # 4 channels * 4 bytes

					## The base colorformat used for cloud rendering.
					var base_colorformat: RDTextureFormat = rd.texture_get_format(
						color_images[view]
					)
					## Controls the blit screen format behavior.
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

					general_data_buffer = rd.uniform_buffer_create(1024)

					## Controls the depthformat behavior.
					var depthformat: RDTextureFormat = rd.texture_get_format(depth_image)
					depthformat.width = new_size.x
					depthformat.height = new_size.y
					depthformat.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
					depthformat.usage_bits = (
						RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
						| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
					)

					resized_depth = rd.texture_create(depthformat, RDTextureView.new(), [])

					# Prepass Uniforms
					## Controls the prepass uniforms array behavior.
					var prepass_uniforms_array: Array[RDUniform] = []

					## Controls the prepass depth uniform behavior.
					var prepass_depth_uniform: RDUniform = RDUniform.new()
					prepass_depth_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					)
					prepass_depth_uniform.binding = 0
					prepass_depth_uniform.add_id(nearest_sampler)
					prepass_depth_uniform.add_id(depth_image)
					prepass_uniforms_array.append(prepass_depth_uniform)

					## Controls the prepass depth output uniform behavior.
					var prepass_depth_output_uniform: RDUniform = RDUniform.new()
					prepass_depth_output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
					prepass_depth_output_uniform.binding = 1
					prepass_depth_output_uniform.add_id(resized_depth)
					prepass_uniforms_array.append(prepass_depth_output_uniform)

					## Controls the prepass camera uniform behavior.
					var prepass_camera_uniform: RDUniform = RDUniform.new()
					prepass_camera_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
					)
					prepass_camera_uniform.binding = 2
					prepass_camera_uniform.add_id(general_data_buffer)
					prepass_uniforms_array.append(prepass_camera_uniform)

					uniform_sets.append(
						rd.uniform_set_create(prepass_uniforms_array, prepass_shader, 0)
					)

					# Main Compute Uniforms
					## Controls the uniforms array behavior.
					var uniforms_array: Array[RDUniform] = []
					for i in range(6):
						## Controls the accum uniform behavior.
						var accum_uniform: RDUniform = RDUniform.new()
						accum_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
						accum_uniform.binding = i
						accum_uniform.add_id(accumulation_textures[(view * 7) + i])
						uniforms_array.append(accum_uniform)

					## Controls the depth uniform behavior.
					var depth_uniform: RDUniform = RDUniform.new()
					depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					depth_uniform.binding = 6
					depth_uniform.add_id(nearest_sampler)
					depth_uniform.add_id(resized_depth)
					uniforms_array.append(depth_uniform)

					## The extra noise uniform texture map applied to the clouds.
					var extra_noise_uniform: RDUniform = RDUniform.new()
					extra_noise_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					)
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
					uniforms_array.append(extra_noise_uniform)

					## The noise samplers texture map applied to the clouds.
					var noise_samplers: Array = [
						large_scale_noise, medium_scale_noise, small_scale_noise, curl_noise
					]
					for i in range(4):
						## The noise uniform texture map applied to the clouds.
						var noise_uniform: RDUniform = RDUniform.new()
						noise_uniform.uniform_type = (
							RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
						)
						noise_uniform.binding = 8 + i
						noise_uniform.add_id(linear_sampler)
						noise_uniform.add_id(
							RenderingServer.texture_get_rd_texture(noise_samplers[i].get_rid())
						)
						uniforms_array.append(noise_uniform)

					## The dither noise uniform texture map applied to the clouds.
					var dither_noise_uniform: RDUniform = RDUniform.new()
					dither_noise_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					)
					dither_noise_uniform.binding = 12
					dither_noise_uniform.add_id(nearest_sampler)
					dither_noise_uniform.add_id(
						RenderingServer.texture_get_rd_texture(dither_noise.get_rid())
					)
					uniforms_array.append(dither_noise_uniform)

					## Controls the height gradient uniform behavior.
					var height_gradient_uniform: RDUniform = RDUniform.new()
					height_gradient_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					)
					height_gradient_uniform.binding = 13
					height_gradient_uniform.add_id(linear_sampler_no_repeat)
					height_gradient_uniform.add_id(
						RenderingServer.texture_get_rd_texture(height_gradient.get_rid())
					)
					uniforms_array.append(height_gradient_uniform)

					## Controls the camera uniform behavior.
					var camera_uniform: RDUniform = RDUniform.new()
					camera_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
					camera_uniform.binding = 14
					camera_uniform.add_id(general_data_buffer)
					uniforms_array.append(camera_uniform)

					light_data_buffer = rd.uniform_buffer_create(6272)
					## Array holding uniform data for light data uniform.
					var light_data_uniform: RDUniform = RDUniform.new()
					light_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
					light_data_uniform.binding = 15
					light_data_uniform.add_id(light_data_buffer)
					uniforms_array.append(light_data_uniform)

					## Array holding uniform data for sample data.
					var sample_data: PackedByteArray = PackedByteArray()
					sample_data.resize(512)
					point_sample_data_buffer = rd.storage_buffer_create(512, sample_data)
					## Array holding uniform data for point sample data uniform.
					var point_sample_data_uniform: RDUniform = RDUniform.new()
					point_sample_data_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
					)
					point_sample_data_uniform.binding = 16
					point_sample_data_uniform.add_id(point_sample_data_buffer)
					uniforms_array.append(point_sample_data_uniform)

					## Array holding uniform data for camera data.
					var camera_data: RID = render_scene_data.get_uniform_buffer()
					## Array holding uniform data for camera data uniform.
					var camera_data_uniform: RDUniform = RDUniform.new()
					camera_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
					camera_data_uniform.binding = 17
					camera_data_uniform.add_id(camera_data)
					uniforms_array.append(camera_data_uniform)

					uniform_sets.append(rd.uniform_set_create(uniforms_array, shader, 0))

					# Postpass Uniforms
					## Controls the postpass uniforms array behavior.
					var postpass_uniforms_array: Array[RDUniform] = []

					## The prepass color data uniform used for cloud rendering.
					var prepass_color_data_uniform: RDUniform = RDUniform.new()
					prepass_color_data_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					)
					prepass_color_data_uniform.binding = 0
					prepass_color_data_uniform.add_id(linear_sampler_no_repeat)
					prepass_color_data_uniform.add_id(accumulation_textures[view * 7])
					postpass_uniforms_array.append(prepass_color_data_uniform)

					## The prepass color uniform used for cloud rendering.
					var prepass_color_uniform: RDUniform = RDUniform.new()
					prepass_color_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					)
					prepass_color_uniform.binding = 1
					prepass_color_uniform.add_id(linear_sampler_no_repeat)
					prepass_color_uniform.add_id(accumulation_textures[(view * 7) + 1])
					postpass_uniforms_array.append(prepass_color_uniform)

					## Controls the postpass reflections uniform behavior.
					var postpass_reflections_uniform: RDUniform = RDUniform.new()
					postpass_reflections_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
					postpass_reflections_uniform.binding = 2
					postpass_reflections_uniform.add_id(accumulation_textures[(view * 7) + 6])
					postpass_uniforms_array.append(postpass_reflections_uniform)

					if reflections_globalshaderparam != "":
						## The new texture texture map applied to the clouds.
						var new_texture: Texture2DRD = Texture2DRD.new()
						new_texture.texture_rd_rid = accumulation_textures[(view * 7) + 6]
						RenderingServer.global_shader_parameter_set(
							reflections_globalshaderparam, new_texture
						)

					## Controls the postpass input screen uniform behavior.
					var postpass_input_screen_uniform: RDUniform = RDUniform.new()
					postpass_input_screen_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					)
					postpass_input_screen_uniform.binding = 3
					postpass_input_screen_uniform.add_id(nearest_sampler)
					postpass_input_screen_uniform.add_id(buffers.get_color_layer(view, is_msaa_on))
					postpass_uniforms_array.append(postpass_input_screen_uniform)

					## Controls the postpass output screen uniform behavior.
					var postpass_output_screen_uniform: RDUniform = RDUniform.new()
					postpass_output_screen_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
					postpass_output_screen_uniform.binding = 4
					postpass_output_screen_uniform.add_id(blit_screen_images[view])
					postpass_uniforms_array.append(postpass_output_screen_uniform)

					## Controls the postpass depth uniform behavior.
					var postpass_depth_uniform: RDUniform = RDUniform.new()
					postpass_depth_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					)
					postpass_depth_uniform.binding = 5
					postpass_depth_uniform.add_id(nearest_sampler)
					postpass_depth_uniform.add_id(buffers.get_depth_layer(view, is_msaa_on))
					postpass_uniforms_array.append(postpass_depth_uniform)

					## Controls the postpass camera uniform behavior.
					var postpass_camera_uniform: RDUniform = RDUniform.new()
					postpass_camera_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
					)
					postpass_camera_uniform.binding = 6
					postpass_camera_uniform.add_id(general_data_buffer)
					postpass_uniforms_array.append(postpass_camera_uniform)

					## Array holding uniform data for postpass light data uniform.
					var postpass_light_data_uniform: RDUniform = RDUniform.new()
					postpass_light_data_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
					)
					postpass_light_data_uniform.binding = 7
					postpass_light_data_uniform.add_id(light_data_buffer)
					postpass_uniforms_array.append(postpass_light_data_uniform)

					## Array holding uniform data for postpass camera data uniform.
					var postpass_camera_data_uniform: RDUniform = RDUniform.new()
					postpass_camera_data_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
					)
					postpass_camera_data_uniform.binding = 8
					postpass_camera_data_uniform.add_id(camera_data)
					postpass_uniforms_array.append(postpass_camera_data_uniform)

					uniform_sets.append(
						rd.uniform_set_create(postpass_uniforms_array, postpass_shader, 0)
					)

					# Display Uniforms
					## Controls the display uniforms array behavior.
					var display_uniforms_array: Array[RDUniform] = []
					## The display screen texture uniform texture map applied to the clouds.
					var display_screen_texture_uniform: RDUniform = RDUniform.new()
					display_screen_texture_uniform.uniform_type = (
						RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					)
					display_screen_texture_uniform.binding = 0
					display_screen_texture_uniform.add_id(nearest_sampler)
					display_screen_texture_uniform.add_id(blit_screen_images[view])
					display_uniforms_array.append(display_screen_texture_uniform)

					uniform_sets.append(
						rd.uniform_set_create(display_uniforms_array, display_shader, 0)
					)

				lights_updated = true

			## The color layer used for cloud rendering.
			var color_layer: RID = buffers.get_color_layer(0, is_msaa_on)
			## Controls the depth layer behavior.
			var depth_layer: RID = buffers.get_depth_layer(0, is_msaa_on)
			## Rendering device handle for the framebuffer.
			var framebuffer: RID = FramebufferCacheRD.get_cache_multipass(
				[color_layer, depth_layer], [], view_count
			)
			assert(framebuffer_format == rd.framebuffer_get_format(framebuffer))

			## Controls the camera tr behavior.
			var camera_tr: Transform3D = render_scene_data.get_cam_transform()
			## Controls the view proj behavior.
			var view_proj: Projection = render_scene_data.get_cam_projection()
			## Controls the rendertarget behavior.
			var rendertarget: RID = buffers.get_render_target()

			if rendertarget != last_render_target:
				last_render_target = rendertarget
				ignore_accumilation = true
			else:
				ignore_accumilation = false

			last_size = size

			if lights_updated or directional_lights_data.size() == 0:
				update_lights()

			if not position_querying and not position_resetting and position_queries.size() > 0:
				encode_sample_points()

			## Controls the prepass x groups behavior.
			var prepass_x_groups: int = ((size.x - 1) / 8) + 1
			## Controls the prepass y groups behavior.
			var prepass_y_groups: int = ((size.y - 1) / 8) + 1
			## Controls the x groups behavior.
			var x_groups: int = ((size.x - 1) / 8 / resscale) + 1
			## Controls the y groups behavior.
			var y_groups: int = ((size.y - 1) / 8 / resscale) + 1

			for view in range(view_count):
				update_matrices(render_scene_data, new_size, view)

				## Controls the prepass list behavior.
				var prepass_list: int = rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(prepass_list, prepass_pipeline)
				rd.compute_list_bind_uniform_set(prepass_list, uniform_sets[view * 4], 0)
				rd.compute_list_dispatch(prepass_list, x_groups, y_groups, 1)
				rd.compute_list_end()

				## Controls the compute list behavior.
				var compute_list: int = rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
				rd.compute_list_bind_uniform_set(compute_list, uniform_sets[(view * 4) + 1], 0)
				rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
				rd.compute_list_end()

				## Controls the postpass list behavior.
				var postpass_list: int = rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(postpass_list, postpass_pipeline)
				rd.compute_list_bind_uniform_set(postpass_list, uniform_sets[(view * 4) + 2], 0)
				rd.compute_list_dispatch(postpass_list, prepass_x_groups, prepass_y_groups, 1)
				rd.compute_list_end()

				## Controls the display list behavior.
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
				rd.buffer_get_data_async(point_sample_data_buffer, retrieve_position_queries.bind())


func retrieve_position_queries(data: PackedByteArray) -> void:
	print("SunshineCloudsGD: Retrieving point sample position queries.")
	## Controls the idx behavior.
	var idx: int = 0
	while idx < 512 and position_query_callables.size() > 0:
		## The 3D world coordinate for the position.
		var position: Vector3 = Vector3.ZERO
		position.x = data.decode_float(idx)
		idx += 4
		position.y = data.decode_float(idx)
		idx += 4
		position.z = data.decode_float(idx)
		idx += 4
		## Controls the thickness and opacity of the density.
		var density: float = data.decode_float(idx)
		idx += 4

		position_query_callables[0].call(position, density)
		position_query_callables.remove_at(0)

	position_querying = false
	position_resetting = false


func update_matrices(
	render_scene_data: RenderSceneData, new_size: Vector2i, view_index: int = 0
) -> void:
	## Array holding uniform data for float data.
	var float_data: PackedFloat32Array = PackedFloat32Array()
	float_data.resize(192)
	## Controls the idx behavior.
	var idx: int = 0

	filter_index += 1
	if filter_index > 16:
		filter_index = 0

	accumulation_is_a = not accumulation_is_a
	first_run = false

	## Controls the width behavior.
	var width: float = mask_width_km * 1000.0

	if extra_large_used_as_mask:
		float_data[idx] = origin_offset.x + ((width * 0.5) * -1.0)
		idx += 1
		float_data[idx] = origin_offset.y + ((width * 0.5) * -1.0)
		idx += 1
		float_data[idx] = origin_offset.z + ((width * 0.5) * -1.0)
		idx += 1
		float_data[idx] = width
		idx += 1
	else:
		float_data[idx] = extra_large_scale_clouds_position.x
		idx += 1
		float_data[idx] = extra_large_scale_clouds_position.y
		idx += 1
		float_data[idx] = extra_large_scale_clouds_position.z
		idx += 1
		float_data[idx] = extra_large_noise_scale
		idx += 1

	float_data[idx] = large_scale_clouds_position.x
	idx += 1
	float_data[idx] = large_scale_clouds_position.y
	idx += 1
	float_data[idx] = large_scale_clouds_position.z
	idx += 1
	float_data[idx] = lighting_sharpness
	idx += 1

	float_data[idx] = medium_scale_clouds_position.x
	idx += 1
	float_data[idx] = medium_scale_clouds_position.y
	idx += 1
	float_data[idx] = medium_scale_clouds_position.z
	idx += 1
	float_data[idx] = lighting_travel_distance
	idx += 1

	float_data[idx] = detail_clouds_position.x
	idx += 1
	float_data[idx] = detail_clouds_position.y
	idx += 1
	float_data[idx] = detail_clouds_position.z
	idx += 1
	float_data[idx] = atmospheric_density
	idx += 1

	float_data[idx] = cloud_ambient_color.r * cloud_ambient_tint.r
	idx += 1
	float_data[idx] = cloud_ambient_color.g * cloud_ambient_tint.g
	idx += 1
	float_data[idx] = cloud_ambient_color.b * cloud_ambient_tint.b
	idx += 1
	float_data[idx] = cloud_ambient_color.a * cloud_ambient_tint.a
	idx += 1

	float_data[idx] = ambient_occlusion_color.r
	idx += 1
	float_data[idx] = ambient_occlusion_color.g
	idx += 1
	float_data[idx] = ambient_occlusion_color.b
	idx += 1
	float_data[idx] = ambient_occlusion_color.a
	idx += 1

	float_data[idx] = lerpf(
		atmosphere_color.r, sampled_environment_fog_color.r, use_environment_fog
	)
	idx += 1
	float_data[idx] = lerpf(
		atmosphere_color.g, sampled_environment_fog_color.g, use_environment_fog
	)
	idx += 1
	float_data[idx] = lerpf(
		atmosphere_color.b, sampled_environment_fog_color.b, use_environment_fog
	)
	idx += 1
	float_data[idx] = lerpf(
		atmosphere_color.a, sampled_environment_fog_color.a, use_environment_fog
	)
	idx += 1

	float_data[idx] = small_noise_scale
	idx += 1
	float_data[idx] = min_step_distance
	idx += 1
	float_data[idx] = max_step_distance
	idx += 1
	float_data[idx] = lod_bias
	idx += 1

	float_data[idx] = clouds_sharpness
	idx += 1
	float_data[idx] = float(directional_lights_data.size()) / 2.0
	idx += 1
	float_data[idx] = clouds_powder
	idx += 1
	float_data[idx] = clouds_anisotropy
	idx += 1

	float_data[idx] = cloud_floor
	idx += 1
	float_data[idx] = cloud_ceiling
	idx += 1
	float_data[idx] = float(max_step_count)
	idx += 1
	float_data[idx] = float(max_lighting_steps)
	idx += 1

	float_data[idx] = use_environment_fog
	idx += 1
	float_data[idx] = float(blur_power)
	idx += 1
	float_data[idx] = float(blur_quality)
	idx += 1
	float_data[idx] = float(curl_noise_strength)
	idx += 1

	float_data[idx] = wind_direction.x
	idx += 1
	float_data[idx] = wind_direction.z
	idx += 1
	float_data[idx] = fog_effect_ground
	idx += 1
	float_data[idx] = position_queries.size()
	idx += 1

	float_data[idx] = float(point_lights_data.size()) / 2.0
	idx += 1
	float_data[idx] = float(point_effector_data.size()) / 2.0
	idx += 1
	float_data[idx] = wind_swept_range
	idx += 1
	float_data[idx] = wind_swept_strength
	idx += 1

	float_data[idx] = new_size.x
	idx += 1
	float_data[idx] = new_size.y
	idx += 1
	float_data[idx] = large_noise_scale
	idx += 1
	float_data[idx] = medium_noise_scale
	idx += 1

	float_data[idx] = current_time
	idx += 1
	float_data[idx] = clouds_coverage
	idx += 1
	float_data[idx] = clouds_density
	idx += 1
	float_data[idx] = clouds_detail_power
	idx += 1

	float_data[idx] = lighting_density
	idx += 1
	float_data[idx] = accumulation_decay if not ignore_accumilation else 0.0
	idx += 1
	float_data[idx] = 1.0 if accumulation_is_a else 0.0
	idx += 1
	float_data[idx] = int(pow(2.0, float(resolution_scale)))

	## Controls the cam proj behavior.
	var cam_proj: Projection = render_scene_data.get_view_projection(view_index)
	## Controls the cam inv proj behavior.
	var cam_inv_proj: Projection = cam_proj.inverse()

	## Controls the cam inv view tr behavior.
	var cam_inv_view_tr: Transform3D = render_scene_data.get_cam_transform()
	## Controls the cam view tr behavior.
	var cam_view_tr: Transform3D = cam_inv_view_tr.inverse()

	## Controls the cam view behavior.
	var cam_view: Projection = Projection(cam_view_tr)
	## Controls the cam inv view behavior.
	var cam_inv_view: Projection = Projection(cam_inv_view_tr)

	## Controls the prev cam proj behavior.
	var prev_cam_proj: Projection = _prev_cam_proj if _has_prev_matrices else cam_proj
	## Controls the prev cam inv proj behavior.
	var prev_cam_inv_proj: Projection = _prev_cam_inv_proj if _has_prev_matrices else cam_inv_proj
	## Controls the prev cam view behavior.
	var prev_cam_view: Projection = _prev_cam_view if _has_prev_matrices else cam_view
	## Controls the prev cam inv view behavior.
	var prev_cam_inv_view: Projection = _prev_cam_inv_view if _has_prev_matrices else cam_inv_view

	_prev_cam_proj = cam_proj
	_prev_cam_inv_proj = cam_inv_proj
	_prev_cam_view = cam_view
	_prev_cam_inv_view = cam_inv_view
	_has_prev_matrices = true

	## Controls the mat idx behavior.
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
		mat_idx += 1
		float_data[mat_idx] = mat.x.y
		mat_idx += 1
		float_data[mat_idx] = mat.x.z
		mat_idx += 1
		float_data[mat_idx] = mat.x.w
		mat_idx += 1
		float_data[mat_idx] = mat.y.x
		mat_idx += 1
		float_data[mat_idx] = mat.y.y
		mat_idx += 1
		float_data[mat_idx] = mat.y.z
		mat_idx += 1
		float_data[mat_idx] = mat.y.w
		mat_idx += 1
		float_data[mat_idx] = mat.z.x
		mat_idx += 1
		float_data[mat_idx] = mat.z.y
		mat_idx += 1
		float_data[mat_idx] = mat.z.z
		mat_idx += 1
		float_data[mat_idx] = mat.z.w
		mat_idx += 1
		float_data[mat_idx] = mat.w.x
		mat_idx += 1
		float_data[mat_idx] = mat.w.y
		mat_idx += 1
		float_data[mat_idx] = mat.w.z
		mat_idx += 1
		float_data[mat_idx] = mat.w.w
		mat_idx += 1

	## Array holding uniform data for general byte data.
	var general_byte_data: PackedByteArray = float_data.to_byte_array()
	rd.buffer_update(general_data_buffer, 0, general_byte_data.size(), general_byte_data)


func update_lights() -> void:
	print("SunshineCloudsGD: Passing updated light structure to storage buffers.")
	lights_updated = false

	if directional_lights_data.size() == 0:
		directional_lights_data.append(Vector4(0.5, 1.0, 0.5, 16.0))
		directional_lights_data.append(Vector4(1.0, 1.0, 1.0, 1.0))

	# 1568 total floats -> 6272 bytes
	## Array holding uniform data for float data.
	var float_data: PackedFloat32Array = PackedFloat32Array()
	float_data.resize(1568)

	## Controls the idx behavior.
	var idx: int = 0
	## Controls the max dir behavior.
	var max_dir: int = min(directional_lights_data.size(), 8)
	for i in range(max_dir):
		float_data[idx] = directional_lights_data[i].x
		idx += 1
		float_data[idx] = directional_lights_data[i].y
		idx += 1
		float_data[idx] = directional_lights_data[i].z
		idx += 1
		float_data[idx] = directional_lights_data[i].w
		idx += 1

	idx = 32  # 128 bytes / 4
	## Controls the max pts behavior.
	var max_pts: int = min(point_lights_data.size(), 256)
	for i in range(max_pts):
		float_data[idx] = point_lights_data[i].x
		idx += 1
		float_data[idx] = point_lights_data[i].y
		idx += 1
		float_data[idx] = point_lights_data[i].z
		idx += 1
		float_data[idx] = point_lights_data[i].w
		idx += 1

	idx = 1056  # 4224 bytes / 4
	## Controls the max eff behavior.
	var max_eff: int = min(point_effector_data.size(), 128)
	for i in range(max_eff):
		float_data[idx] = point_effector_data[i].x
		idx += 1
		float_data[idx] = point_effector_data[i].y
		idx += 1
		float_data[idx] = point_effector_data[i].z
		idx += 1
		float_data[idx] = point_effector_data[i].w
		idx += 1

	## Array holding uniform data for light byte data.
	var light_byte_data: PackedByteArray = float_data.to_byte_array()
	rd.buffer_update(light_data_buffer, 0, light_byte_data.size(), light_byte_data)


func encode_sample_points() -> void:
	print("SunshineCloudsGD: Encoding sample points into storage buffer.")
	position_querying = true

	## Array holding uniform data for float data.
	var float_data: PackedFloat32Array = PackedFloat32Array()
	float_data.resize(128)  # 512 bytes / 4 = 128 floats

	## Controls the idx behavior.
	var idx: int = 0
	while idx < 128 and position_queries.size() > 0:
		## Controls the pos behavior.
		var pos: Vector3 = position_queries[0]
		float_data[idx] = pos.x
		idx += 1
		float_data[idx] = pos.y
		idx += 1
		float_data[idx] = pos.z
		idx += 1
		float_data[idx] = 0.0
		idx += 1
		position_queries.remove_at(0)

	## Array holding uniform data for sample byte data.
	var sample_byte_data: PackedByteArray = float_data.to_byte_array()
	rd.buffer_update(point_sample_data_buffer, 0, sample_byte_data.size(), sample_byte_data)
