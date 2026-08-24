@tool
extends MeshInstance3D
## Controls the ocean water plane, GPU wave simulation bindings, and spray positioning.

## Mesh quality level determining polygon density.
enum MeshQuality {
	LOW,
	HIGH,
	HIGH8K,
}

## Material applied to the ocean surface mesh.
const WATER_MAT: Material = preload("res://environment/mat_ocean.tres")
## Material applied to spray particle emissions.
const SPRAY_MAT: Material = preload("res://environment/mat_spray.tres")
## Ultra-high density clipmap mesh asset.
const WATER_MESH_HIGH8_K: Mesh = preload("res://assets/ocean_waves/ocean/clipmap_high_8k.obj")
## Standard high density clipmap mesh asset.
const WATER_MESH_HIGH: Mesh = preload("res://assets/ocean_waves/ocean/clipmap_high.obj")
## Low density clipmap mesh asset.
const WATER_MESH_LOW: Mesh = preload("res://assets/ocean_waves/ocean/clipmap_low.obj")

@export_group("Optimization & Targets")

## The target node (usually the player) that the water simulation will track.
@export var player_target: Node3D

## Maximum distance from the target before the simulation suspends.
@export var max_sim_distance: float = 300.0

## Defines the total size of your ocean plane to keep particles inside.
@export var ocean_plane_size: float = 300.0

## Controls the spawn radius for spray particles across the ocean surface.
@export var spray_spawn_radius: float = 150.0:
	set(value):
		spray_spawn_radius = value
		_update_scales_uniform()

## Reference to the GPU particle system for generating spray.
@export var spray_particles: GPUParticles3D:
	set(value):
		spray_particles = value
		_update_scales_uniform()

@export_group("Colors & Subsurface Glow")

## Base color of the deep water.
@export_color_no_alpha var water_color: Color = Color(0.01, 0.02, 0.03):
	set(value):
		water_color = value
		RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())

## Color of the foam generated on wave crests and trails.
@export_color_no_alpha var foam_color: Color = Color(0.9, 0.9, 0.95):
	set(value):
		foam_color = value
		RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())

## Subsurface scattering color visible through the peaks of waves.
@export_color_no_alpha var crest_color: Color = Color(0.0, 0.65, 0.85):
	set(value):
		crest_color = value
		if WATER_MAT:
			WATER_MAT.set_shader_parameter("crest_color", crest_color)

## Controls the intensity of the light passing through wave peaks.
@export_range(0.0, 2.0) var crest_glow_intensity: float = 0.8:
	set(value):
		crest_glow_intensity = value
		if WATER_MAT:
			WATER_MAT.set_shader_parameter("crest_glow_intensity", crest_glow_intensity)

## Controls how much ambient light is captured by heavily aerated foam.
@export_range(0.0, 2.0) var aerated_foam_glow: float = 0.5:
	set(value):
		aerated_foam_glow = value
		if WATER_MAT:
			WATER_MAT.set_shader_parameter("aerated_foam_glow", aerated_foam_glow)

@export_group("Wave Parameters")

## Parameter configurations used to generate multi-frequency wave cascades.
@export var parameters: Array[WaveCascadeParameters]:
	set(value):
		var new_size: int = value.size()
		for i: int in range(new_size):
			if not value[i]:
				value[i] = WaveCascadeParameters.new()
			if not value[i].is_connected(&"scale_changed", _update_scales_uniform):
				value[i].scale_changed.connect(_update_scales_uniform)
			value[i].spectrum_seed = Vector2i(
				rng.randi_range(-10000, 10000), rng.randi_range(-10000, 10000)
			)
			value[i].time = 120.0 + PI * i
		parameters = value

		if not is_inside_tree():
			return

		_setup_wave_generator()
		_update_scales_uniform()
		_setup_cpu_displacement_textures()

@export_group("Performance Parameters")

## Available square resolution dimensions for generated wave maps.
enum WaveMapResolution {
	## 128x128 wave map resolution.
	RES_128 = 128,
	## 256x256 wave map resolution.
	RES_256 = 256,
	## 512x512 wave map resolution.
	RES_512 = 512,
	## 1024x1024 wave map resolution.
	RES_1024 = 1024,
}

