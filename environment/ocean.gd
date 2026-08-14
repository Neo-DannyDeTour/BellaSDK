@tool
extends MeshInstance3D

enum MeshQuality { LOW, HIGH, HIGH8K }

const WATER_MAT: Material = preload("res://environment/mat_ocean.tres")
const SPRAY_MAT: Material = preload("res://environment/mat_spray.tres")
const WATER_MESH_HIGH8_K: Mesh = preload("res://assets/ocean_waves/ocean/clipmap_high_8k.obj")
const WATER_MESH_HIGH: Mesh = preload("res://assets/ocean_waves/ocean/clipmap_high.obj")
const WATER_MESH_LOW: Mesh = preload("res://assets/ocean_waves/ocean/clipmap_low.obj")

# ==========================================
# TARGETS & OPTIMIZATION
# ==========================================
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

# ==========================================
# 1. VISUALS (Colors & Glow)
# ==========================================
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

# ==========================================
# 2. PHYSICS (Cascades)
# ==========================================
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

		# Prevent premature execution during editor resource load
		if not is_inside_tree():
			return

		_setup_wave_generator()
		_update_scales_uniform()
		_setup_cpu_displacement_textures()

# ==========================================
# 3. PERFORMANCE
# ==========================================
@export_group("Performance Parameters")

## Resolution of the generated wave maps. Higher values cost more performance.
@export_enum(
	"128x128:128",
	"256x256:256",
	"1024x1024:1024",
	"512x512:512",
)
var map_size: int = 1024:
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

# ==========================================
# 4. TOOLS (The "Buttons")
# ==========================================
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

# ==========================================
# INTERNAL STATE VARIABLES
# ==========================================
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var wave_generator: WaveGenerator:
	set(value):
		if wave_generator:
			wave_generator.queue_free()
		wave_generator = value
		add_child(wave_generator)

var time: float = 0.0
var displacement_maps: Texture2DArrayRD = Texture2DArrayRD.new()
var normal_maps: Texture2DArrayRD = Texture2DArrayRD.new()
var update_textures: bool = true
var just_calculated_water: bool = false
var mutex: Mutex = Mutex.new()
var cpu_displacement_textures: Dictionary = {}
var _displacement_textures_total_update_interval: float = 1.0 / 30.0
var _displacement_textures_update_time: float = 0.0
var _texture_loading_index: int = 0
var _is_reading_back: bool = false
var _last_cam_pos: Vector3 = Vector3.ZERO
var _cached_camera: Camera3D = null


func _enter_tree() -> void:
	print("ocean.gd: Entering scene tree.")
	RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())
	if Engine.is_editor_hint() and parameters != null:
		if parameters.size() > 0:
			_setup_wave_generator()
			_update_scales_uniform()


func _init() -> void:
	rng.set_seed(1234)


func _ready() -> void:
	print("ocean.gd: Executing _ready().")
	extra_cull_margin = 150.0
	RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())

	if parameters != null and parameters.size() > 0:
		if not Engine.is_editor_hint():
			_setup_wave_generator()
			_update_scales_uniform()
			_setup_cpu_displacement_textures()


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


func _setup_wave_generator() -> void:
	print("ocean.gd: Setting up wave generator...")
	if not RenderingServer.get_rendering_device():
		printerr("ocean.gd: RenderingDevice is null. Skipping GPU init.")
		return

	if parameters.size() <= 0:
		return

	for param: WaveCascadeParameters in parameters:
		param.should_generate_spectrum = true

	wave_generator = WaveGenerator.new()
	wave_generator.map_size = map_size
	wave_generator.init_gpu(maxi(2, parameters.size()))

	displacement_maps.texture_rd_rid = wave_generator.descriptors[&"displacement_map"].rid
	normal_maps.texture_rd_rid = wave_generator.descriptors[&"normal_map"].rid

	RenderingServer.global_shader_parameter_set(&"num_cascades", parameters.size())
	RenderingServer.global_shader_parameter_set(&"displacements", displacement_maps)
	RenderingServer.global_shader_parameter_set(&"normals", normal_maps)


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


