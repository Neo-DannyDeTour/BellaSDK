@tool
## Controls the ocean water plane, GPU wave simulation bindings, and spray positioning.
class_name Ocean
extends MeshInstance3D

## Mesh quality level determining polygon density.
enum MeshQuality {
	LOW,
	HIGH,
	HIGH8K,
}

## Available square resolution dimensions for generated wave maps.
enum WaveMapResolution {
	RES_128 = 128,
	RES_256 = 256,
	RES_512 = 512,
	RES_1024 = 1024,
}

## Shader material applied to the ocean surface mesh.
const WATER_MAT: ShaderMaterial = preload("res://dynamic_ocean/materials/mat_ocean.tres")
## Shader material applied to spray particle emissions.
const SPRAY_MAT: ShaderMaterial = preload("res://dynamic_ocean/materials/mat_spray.tres")
## Ultra-high density clipmap mesh asset.
const WATER_MESH_HIGH8_K: Mesh = preload("res://dynamic_ocean/meshes/clipmap_high_8k.obj")
## Standard high density clipmap mesh asset.
const WATER_MESH_HIGH: Mesh = preload("res://dynamic_ocean/meshes/clipmap_high.obj")
## Low density clipmap mesh asset.
const WATER_MESH_LOW: Mesh = preload("res://dynamic_ocean/meshes/clipmap_low.obj")

## Global and material shader parameter names.
const PARAM_WATER_COLOR: StringName = &"water_color"
const PARAM_FOAM_COLOR: StringName = &"foam_color"
const PARAM_CREST_COLOR: StringName = &"crest_color"
const PARAM_CREST_GLOW: StringName = &"crest_glow_intensity"
const PARAM_AERATED_GLOW: StringName = &"aerated_foam_glow"
const PARAM_NUM_CASCADES: StringName = &"num_cascades"
const PARAM_DISPLACEMENTS: StringName = &"displacements"
const PARAM_NORMALS: StringName = &"normals"
const PARAM_MAP_SCALES: StringName = &"map_scales"
const PARAM_SPAWN_RADIUS: StringName = &"spawn_radius"
## Compute descriptor key for downsampled CPU buoyancy map.
const DESC_DOWNSAMPLED: StringName = &"downsampled_map"

@export_group("Optimization & Targets")

## The target node that the water simulation will track.
@export var player_target: Node3D

## Maximum distance in meters from the ocean boundary before simulation throttles.
@export var max_sim_distance: float = 150.0

## Target simulation framerate when viewer is beyond max_sim_distance from boundary.
@export_range(5.0, 60.0, 1.0) var distant_sim_fps: float = 35.0

## Defines the total size of your ocean plane to keep particles inside.
## Defines the total size of your ocean plane to keep particles inside.
@export var ocean_plane_size: float = 300.0:
	set(value):
		ocean_plane_size = value
		_update_visibility_notifier_aabb()

## Controls the spawn radius for spray particles across the ocean surface.
@export var spray_spawn_radius: float = 150.0:
	set(value):
		spray_spawn_radius = value
		if is_inside_tree():
			_update_scales_uniform()

## Reference to the GPU particle system for generating spray.
@export var spray_particles: GPUParticles3D:
	set(value):
		spray_particles = value
		if is_inside_tree():
			_update_scales_uniform()

@export_group("Colors & Subsurface Glow")

## Base color of the deep water.
@export_color_no_alpha var water_color: Color = Color(0.01, 0.02, 0.03):
	set(value):
		water_color = value
		RenderingServer.global_shader_parameter_set(PARAM_WATER_COLOR, water_color.srgb_to_linear())

## Color of the foam generated on wave crests and trails.
@export_color_no_alpha var foam_color: Color = Color(0.9, 0.9, 0.95):
	set(value):
		foam_color = value
		RenderingServer.global_shader_parameter_set(PARAM_FOAM_COLOR, foam_color.srgb_to_linear())