## Resolution of the generated wave maps. Higher values cost more performance.
@export var map_size: WaveMapResolution = WaveMapResolution.RES_1024:
	set(value):
		map_size = value
		print("ocean.gd: Updating map_size to: ", map_size)
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
		if value:
			bake_waves_to_res_routine()
		bake_waves_to_res = false

## Triggers a hard reset of all wave cascades to their default settings.
@export var reset_cascades: bool = false:
	set(value):
		if value:
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
var cpu_displacement_textures: Dictionary = {}
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


## Initializes global shader parameters when entering the tree.
func _enter_tree() -> void:
	print("ocean.gd: Entering scene tree.")
	RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())
	if Engine.is_editor_hint() and parameters != null and not parameters.is_empty():
		_setup_wave_generator()
		_update_scales_uniform()


## Sets up default seed values on instantiation.
func _init() -> void:
	rng.set_seed(1234)


## Prepares culling bounds and starts simulation services.
func _ready() -> void:
	print("ocean.gd: Executing _ready().")
	extra_cull_margin = 150.0
	RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())

	if parameters != null and not parameters.is_empty():
		_setup_wave_generator()
		_update_scales_uniform()
		_setup_cpu_displacement_textures()


## Drives spray emitter position tracking and per-frame simulation steps.
func _process(delta: float) -> void:
	if is_instance_valid(spray_particles):
		var target_pos: Vector3 = global_position
		if is_instance_valid(player_target):
			target_pos = player_target.global_position
		else:
			var active_cam: Camera3D = _get_camera()
			if is_instance_valid(active_cam):
				target_pos = active_cam.global_position

		var local_target: Vector3 = target_pos - global_position
		var max_dist: float = maxf(0.0, (ocean_plane_size / 2.0) - spray_spawn_radius)
		local_target.x = clampf(local_target.x, -max_dist, max_dist)
		local_target.z = clampf(local_target.z, -max_dist, max_dist)

		spray_particles.global_position = (
			global_position + Vector3(local_target.x, 0.0, local_target.z)
		)

	if Engine.is_editor_hint():
		_update_water(delta)
		return

	if is_instance_valid(player_target):
		if (
			global_position.distance_squared_to(player_target.global_position)
			> max_sim_distance * max_sim_distance
		):
			return

	var cam: Camera3D = _get_camera()
	if cam:
		var distance_moved_sq: float = _last_cam_pos.distance_squared_to(cam.global_position)
		_last_cam_pos = cam.global_position
		if distance_moved_sq > 25.0:
			if update_textures:
				update_textures = false
		else:
			if not update_textures:
				update_textures = true

	just_calculated_water = false
	_update_water(delta)

	if update_textures:
		_manage_cpu_displacement_textures_updates(delta)

	just_calculated_water = true
	time += delta


## Configures the wave generator node and hooks resource updates.
func _setup_wave_generator() -> void:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if not rd:
		printerr("ocean.gd: RenderingDevice is null. Skipping GPU init.")
		return

	if parameters == null or parameters.is_empty():
		print("ocean.gd: No WaveCascadeParameters configured. Waiting for parameters.")
		return

	print("ocean.gd: Setting up wave generator with %d cascades..." % parameters.size())

	for param: WaveCascadeParameters in parameters:
		if is_instance_valid(param):
			param.should_generate_spectrum = true

	if not is_instance_valid(wave_generator):
		wave_generator = WaveGenerator.new()
		wave_generator.name = "WaveGenerator"
		wave_generator.textures_created.connect(_on_wave_textures_created)
		add_child.call_deferred(wave_generator)

	wave_generator.map_size = map_size
	wave_generator.init_gpu(maxi(2, parameters.size()))