func _update_water(delta: float) -> void:
	if not RenderingServer.get_rendering_device():
		return  # Prevents the invalid lambda crash by skipping GPU updates

	if wave_generator == null:
		_setup_wave_generator()

	if wave_generator:
		wave_generator.update(delta, parameters)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		displacement_maps.texture_rd_rid = RID()
		normal_maps.texture_rd_rid = RID()


func _manage_cpu_displacement_textures_updates(delta: float) -> void:
	if cpu_displacement_textures.size() < 1 or _is_reading_back:
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


func _do_texture_readback(idx: int) -> void:
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	if not device:
		_is_reading_back = false
		return

	var rid_downsampled: RID = wave_generator.descriptors[&"downsampled_map"].rid
	var callable: Callable = _on_texture_data_received.bind(idx)
	var err: int = device.texture_get_data_async(rid_downsampled, idx, callable)
	if err != OK:
		_is_reading_back = false


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


func _setup_cpu_displacement_textures() -> void:
	print("ocean.gd: Setting up CPU displacement textures.")
	var used_idx: Array[int] = []
	for i: int in range(parameters.size()):
		var cascade: WaveCascadeParameters = parameters[i]
		if cascade.displacement_scale > 0.001:
			used_idx.append(i)

	RenderingServer.call_on_render_thread(_do_initial_texture_readback.bind(used_idx))


func _do_initial_texture_readback(used_indices: Array[int]) -> void:
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	if not device:
		return

	if not wave_generator or not wave_generator.descriptors.has(&"displacement_map"):
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


func _world_to_uv(w: Vector2, tile_length: Vector2) -> Vector2:
	return Vector2(
		fposmod(w.x, tile_length.x) / tile_length.x, fposmod(w.y, tile_length.y) / tile_length.y
	)


func get_height(world_pos: Vector3, steps: int = 3) -> float:
	print("ocean.gd: Calculating height from world position.")
	var world_pos_xz: Vector2 = Vector2(world_pos.x, world_pos.z)
	var summed_height: float = 0.0

	mutex.lock()
	if wave_generator:
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


func bake_waves_to_res_routine() -> void:
	print("ocean.gd: Executing bake_waves_to_res_routine().")
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	if not device:
		printerr("ocean.gd: Cannot bake waves without a rendering device.")
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


func force_reset_cascades() -> void:
	print("ocean.gd: Force resetting cascade parameters.")
	if parameters.size() == 0:
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


func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
	return _cached_camera