## Subsurface scattering color visible through the peaks of waves.
@export_color_no_alpha var crest_color: Color = Color(0.0, 0.65, 0.85):
	set(value):
		crest_color = value
		if is_instance_valid(WATER_MAT):
			WATER_MAT.set_shader_parameter(PARAM_CREST_COLOR, crest_color)

## Controls the intensity of the light passing through wave peaks.
@export_range(0.0, 2.0) var crest_glow_intensity: float = 0.8:
	set(value):
		crest_glow_intensity = value
		if is_instance_valid(WATER_MAT):
			WATER_MAT.set_shader_parameter(PARAM_CREST_GLOW, crest_glow_intensity)

## Controls how much ambient light is captured by heavily aerated foam.
@export_range(0.0, 2.0) var aerated_foam_glow: float = 0.5:
	set(value):
		aerated_foam_glow = value
		if is_instance_valid(WATER_MAT):
			WATER_MAT.set_shader_parameter(PARAM_AERATED_GLOW, aerated_foam_glow)

@export_group("Wave Parameters")

## Parameter configurations used to generate multi-frequency wave cascades.
@export var parameters: Array[WaveCascadeParameters]:
	set(value):
		_disconnect_parameter_signals()
		var new_size: int = value.size()
		for i: int in range(new_size):
			if not value[i]:
				value[i] = WaveCascadeParameters.new()
			if not value[i].scale_changed.is_connected(_update_scales_uniform):
				value[i].scale_changed.connect(_update_scales_uniform)
			value[i].spectrum_seed = Vector2i(
				rng.randi_range(-10000, 10000), rng.randi_range(-10000, 10000)
			)
			value[i].time = 120.0 + PI * float(i)
		parameters = value

		if not is_inside_tree():
			return

		_setup_wave_generator()
		_update_scales_uniform()
		_setup_cpu_displacement_textures()

@export_group("Performance Parameters")

## Resolution of the generated wave maps. Higher values cost more performance.
@export var map_size: WaveMapResolution = WaveMapResolution.RES_1024:
	set(value):
		map_size = value
		print("Ocean: Updating map_size to: ", map_size)
		if is_inside_tree():
			_setup_wave_generator()

## Level of detail for the actual ocean mesh geometry.
@export var mesh_quality: MeshQuality = MeshQuality.HIGH:
	set(value):
		mesh_quality = value
		if mesh_quality == MeshQuality.LOW:
			mesh = WATER_MESH_LOW
		elif mesh_quality == MeshQuality.HIGH:
			mesh = WATER_MESH_HIGH
		elif mesh_quality == MeshQuality.HIGH8K:
			mesh = WATER_MESH_HIGH8_K

@export_group("Tools & Actions")

## Triggers the process to bake the current wave states into a static resource.
@export var bake_waves_to_res: bool = false:
	set(value):
		if value and is_inside_tree():
			bake_waves_to_res_routine()
		bake_waves_to_res = false

## Triggers a hard reset of all wave cascades to their default settings.
@export var reset_cascades: bool = false:
	set(value):
		if value and is_inside_tree():
			force_reset_cascades()
		reset_cascades = false

## Random number generator instance used for procedural spectrum seeding.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The active wave generator child node driving GPU compute passes.
var wave_generator: WaveGenerator

## Total accumulated simulation time.
var time: float = 0.0

## Texture array referencing displacement map slices on the GPU.
var displacement_maps: Texture2DArrayRD = Texture2DArrayRD.new()

## Texture array referencing normal map slices on the GPU.
var normal_maps: Texture2DArrayRD = Texture2DArrayRD.new()

## Controls whether CPU readback updates are active.
var update_textures: bool = true

## Flag indicating whether water height calculations completed for the frame.
var just_calculated_water: bool = false

## Thread lock for synchronizing CPU displacement image accesses.
var mutex: Mutex = Mutex.new()