## Updates global shader parameters when new RD textures are created.
func _on_wave_textures_created(disp_rid: RID, norm_rid: RID) -> void:
	print("ocean.gd: Received new texture RIDs from WaveGenerator.")
	if not disp_rid.is_valid() or not norm_rid.is_valid():
		return

	displacement_maps.texture_rd_rid = disp_rid
	normal_maps.texture_rd_rid = norm_rid

	RenderingServer.global_shader_parameter_set(&"num_cascades", parameters.size())
	RenderingServer.global_shader_parameter_set(&"displacements", displacement_maps)
	RenderingServer.global_shader_parameter_set(&"normals", normal_maps)


## Updates uniform map scales on ocean and spray materials.
func _update_scales_uniform() -> void:
	print("ocean.gd: Updating uniform map scales.")
	var map_scales: PackedVector4Array
	map_scales.resize(parameters.size())
	for i: int in range(parameters.size()):
		var params: WaveCascadeParameters = parameters[i]
		var uv_scale: Vector2 = Vector2.ONE / params.tile_length
		map_scales[i] = Vector4(
			uv_scale.x, uv_scale.y, params.displacement_scale, params.normal_scale
		)

	if WATER_MAT:
		WATER_MAT.set_shader_parameter(&"map_scales", map_scales)
	if SPRAY_MAT:
		SPRAY_MAT.set_shader_parameter(&"map_scales", map_scales)
	if spray_particles and spray_particles.process_material:
		var proc_mat: Material = spray_particles.process_material
		proc_mat.set_shader_parameter(&"map_scales", map_scales)
		proc_mat.set_shader_parameter(&"spawn_radius", spray_spawn_radius)


## Updates the water simulation through the wave generator.
func _update_water(delta: float) -> void:
	if not RenderingServer.get_rendering_device():
		return

	if not is_instance_valid(wave_generator):
		_setup_wave_generator()

	if is_instance_valid(wave_generator) and wave_generator.is_initialized:
		wave_generator.update(delta, parameters)


## Handles cleanup before deletion to avoid dangling GPU references.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		RenderingServer.global_shader_parameter_set(&"displacements", null)
		RenderingServer.global_shader_parameter_set(&"normals", null)
		displacement_maps.texture_rd_rid = RID()
		normal_maps.texture_rd_rid = RID()


## Manages asynchronous round-robin readbacks of displacement maps to the CPU.
func _manage_cpu_displacement_textures_updates(delta: float) -> void:
	if cpu_displacement_textures.is_empty() or _is_reading_back:
		return

	var cache_size: int = cpu_displacement_textures.size()
	var time_per_tex: float = _displacement_textures_total_update_interval / float(cache_size)

	if _displacement_textures_update_time > time_per_tex:
		_texture_loading_index += 1
		if _texture_loading_index >= cpu_displacement_textures.size():
			_texture_loading_index = 0

		var target_idx: int = cpu_displacement_textures.keys()[_texture_loading_index]
		_is_reading_back = true
		RenderingServer.call_on_render_thread(_do_texture_readback.bind(target_idx))
		_displacement_textures_update_time = 0.0

	_displacement_textures_update_time += delta


## Dispatches an asynchronous GPU texture download request for the specified cascade.
func _do_texture_readback(idx: int) -> void:
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	if not device or not is_instance_valid(wave_generator):
		_is_reading_back = false
		return

	if not wave_generator.descriptors.has(&"downsampled_map"):
		_is_reading_back = false
		return

	var rid_downsampled: RID = wave_generator.descriptors[&"downsampled_map"].rid
	var callable: Callable = _on_texture_data_received.bind(idx)
	var err: int = device.texture_get_data_async(rid_downsampled, idx, callable)
	if err != OK:
		_is_reading_back = false


## Ingests downsampled texture byte data received asynchronously from the GPU.
func _on_texture_data_received(tex: PackedByteArray, idx: int) -> void:
	if not is_instance_valid(wave_generator):
		return

	var img: Image = Image.create_from_data(
		wave_generator.cpu_map_size, wave_generator.cpu_map_size, false, Image.FORMAT_RGBAH, tex
	)
	mutex.lock()
	cpu_displacement_textures[idx] = img
	_is_reading_back = false
	mutex.unlock()