#@tool
#extends MeshInstance3D
#
#enum MeshQuality { LOW, HIGH, HIGH8K }
#
#const WATER_MAT: Material = preload("res://environment/mat_ocean.tres")
#const SPRAY_MAT: Material = preload("res://environment/mat_spray.tres")
#const WATER_MESH_HIGH8_K: Mesh = preload("res://assets/ocean_waves/ocean/clipmap_high_8k.obj")
#const WATER_MESH_HIGH: Mesh = preload("res://assets/ocean_waves/ocean/clipmap_high.obj")
#const WATER_MESH_LOW: Mesh = preload("res://assets/ocean_waves/ocean/clipmap_low.obj")
#
## ==========================================
## TARGETS & OPTIMIZATION
## ==========================================
#@export_group("Optimization & Targets")
#
### The target node (usually the player) that the water simulation will track.
#@export var player_target: Node3D
#
### Maximum distance from the target before the simulation suspends.
#@export var max_sim_distance: float = 300.0
#
### Defines the total size of your ocean plane to keep particles inside.
#@export var ocean_plane_size: float = 300.0
#
### Controls the spawn radius in meters for spray particles across the ocean surface.
#@export var spray_spawn_radius: float = 150.0:
#set(value):
#spray_spawn_radius = value
#_update_scales_uniform()
#
### Reference to the GPU particle system for generating spray.
#@export var spray_particles: GPUParticles3D:
#set(value):
#spray_particles = value
#_update_scales_uniform()
#
## ==========================================
## 1. VISUALS (Colors & Glow)
## ==========================================
#@export_group("Colors & Subsurface Glow")
#
### Base color of the deep water.
#@export_color_no_alpha var water_color: Color = Color(0.01, 0.02, 0.03):
#set(value):
#water_color = value
#RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())
#
### Color of the foam generated on wave crests and trails.
#@export_color_no_alpha var foam_color: Color = Color(0.9, 0.9, 0.95):
#set(value):
#foam_color = value
#RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())
#
### Subsurface scattering color visible through the peaks of waves.
#@export_color_no_alpha var crest_color: Color = Color(0.0, 0.65, 0.85):
#set(value):
#crest_color = value
#if WATER_MAT:
#WATER_MAT.set_shader_parameter("crest_color", crest_color)
#
### Controls the intensity of the light passing through wave peaks.
#@export_range(0.0, 2.0) var crest_glow_intensity: float = 0.8:
#set(value):
#crest_glow_intensity = value
#if WATER_MAT:
#WATER_MAT.set_shader_parameter("crest_glow_intensity", crest_glow_intensity)
#
### Controls how much ambient light is captured by heavily aerated foam.
#@export_range(0.0, 2.0) var aerated_foam_glow: float = 0.5:
#set(value):
#aerated_foam_glow = value
#if WATER_MAT:
#WATER_MAT.set_shader_parameter("aerated_foam_glow", aerated_foam_glow)
#
## ==========================================
## 2. PHYSICS (Cascades)
## ==========================================
#@export_group("Wave Parameters")
#
### Array of parameter configurations used to generate multi-frequency wave cascades.
#@export var parameters: Array[WaveCascadeParameters]:
#set(value):
#var new_size: int = value.size()
#for i: int in range(new_size):
#if not value[i]:
#value[i] = WaveCascadeParameters.new()
#if not value[i].is_connected(&"scale_changed", _update_scales_uniform):
#value[i].scale_changed.connect(_update_scales_uniform)
#value[i].spectrum_seed = Vector2i(
#rng.randi_range(-10000, 10000), rng.randi_range(-10000, 10000)
#)
#value[i].time = 120.0 + PI * i
#parameters = value
#_setup_wave_generator()
#_update_scales_uniform()
#_setup_cpu_displacement_textures()
#
## ==========================================
## 3. PERFORMANCE
## ==========================================
#@export_group("Performance Parameters")
#
### Resolution of the generated wave maps. Higher values cost more performance.
#@export_enum(
#"128x128:128",
#"256x256:256",
#"1024x1024:1024",
#"512x512:512",
#)
#var map_size: int = 1024:
#set(value):
#map_size = value
#print("ocean.gd: Updating map_size to: ", map_size)
#_setup_wave_generator()
#
### Level of detail for the actual ocean mesh geometry.
#@export var mesh_quality: MeshQuality = MeshQuality.HIGH:
#set(value):
#mesh_quality = value
#if mesh_quality == MeshQuality.LOW:
#mesh = WATER_MESH_LOW
#elif mesh_quality == MeshQuality.HIGH:
#mesh = WATER_MESH_HIGH
#elif mesh_quality == MeshQuality.HIGH8K:
#mesh = WATER_MESH_HIGH8_K
#
## ==========================================
## 4. TOOLS (The "Buttons")
## ==========================================
#@export_group("Tools & Actions")
#
### Triggers the process to bake the current wave states into a static resource.
#@export var bake_waves_to_res: bool = false:
#set(value):
#if value:
#bake_waves_to_res_routine()
#bake_waves_to_res = false
#
### Triggers a hard reset of all wave cascades to their default settings.
#@export var reset_cascades: bool = false:
#set(value):
#if value:
#force_reset_cascades()
#reset_cascades = false
#
## ==========================================
## INTERNAL STATE VARIABLES
## ==========================================
### Reference to the main random number generator for wave generation.
#var rng: RandomNumberGenerator = RandomNumberGenerator.new()
#
### Generator node responsible for dispatching compute shaders.
#var wave_generator: WaveGenerator:
#set(value):
#if wave_generator:
#wave_generator.queue_free()
#wave_generator = value
#add_child(wave_generator)
#
### Stores the accumulated elapsed time to pass into the wave system.
#var time: float = 0.0
#
### Texture array used to store the GPU-calculated displacement maps.
#var displacement_maps: Texture2DArrayRD = Texture2DArrayRD.new()
#
### Texture array used to store the GPU-calculated normal maps.
#var normal_maps: Texture2DArrayRD = Texture2DArrayRD.new()
#
### Flag indicating whether the CPU should continue reading back displacement textures.
#var update_textures: bool = true
#
### Flag to track if the water was just calculated in the current frame.
#var just_calculated_water: bool = false
#
### Mutex used to lock threading operations when accessing CPU textures.
#var mutex: Mutex = Mutex.new()
#
### Dictionary storing the CPU-accessible Image data for buoyancy queries.
#var cpu_displacement_textures: Dictionary = {}
#
### The total time interval allowed for updating all displacement textures.
#var _displacement_textures_total_update_interval: float = 1.0 / 30.0
#
### Timer tracking the time since the last texture update.
#var _displacement_textures_update_time: float = 0.0
#
### The current index of the texture being loaded from the GPU.
#var _texture_loading_index: int = 0
#
### Flag preventing overlapping readbacks from the GPU.
#var _is_reading_back: bool = false
#
### Stores the camera's position from the previous frame to detect teleports.
#var _last_cam_pos: Vector3 = Vector3.ZERO
#
### Cached reference to the active viewport camera.
#var _cached_camera: Camera3D = null
#
#
#func _enter_tree() -> void:
#RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())
#RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())
#if Engine.is_editor_hint() and parameters != null and parameters.size() > 0:
#_setup_wave_generator()
#_update_scales_uniform()
#
#
#func _init() -> void:
#rng.set_seed(1234)
#
#
#func _ready() -> void:
#extra_cull_margin = 150.0
#RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())
#RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())
#
#
#func _process(delta: float) -> void:
## 1. Spray Boundary Lock
#if is_instance_valid(spray_particles):
#var target_pos: Vector3 = global_position
#if is_instance_valid(player_target):
#target_pos = player_target.global_position
#else:
#var active_cam: Camera3D = _get_camera()
#if is_instance_valid(active_cam):
#target_pos = active_cam.global_position
#
## Calculate target offset relative to the ocean center
#var local_target: Vector3 = target_pos - global_position
#
## Clamp the emitter so it never gets close enough to the edge to push particles outside
#var max_dist: float = maxf(0.0, (ocean_plane_size / 2.0) - spray_spawn_radius)
#local_target.x = clampf(local_target.x, -max_dist, max_dist)
#local_target.z = clampf(local_target.z, -max_dist, max_dist)
#
#spray_particles.global_position = (
#global_position + Vector3(local_target.x, 0.0, local_target.z)
#)
#
## 2. Editor Bypass
#if Engine.is_editor_hint():
#_update_water(delta)
#return
#
## 3. Distance Culling
#if is_instance_valid(player_target):
#if global_position.distance_to(player_target.global_position) > max_sim_distance:
#return
#
## 4. Camera Teleport Freeze
#var cam: Camera3D = _get_camera()
#if cam:
#var distance_moved: float = _last_cam_pos.distance_to(cam.global_position)
#_last_cam_pos = cam.global_position
#if distance_moved > 5.0:
#if update_textures:
#update_textures = false
#else:
#if not update_textures:
#update_textures = true
#
#just_calculated_water = false
#_update_water(delta)
#
#if update_textures:
#_manage_cpu_displacement_textures_updates(delta)
#
#just_calculated_water = true
#time += delta
#
#
#func _setup_wave_generator() -> void:
#print("ocean.gd: Setting up wave generator and binding RD texture RIDs.")
#if parameters.size() <= 0:
#return
#for param: WaveCascadeParameters in parameters:
#param.should_generate_spectrum = true
#wave_generator = WaveGenerator.new()
#wave_generator.map_size = map_size
#wave_generator.init_gpu(maxi(2, parameters.size()))
#displacement_maps.texture_rd_rid = wave_generator.descriptors[&"displacement_map"].rid
#normal_maps.texture_rd_rid = wave_generator.descriptors[&"normal_map"].rid
#RenderingServer.global_shader_parameter_set(&"num_cascades", parameters.size())
#RenderingServer.global_shader_parameter_set(&"displacements", displacement_maps)
#RenderingServer.global_shader_parameter_set(&"normals", normal_maps)
#
#
#func _update_scales_uniform() -> void:
#print("ocean.gd: Updating map_scales and spawn_radius uniforms across materials.")
#var map_scales: PackedVector4Array
#map_scales.resize(parameters.size())
#for i: int in range(parameters.size()):
#var params: WaveCascadeParameters = parameters[i]
#var uv_scale: Vector2 = Vector2.ONE / params.tile_length
#map_scales[i] = Vector4(
#uv_scale.x, uv_scale.y, params.displacement_scale, params.normal_scale
#)
#if WATER_MAT:
#WATER_MAT.set_shader_parameter(&"map_scales", map_scales)
#if SPRAY_MAT:
#SPRAY_MAT.set_shader_parameter(&"map_scales", map_scales)
#if spray_particles and spray_particles.process_material:
#spray_particles.process_material.set_shader_parameter(&"map_scales", map_scales)
#spray_particles.process_material.set_shader_parameter(&"spawn_radius", spray_spawn_radius)
#
#
#func _update_water(delta: float) -> void:
#if wave_generator == null:
#_setup_wave_generator()
#wave_generator.update(delta, parameters)
#
#
#func _notification(what: int) -> void:
#if what == NOTIFICATION_PREDELETE:
#displacement_maps.texture_rd_rid = RID()
#normal_maps.texture_rd_rid = RID()
#
#
#func _manage_cpu_displacement_textures_updates(delta: float) -> void:
#if cpu_displacement_textures.size() < 1 or _is_reading_back:
#return
#var cache_size: int = cpu_displacement_textures.size()
#var time_per_texture: float = _displacement_textures_total_update_interval / float(cache_size)
#if _displacement_textures_update_time > time_per_texture:
#_texture_loading_index += 1
#if _texture_loading_index >= cpu_displacement_textures.size():
#_texture_loading_index = 0
#var target_idx: int = cpu_displacement_textures.keys()[_texture_loading_index]
#_is_reading_back = true
#RenderingServer.call_on_render_thread(_do_texture_readback.bind(target_idx))
#_displacement_textures_update_time = 0.0
#_displacement_textures_update_time += delta
#
#
#func _do_texture_readback(idx: int) -> void:
#var rid_downsampled_map: RID = wave_generator.descriptors[&"downsampled_map"].rid
#var device: RenderingDevice = RenderingServer.get_rendering_device()
#var callable: Callable = _on_texture_data_received.bind(idx)
#var err: int = device.texture_get_data_async(rid_downsampled_map, idx, callable)
#if err != OK:
#_is_reading_back = false
#
#
#func _on_texture_data_received(tex: PackedByteArray, idx: int) -> void:
#if not is_instance_valid(wave_generator):
#return
#var img: Image = Image.create_from_data(
#wave_generator.cpu_map_size, wave_generator.cpu_map_size, false, Image.FORMAT_RGBAH, tex
#)
#mutex.lock()
#cpu_displacement_textures[idx] = img
#_is_reading_back = false
#mutex.unlock()
#
#
#func _setup_cpu_displacement_textures() -> void:
#var actually_used_textures_idx: Array[int] = []
#for i: int in range(parameters.size()):
#var cascade: WaveCascadeParameters = parameters[i]
#if cascade.displacement_scale > 0.001:
#actually_used_textures_idx.append(i)
#RenderingServer.call_on_render_thread(
#_do_initial_texture_readback.bind(actually_used_textures_idx)
#)
#
#
#func _do_initial_texture_readback(used_indices: Array[int]) -> void:
#if not wave_generator or not wave_generator.descriptors.has(&"displacement_map"):
#return
#var rid_displacement_map: RID = wave_generator.descriptors[&"displacement_map"].rid
#var device: RenderingDevice = RenderingServer.get_rendering_device()
#mutex.lock()
#for i: int in used_indices:
#var tex: PackedByteArray = device.texture_get_data(rid_displacement_map, i)
#var img: Image = Image.create_from_data(
#wave_generator.map_size, wave_generator.map_size, false, Image.FORMAT_RGBAH, tex
#)
#cpu_displacement_textures[i] = img
#mutex.unlock()
#
#
#func _world_to_uv(w: Vector2, tile_length: Vector2) -> Vector2:
#return Vector2(
#fposmod(w.x, tile_length.x) / tile_length.x, fposmod(w.y, tile_length.y) / tile_length.y
#)
#
#
#func get_height(world_pos: Vector3, steps: int = 3) -> float:
#var world_pos_xz: Vector2 = Vector2(world_pos.x, world_pos.z)
#var summed_height: float = 0.0
#mutex.lock()
#var map_size_cache: int = wave_generator.cpu_map_size
#var map_size_float: float = float(map_size_cache)
#for cascade_index: int in cpu_displacement_textures.keys():
#var displacement_scale: float = parameters[cascade_index].displacement_scale
#var tile_length: Vector2 = parameters[cascade_index].tile_length
#var x: Vector2 = world_pos_xz
#var y: Vector2 = Vector2.ZERO
#var y_raw: Color
#for i: int in range(steps):
#var img_v: Vector2 = _world_to_uv(x, tile_length) * map_size_float
#var pixel_x: int = wrapi(int(img_v.x), 0, map_size_cache)
#var pixel_y: int = wrapi(int(img_v.y), 0, map_size_cache)
#y_raw = cpu_displacement_textures[cascade_index].get_pixel(pixel_x, pixel_y)
#y = Vector2(y_raw.r, y_raw.b)
#x = world_pos_xz - y
#summed_height += y_raw.g * displacement_scale
#mutex.unlock()
#return summed_height
#
#
#func bake_waves_to_res_routine() -> void:
#print("ocean.gd: Executing bake_waves_to_res_routine() to bake cascades into a texture array.")
#var frames_to_bake: int = 64
#var time_step: float = 0.05
#var cascade_to_bake: int = 0
#var total_bake_duration: float = float(frames_to_bake) * time_step
#for p: WaveCascadeParameters in parameters:
#p.loop_period = total_bake_duration
#p.time = 0.0
#p.should_generate_spectrum = true
#_update_water(0.0)
#RenderingServer.force_sync()
#var baked_images: Array[Image] = []
#for frame: int in range(frames_to_bake):
#_update_water(time_step)
#RenderingServer.force_sync()
#var rid_displacement_map: RID = wave_generator.descriptors[&"displacement_map"].rid
#var device: RenderingDevice = RenderingServer.get_rendering_device()
#var tex: PackedByteArray = device.texture_get_data(rid_displacement_map, cascade_to_bake)
#var img: Image = Image.create_from_data(
#wave_generator.map_size, wave_generator.map_size, false, Image.FORMAT_RGBAH, tex
#)
#baked_images.append(img)
#for p: WaveCascadeParameters in parameters:
#p.loop_period = 0.0
#p.should_generate_spectrum = true
#var texture_array: Texture2DArray = Texture2DArray.new()
#var err: Error = texture_array.create_from_images(baked_images)
#if err == OK:
#var save_path: String = "res://baked_waves/baked_ocean_array.res"
#ResourceSaver.save(texture_array, save_path)
#
#
#func force_reset_cascades() -> void:
#print("ocean.gd: Executing force_reset_cascades() to revert parameters to defaults.")
#if parameters.size() == 0:
#return
#for p: WaveCascadeParameters in parameters:
#p.tile_length = Vector2(50.0, 50.0)
#p.displacement_scale = 1.0
#p.wind_speed = 15.0
#p.fetch_length = 100.0
#p.swell = 0.5
#p.spread = 0.5
#p.detail = 1.0
#p.should_generate_spectrum = true
#_update_scales_uniform()
#
#
#func _get_camera() -> Camera3D:
#if not is_instance_valid(_cached_camera):
#_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
#return _cached_camera