## Cache of CPU-side displacement images for physical height sampling.
var cpu_displacement_textures: Dictionary[int, Image] = {}

## Pre-allocated array of cascade indices to avoid per-frame keys() allocation.
var _cpu_displacement_keys: PackedInt32Array = PackedInt32Array()

## Target time interval for refreshing CPU displacement textures.
var _displacement_textures_total_update_interval: float = 1.0 / 30.0

## Elapsed timer tracking intervals between CPU readbacks.
var _displacement_textures_update_time: float = 0.0

## Current index in the cascade queue being read back to the CPU.
var _texture_loading_index: int = 0

## Guards against simultaneous asynchronous GPU readback operations.
var _is_reading_back: bool = false

## Position of the camera in the previous frame to identify rapid movement.
var _last_cam_pos: Vector3 = Vector3.ZERO

## Cached active camera reference.
var _cached_camera: Camera3D = null

## Throttle accumulator for updating distant ocean simulations.
var _distant_timer: float = 0.0

## Frustum notifier used to pause GPU wave dispatches when off-screen.
var _visibility_notifier: VisibleOnScreenNotifier3D = null


## Sets up default seed values on instantiation.
func _init() -> void:
	rng.set_seed(1234)


## Initializes global shader parameters when entering the tree.
func _enter_tree() -> void:
	RenderingServer.global_shader_parameter_set(PARAM_WATER_COLOR, water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(PARAM_FOAM_COLOR, foam_color.srgb_to_linear())


## Disconnects shared resource signals and releases RD texture wrappers on exit.
func _exit_tree() -> void:
	_disconnect_parameter_signals()
	_clear_rd_texture_refs()


## Prepares culling bounds, wave generator, and runs initial GPU compute pass.
func _ready() -> void:
	print("Ocean: Executing _ready() and forcing initial wave calculations.")
	extra_cull_margin = 150.0
	RenderingServer.global_shader_parameter_set(PARAM_WATER_COLOR, water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(PARAM_FOAM_COLOR, foam_color.srgb_to_linear())

	if parameters != null and not parameters.is_empty():
		for i: int in range(parameters.size()):
			if is_instance_valid(parameters[i]):
				if not parameters[i].scale_changed.is_connected(_update_scales_uniform):
					parameters[i].scale_changed.connect(_update_scales_uniform)
		_setup_wave_generator()
		_update_scales_uniform()
		_update_water(0.016)
		_setup_cpu_displacement_textures()

	if not Engine.is_editor_hint():
		_setup_visibility_notifier()


## Drives spray emitter position tracking and boundary-aware simulation steps.
func _process(delta: float) -> void:
	var cam: Camera3D = _get_camera()
	var tracker_node: Node3D = player_target if is_instance_valid(player_target) else cam
	var target_pos: Vector3 = (
		tracker_node.global_position if is_instance_valid(tracker_node) else global_position
	)

	if is_instance_valid(spray_particles):
		var local_target: Vector3 = target_pos - global_position
		var max_dist: float = maxf(0.0, (ocean_plane_size * 0.5) - spray_spawn_radius)
		local_target.x = clampf(local_target.x, -max_dist, max_dist)
		local_target.z = clampf(local_target.z, -max_dist, max_dist)
		spray_particles.global_position = (
			global_position + Vector3(local_target.x, 0.0, local_target.z)
		)

	if Engine.is_editor_hint():
		_update_water(delta)
		time += delta
		return

	var sim_delta: float = delta
	var is_distant: bool = false
	if is_instance_valid(tracker_node):
		var dist_sq: float = _get_boundary_distance_squared(target_pos)
		if dist_sq > max_sim_distance * max_sim_distance:
			is_distant = true
			_distant_timer += delta
			var step_interval: float = 1.0 / maxf(5.0, distant_sim_fps)
			if _distant_timer < step_interval:
				return
			sim_delta = _distant_timer
			_distant_timer = 0.0
		else:
			_distant_timer = 0.0

	if is_instance_valid(cam):
		var distance_moved_sq: float = _last_cam_pos.distance_squared_to(cam.global_position)
		_last_cam_pos = cam.global_position
		update_textures = (distance_moved_sq <= 25.0) and not is_distant

	just_calculated_water = false
	_update_water(sim_delta)

	if update_textures:
		_manage_cpu_displacement_textures_updates(sim_delta)

	just_calculated_water = true
	time += sim_delta


## Handles cleanup before deletion to avoid dangling GPU references.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_clear_rd_texture_refs()


## Computes ocean wave height displacement using GPU textures or Gerstner wave.
func get_height(world_pos: Vector3, steps: int = 3) -> float:
	var world_pos_xz: Vector2 = Vector2(world_pos.x, world_pos.z)
	var summed_height: float = 0.0

	mutex.lock()
	if is_instance_valid(wave_generator) and not _cpu_displacement_keys.is_empty():
		var map_size_cache: int = wave_generator.cpu_map_size
		var map_size_float: float = float(map_size_cache)
		for idx: int in _cpu_displacement_keys:
			if not cpu_displacement_textures.has(idx):
				continue
			var img: Image = cpu_displacement_textures[idx]
			if not is_instance_valid(img):
				continue

			var disp_scale: float = parameters[idx].displacement_scale
			var tile_length: Vector2 = parameters[idx].tile_length
			var sample_pos: Vector2 = world_pos_xz
			var horiz_offset: Vector2 = Vector2.ZERO
			var pixel_col: Color = Color.BLACK

			for step_idx: int in range(steps):
				var img_v: Vector2 = _world_to_uv(sample_pos, tile_length) * map_size_float
				var pixel_x: int = wrapi(int(img_v.x), 0, map_size_cache)
				var pixel_y: int = wrapi(int(img_v.y), 0, map_size_cache)
				pixel_col = img.get_pixel(pixel_x, pixel_y)
				horiz_offset = Vector2(pixel_col.r, pixel_col.b)
				sample_pos = world_pos_xz - horiz_offset

			summed_height += pixel_col.g * disp_scale
	else:
		for i: int in range(parameters.size()):
			var cascade: WaveCascadeParameters = parameters[i]
			if cascade.displacement_scale > 0.001:
				var disp: Vector3 = MathUtils.gerstner_wave(
					world_pos, Vector2(1.0, 0.2), 0.35, cascade.tile_length.x, time
				)
				summed_height += disp.y * cascade.displacement_scale
	mutex.unlock()
	return summed_height


## Bakes an animated sequence of displacement maps into a static Texture2DArray.
func bake_waves_to_res_routine() -> void:
	print("Ocean: Executing bake_waves_to_res_routine().")
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	if not device or not is_instance_valid(wave_generator):
		printerr("Ocean: Cannot bake waves without valid GPU resources.")
		return

	var frames_to_bake: int = 64
	var time_step: float = 0.05
	var cascade_to_bake: int = 0
	var total_duration: float = float(frames_to_bake) * time_step

	for p: WaveCascadeParameters in parameters:
		p.loop_period = total_duration
		p.time = 0.0
		p.should_generate_spectrum = true

	_update_water(0.0)
	RenderingServer.force_sync()

	var disp_desc: RenderingContext.Descriptor = wave_generator.descriptors[&"displacement_map"]
	var rid_disp_map: RID = disp_desc.rid
	var baked_images: Array[Image] = []

	for frame: int in range(frames_to_bake):
		_update_water(time_step)
		RenderingServer.force_sync()

		var tex: PackedByteArray = device.texture_get_data(rid_disp_map, cascade_to_bake)
		var img: Image = Image.create_from_data(
			wave_generator.map_size, wave_generator.map_size, false, Image.FORMAT_RGBAH, tex
		)
		baked_images.append(img)

	for p: WaveCascadeParameters in parameters:
		p.loop_period = 0.0
		p.should_generate_spectrum = true

	var texture_array: Texture2DArray = Texture2DArray.new()
	var err: Error = texture_array.create_from_images(baked_images)
	if err == OK:
		var save_path: String = "res://baked_waves/baked_ocean_array.res"
		ResourceSaver.save(texture_array, save_path)


## Resets cascade configuration parameters back to standard baseline presets.
func force_reset_cascades() -> void:
	print("Ocean: Force resetting cascade parameters.")
	if parameters.is_empty():
		return
	var default_tiles: Array[Vector2] = [
		Vector2(256.0, 256.0),
		Vector2(67.0, 67.0),
		Vector2(17.0, 17.0),
	]
	for i: int in range(parameters.size()):
		var p: WaveCascadeParameters = parameters[i]
		p.tile_length = default_tiles[i] if i < default_tiles.size() else Vector2(50.0, 50.0)
		p.displacement_scale = 1.0
		p.wind_speed = 15.0
		p.fetch_length = 100.0
		p.swell = 0.5
		p.spread = 0.5
		p.detail = 1.0
		p.should_generate_spectrum = true
	_update_scales_uniform()


## Computes squared distance from a world point to the nearest point on the ocean XZ bounds.
func _get_boundary_distance_squared(world_point: Vector3) -> float:
	var half_extent: float = ocean_plane_size * 0.5
	var nearest_point: Vector3 = Vector3(
		clampf(world_point.x, global_position.x - half_extent, global_position.x + half_extent),
		global_position.y,
		clampf(world_point.z, global_position.z - half_extent, global_position.z + half_extent)
	)
	return world_point.distance_squared_to(nearest_point)


## Unbinds Texture2DArrayRD wrappers before underlying RD textures are freed.
func _clear_rd_texture_refs() -> void:
	RenderingServer.global_shader_parameter_set(PARAM_DISPLACEMENTS, null)
	RenderingServer.global_shader_parameter_set(PARAM_NORMALS, null)
	if is_instance_valid(displacement_maps):
		displacement_maps.texture_rd_rid = RID()
	if is_instance_valid(normal_maps):
		normal_maps.texture_rd_rid = RID()


## Disconnects scale_changed signals from current WaveCascadeParameters.
func _disconnect_parameter_signals() -> void:
	if parameters == null:
		return
	for param: WaveCascadeParameters in parameters:
		if is_instance_valid(param) and param.scale_changed.is_connected(_update_scales_uniform):
			param.scale_changed.disconnect(_update_scales_uniform)


## Configures the wave generator child node synchronously.
func _setup_wave_generator() -> void:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if not is_instance_valid(rd):
		printerr("Ocean: RenderingDevice is null. Skipping GPU init.")
		return

	if parameters == null or parameters.is_empty():
		return

	print("Ocean: Initializing wave generator with ", parameters.size(), " cascades.")
	_clear_rd_texture_refs()

	for param: WaveCascadeParameters in parameters:
		if is_instance_valid(param):
			param.should_generate_spectrum = true

	if not is_instance_valid(wave_generator):
		wave_generator = WaveGenerator.new()
		wave_generator.name = "WaveGenerator"
		if not wave_generator.textures_created.is_connected(_on_wave_textures_created):
			wave_generator.textures_created.connect(_on_wave_textures_created)
		add_child(wave_generator)

	wave_generator.map_size = map_size
	wave_generator.init_gpu(maxi(2, parameters.size()))


## Updates global shader parameters when new RD textures are created.
func _on_wave_textures_created(disp_rid: RID, norm_rid: RID) -> void:
	print("Ocean: Received new texture RIDs from WaveGenerator.")
	if not disp_rid.is_valid() or not norm_rid.is_valid():
		return

	displacement_maps.texture_rd_rid = disp_rid
	normal_maps.texture_rd_rid = norm_rid

	RenderingServer.global_shader_parameter_set(PARAM_NUM_CASCADES, parameters.size())
	RenderingServer.global_shader_parameter_set(PARAM_DISPLACEMENTS, displacement_maps)
	RenderingServer.global_shader_parameter_set(PARAM_NORMALS, normal_maps)


## Updates uniform map scales on ocean and spray materials.
func _update_scales_uniform() -> void:
	if parameters == null or parameters.is_empty():
		return
	var map_scales: PackedVector4Array = PackedVector4Array()
	map_scales.resize(parameters.size())
	for i: int in range(parameters.size()):
		var params: WaveCascadeParameters = parameters[i]
		var uv_scale: Vector2 = Vector2.ONE / params.tile_length
		map_scales[i] = Vector4(
			uv_scale.x, uv_scale.y, params.displacement_scale, params.normal_scale
		)

	if is_instance_valid(WATER_MAT):
		WATER_MAT.set_shader_parameter(PARAM_MAP_SCALES, map_scales)
	if is_instance_valid(SPRAY_MAT):
		SPRAY_MAT.set_shader_parameter(PARAM_MAP_SCALES, map_scales)
		SPRAY_MAT.set_shader_parameter(PARAM_SPAWN_RADIUS, spray_spawn_radius)
	if is_instance_valid(spray_particles):
		var proc_mat: ShaderMaterial = spray_particles.process_material as ShaderMaterial
		if is_instance_valid(proc_mat):
			proc_mat.set_shader_parameter(PARAM_MAP_SCALES, map_scales)
			proc_mat.set_shader_parameter(PARAM_SPAWN_RADIUS, spray_spawn_radius)


## Updates the water simulation through the wave generator.
func _update_water(delta: float) -> void:
	if not RenderingServer.get_rendering_device():
		return

	if not is_instance_valid(wave_generator):
		_setup_wave_generator()

	if is_instance_valid(wave_generator) and wave_generator.is_initialized:
		wave_generator.update(delta, parameters)


## Manages asynchronous round-robin readbacks of displacement maps to the CPU.
func _manage_cpu_displacement_textures_updates(delta: float) -> void:
	if _cpu_displacement_keys.is_empty() or _is_reading_back:
		return

	var cache_size: int = _cpu_displacement_keys.size()
	var time_per_tex: float = _displacement_textures_total_update_interval / float(cache_size)

	if _displacement_textures_update_time > time_per_tex:
		_texture_loading_index = (_texture_loading_index + 1) % cache_size
		var target_idx: int = _cpu_displacement_keys[_texture_loading_index]
		_is_reading_back = true
		RenderingServer.call_on_render_thread(_do_texture_readback.bind(target_idx))
		_displacement_textures_update_time = 0.0

	_displacement_textures_update_time += delta


## Dispatches an asynchronous GPU texture download request for the cascade.
func _do_texture_readback(idx: int) -> void:
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	if not device or not is_instance_valid(wave_generator):
		_is_reading_back = false
		return

	if not wave_generator.descriptors.has(DESC_DOWNSAMPLED):
		_is_reading_back = false
		return

	var desc: RenderingContext.Descriptor = wave_generator.descriptors[DESC_DOWNSAMPLED]
	if not desc.rid.is_valid():
		_is_reading_back = false
		return

	var callable: Callable = _on_texture_data_received.bind(idx)
	var err: Error = device.texture_get_data_async(desc.rid, idx, callable)
	if err != OK:
		_is_reading_back = false


## Ingests downsampled texture byte data received asynchronously from the GPU.
func _on_texture_data_received(tex: PackedByteArray, idx: int) -> void:
	if not is_instance_valid(wave_generator) or tex.is_empty():
		_is_reading_back = false
		return

	var img: Image = Image.create_from_data(
		wave_generator.cpu_map_size, wave_generator.cpu_map_size, false, Image.FORMAT_RGBAH, tex
	)
	mutex.lock()
	cpu_displacement_textures[idx] = img
	_is_reading_back = false
	mutex.unlock()


## Schedules initial displacement map readbacks for CPU physics.
func _setup_cpu_displacement_textures() -> void:
	var used_idx: Array[int] = []
	for i: int in range(parameters.size()):
		var cascade: WaveCascadeParameters = parameters[i]
		if cascade.displacement_scale > 0.001:
			used_idx.append(i)

	RenderingServer.call_on_render_thread(_do_initial_texture_readback.bind(used_idx))


## Performs initial download of downsampled 128x128 maps on the render thread.
func _do_initial_texture_readback(used_indices: Array[int]) -> void:
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	if not device or not is_instance_valid(wave_generator):
		return

	if not wave_generator.descriptors.has(DESC_DOWNSAMPLED):
		return

	var desc: RenderingContext.Descriptor = wave_generator.descriptors[DESC_DOWNSAMPLED]
	if not desc.rid.is_valid():
		return

	mutex.lock()
	_cpu_displacement_keys.clear()
	for i: int in used_indices:
		var tex: PackedByteArray = device.texture_get_data(desc.rid, i)
		if tex.is_empty():
			continue

		var img: Image = Image.create_from_data(
			wave_generator.cpu_map_size, wave_generator.cpu_map_size, false, Image.FORMAT_RGBAH, tex
		)
		if is_instance_valid(img):
			cpu_displacement_textures[i] = img
			_cpu_displacement_keys.append(i)
	mutex.unlock()


## Converts world space coordinates to repeating UV coordinates for a tile.
func _world_to_uv(w: Vector2, tile_length: Vector2) -> Vector2:
	return Vector2(
		fposmod(w.x, tile_length.x) / tile_length.x, fposmod(w.y, tile_length.y) / tile_length.y
	)


## Retrieves and caches the active camera node from the main viewport.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		var vp: Viewport = get_viewport()
		if is_instance_valid(vp):
			_cached_camera = vp.get_camera_3d()
	return _cached_camera


## Creates and binds the VisibleOnScreenNotifier3D child for frustum gating.
func _setup_visibility_notifier() -> void:
	if is_instance_valid(_visibility_notifier):
		return
	_visibility_notifier = VisibleOnScreenNotifier3D.new()
	_visibility_notifier.name = "OceanVisibilityNotifier"
	_update_visibility_notifier_aabb()
	if not _visibility_notifier.screen_entered.is_connected(_on_screen_entered):
		_visibility_notifier.screen_entered.connect(_on_screen_entered)
	if not _visibility_notifier.screen_exited.is_connected(_on_screen_exited):
		_visibility_notifier.screen_exited.connect(_on_screen_exited)
	add_child(_visibility_notifier)


## Updates the frustum culling AABB to match ocean_plane_size.
func _update_visibility_notifier_aabb() -> void:
	if not is_instance_valid(_visibility_notifier):
		return
	var half: float = ocean_plane_size * 0.5
	_visibility_notifier.aabb = AABB(
		Vector3(-half, -25.0, -half), Vector3(ocean_plane_size, 50.0, ocean_plane_size)
	)


## Resumes ocean simulation and spray emission when entering the camera frustum.
func _on_screen_entered() -> void:
	print("Ocean: Entered screen frustum. Resuming simulation.")
	set_process(true)
	if is_instance_valid(spray_particles):
		spray_particles.emitting = true


## Pauses ocean simulation when off-screen unless the target is inside the bounds.
func _on_screen_exited() -> void:
	var cam: Camera3D = _get_camera()
	var tracker_node: Node3D = player_target if is_instance_valid(player_target) else cam
	if is_instance_valid(tracker_node):
		if _get_boundary_distance_squared(tracker_node.global_position) <= 25.0:
			return
	print("Ocean: Exited screen frustum. Pausing simulation.")
	set_process(false)
	if is_instance_valid(spray_particles):
		spray_particles.emitting = false