## Schedules initial synchronous displacement map readbacks for CPU physics.
func _setup_cpu_displacement_textures() -> void:
	print("ocean.gd: Setting up CPU displacement textures.")
	var used_idx: Array[int] = []
	for i: int in range(parameters.size()):
		var cascade: WaveCascadeParameters = parameters[i]
		if cascade.displacement_scale > 0.001:
			used_idx.append(i)

	RenderingServer.call_on_render_thread(_do_initial_texture_readback.bind(used_idx))


## Performs the initial download of displacement maps on the render thread.
func _do_initial_texture_readback(used_indices: Array[int]) -> void:
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	if not device:
		return

	if not is_instance_valid(wave_generator):
		return

	if not wave_generator.descriptors.has(&"displacement_map"):
		return

	var rid_disp_map: RID = wave_generator.descriptors[&"displacement_map"].rid

	mutex.lock()
	for i: int in used_indices:
		var tex: PackedByteArray = device.texture_get_data(rid_disp_map, i)
		if tex.is_empty():
			continue

		var img: Image = Image.create_from_data(
			wave_generator.map_size, wave_generator.map_size, false, Image.FORMAT_RGBAH, tex
		)
		if img:
			cpu_displacement_textures[i] = img
	mutex.unlock()


## Converts world space coordinates to repeating UV coordinates for a tile.
func _world_to_uv(w: Vector2, tile_length: Vector2) -> Vector2:
	return Vector2(
		fposmod(w.x, tile_length.x) / tile_length.x, fposmod(w.y, tile_length.y) / tile_length.y
	)


## Computes the ocean wave height displacement at a given world position.
func get_height(world_pos: Vector3, steps: int = 3) -> float:
	print("ocean.gd: Calculating height from world position.")
	var world_pos_xz: Vector2 = Vector2(world_pos.x, world_pos.z)
	var summed_height: float = 0.0

	mutex.lock()
	if is_instance_valid(wave_generator):
		var map_size_cache: int = wave_generator.cpu_map_size
		var map_size_float: float = float(map_size_cache)
		for idx: int in cpu_displacement_textures.keys():
			var disp_scale: float = parameters[idx].displacement_scale
			var tile_length: Vector2 = parameters[idx].tile_length
			var x: Vector2 = world_pos_xz
			var y: Vector2 = Vector2.ZERO
			var y_raw: Color

			for i: int in range(steps):
				var img_v: Vector2 = _world_to_uv(x, tile_length) * map_size_float
				var pixel_x: int = wrapi(int(img_v.x), 0, map_size_cache)
				var pixel_y: int = wrapi(int(img_v.y), 0, map_size_cache)
				y_raw = cpu_displacement_textures[idx].get_pixel(pixel_x, pixel_y)
				y = Vector2(y_raw.r, y_raw.b)
				x = world_pos_xz - y

			summed_height += y_raw.g * disp_scale
	mutex.unlock()
	return summed_height


## Bakes an animated sequence of displacement maps into a static Texture2DArray resource.
func bake_waves_to_res_routine() -> void:
	print("ocean.gd: Executing bake_waves_to_res_routine().")
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	if not device or not is_instance_valid(wave_generator):
		printerr("ocean.gd: Cannot bake waves without valid GPU resources.")
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

	var baked_images: Array[Image] = []
	for frame: int in range(frames_to_bake):
		_update_water(time_step)
		RenderingServer.force_sync()
		var rid_disp_map: RID = wave_generator.descriptors[&"displacement_map"].rid

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
	print("ocean.gd: Force resetting cascade parameters.")
	if parameters.is_empty():
		return
	for p: WaveCascadeParameters in parameters:
		p.tile_length = Vector2(50.0, 50.0)
		p.displacement_scale = 1.0
		p.wind_speed = 15.0
		p.fetch_length = 100.0
		p.swell = 0.5
		p.spread = 0.5
		p.detail = 1.0
		p.should_generate_spectrum = true
	_update_scales_uniform()


## Retrieves and caches the active camera node from the main viewport.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
	return _cached_camera
