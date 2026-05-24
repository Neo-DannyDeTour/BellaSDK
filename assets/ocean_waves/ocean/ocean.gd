@tool
extends MeshInstance3D
## Handles updating the displacement/normal maps for the water material as well as
## managing wave generation pipelines.

const WATER_MAT := preload("res://assets/ocean_waves/ocean/mat_ocean.tres")
const SPRAY_MAT := preload("res://assets/ocean_waves/ocean/mat_spray.tres")
const WATER_MESH_HIGH8K := preload("res://assets/ocean_waves/ocean/clipmap_high_8k.obj")
const WATER_MESH_HIGH := preload("res://assets/ocean_waves/ocean/clipmap_high.obj")
const WATER_MESH_LOW := preload("res://assets/ocean_waves/ocean/clipmap_low.obj")

enum MeshQuality { LOW, HIGH, HIGH8K }

# ==========================================
# INTERNAL STATE VARIABLES (Restored)
# ==========================================
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var wave_generator: WaveGenerator:
	set(value):
		if wave_generator:
			wave_generator.queue_free()
		wave_generator = value
		add_child(wave_generator)

var time: float = 0.0
var next_update_time: float = 0.0
var displacement_maps: Texture2DArrayRD = Texture2DArrayRD.new()
var normal_maps: Texture2DArrayRD = Texture2DArrayRD.new()

var update_textures: bool = true
var just_calculated_water: bool = false

# CPU readback variables
var mutex: Mutex = Mutex.new()
var _cpu_displacement_textures: Dictionary = {}
var _displacement_textures_total_update_interval: float = 1.0 / 120.0
var _displacement_textures_update_time: float = 0.0
var _texture_loading_index: int = 0
var _is_reading_back: bool = false

var _last_cam_pos: Vector3 = Vector3.ZERO

static var player_target: Node3D = null
static var max_sim_distance: float = 200.0

# ==========================================
# 1. VISUALS (Colors & Glow)
# ==========================================
@export_group("Colors & Subsurface Glow")
@export_color_no_alpha var water_color: Color = Color(0.01, 0.02, 0.03):
	set(value):
		water_color = value
		RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())

@export_color_no_alpha var foam_color: Color = Color(0.9, 0.9, 0.95):
	set(value):
		foam_color = value
		RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())

@export_color_no_alpha var crest_color: Color = Color(0.0, 0.65, 0.85):
	set(value):
		crest_color = value
		if WATER_MAT:
			WATER_MAT.set_shader_parameter("crest_color", crest_color)

@export_range(0.0, 2.0) var crest_glow_intensity: float = 0.8:
	set(value):
		crest_glow_intensity = value
		if WATER_MAT:
			WATER_MAT.set_shader_parameter("crest_glow_intensity", crest_glow_intensity)

@export_range(0.0, 2.0) var aerated_foam_glow: float = 0.5:
	set(value):
		aerated_foam_glow = value
		if WATER_MAT:
			WATER_MAT.set_shader_parameter("aerated_foam_glow", aerated_foam_glow)

# ==========================================
# 2. PHYSICS (Cascades)
# ==========================================
@export_group("Wave Parameters")
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
		_setup_wave_generator()
		_update_scales_uniform()
		_setup_cpu_displacement_textures()

# ==========================================
# 3. PERFORMANCE
# ==========================================
@export_group("Performance Parameters")
@export_enum("128x128:128", "256x256:256", "512x512:512", "1024x1024:1024") var map_size: int = 1024:
	set(value):
		map_size = value
		_setup_wave_generator()

@export var mesh_quality: MeshQuality = MeshQuality.HIGH:
	set(value):
		mesh_quality = value
		if mesh_quality == MeshQuality.LOW:
			mesh = WATER_MESH_LOW
		if mesh_quality == MeshQuality.HIGH:
			mesh = WATER_MESH_HIGH
		if mesh_quality == MeshQuality.HIGH8K:
			mesh = WATER_MESH_HIGH8K

@export_range(0, 60) var updates_per_second: float = 50.0:
	set(value):
		next_update_time = (
			next_update_time - (1.0 / (updates_per_second + 1e-10) - 1.0 / (value + 1e-10))
		)
		updates_per_second = value

# ==========================================
# 4. TOOLS (The "Buttons")
# ==========================================
@export_group("Tools & Actions")
@export var bake_waves_to_res: bool = false:
	set(value):
		if value:
			bake_waves_to_res_routine()
		bake_waves_to_res = false

@export var reset_cascades: bool = false:
	set(value):
		if value:
			force_reset_cascades()
		reset_cascades = false
# ==========================================


func _enter_tree() -> void:
	# 1. Force the colors to load immediately
	RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())

	# 2. Force the compute shader to boot up in the editor viewport
	if Engine.is_editor_hint() and parameters != null and parameters.size() > 0:
		_setup_wave_generator()
		_update_scales_uniform()


func _init() -> void:
	rng.set_seed(1234)


func _ready() -> void:
	# Tell the CPU not to cull the mesh unless it is safely far off-screen
	extra_cull_margin = 150.0

	RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())


func _process(delta: float) -> void:
	# --- Mach 3 Noclip Speed Freeze ---
	var cam := get_viewport().get_camera_3d()
	if cam:
		var cam_speed := _last_cam_pos.distance_to(cam.global_position) / delta
		_last_cam_pos = cam.global_position
		if cam_speed > 100.0:
			return

	# --- Distance Culling ---
	if player_target:
		# Stop sending compute commands if we are too far away
		if global_position.distance_to(player_target.global_position) > max_sim_distance:
			return

	# ---------------------------------------

	just_calculated_water = false
	if updates_per_second == 0.0 or time >= next_update_time:
		var target_update_delta: float = 1.0 / (updates_per_second + 1e-10)
		var update_delta: float = (
			delta if updates_per_second == 0.0 else target_update_delta + (time - next_update_time)
		)
		next_update_time = time + target_update_delta

		_update_water(update_delta)

		if update_textures:
			_manage_cpu_displacement_textures_updates(delta)
		just_calculated_water = true
	time += delta


func _setup_wave_generator() -> void:
	if parameters.size() <= 0:
		return
	for param: WaveCascadeParameters in parameters:
		param.should_generate_spectrum = true

	wave_generator = WaveGenerator.new()
	wave_generator.map_size = map_size
	wave_generator.init_gpu(maxi(2, parameters.size()))

	displacement_maps.texture_rd_rid = RID()
	normal_maps.texture_rd_rid = RID()
	displacement_maps.texture_rd_rid = wave_generator.descriptors[&"displacement_map"].rid
	normal_maps.texture_rd_rid = wave_generator.descriptors[&"normal_map"].rid

	RenderingServer.global_shader_parameter_set(&"num_cascades", parameters.size())
	RenderingServer.global_shader_parameter_set(&"displacements", displacement_maps)
	RenderingServer.global_shader_parameter_set(&"normals", normal_maps)


func _update_scales_uniform() -> void:
	var map_scales: PackedVector4Array
	map_scales.resize(parameters.size())
	for i: int in parameters.size():
		var params: WaveCascadeParameters = parameters[i]
		var uv_scale: Vector2 = Vector2.ONE / params.tile_length
		map_scales[i] = Vector4(
			uv_scale.x, uv_scale.y, params.displacement_scale, params.normal_scale
		)

	WATER_MAT.set_shader_parameter(&"map_scales", map_scales)
	SPRAY_MAT.set_shader_parameter(&"map_scales", map_scales)


func _update_water(delta: float) -> void:
	if wave_generator == null:
		_setup_wave_generator()
	wave_generator.update(delta, parameters)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		displacement_maps.texture_rd_rid = RID()
		normal_maps.texture_rd_rid = RID()


# =============================================================================
#  displacement textures loading from gpu (Render Thread Safe)
# =============================================================================


func _manage_cpu_displacement_textures_updates(delta: float) -> void:
	if _cpu_displacement_textures.size() < 1:
		return

	# Ensure we don't queue another readback if the render thread is still processing the last one
	if _is_reading_back:
		return

	var time_per_texture: float = (
		_displacement_textures_total_update_interval / float(_cpu_displacement_textures.size())
	)
	var _cpu_displacement_textures_indeces: Array = _cpu_displacement_textures.keys()
	_cpu_displacement_textures_indeces.sort()

	if _displacement_textures_update_time > time_per_texture:
		_texture_loading_index += 1
		if _texture_loading_index >= _cpu_displacement_textures.size():
			_texture_loading_index = 0

		var target_idx: int = _cpu_displacement_textures_indeces[_texture_loading_index]

		_is_reading_back = true
		# Dispatch directly to the engine's Render Thread to satisfy the RenderingDevice requirement
		RenderingServer.call_on_render_thread(_do_texture_readback.bind(target_idx))

		_displacement_textures_update_time = 0.0
	_displacement_textures_update_time += delta


func _do_texture_readback(idx: int) -> void:
	var rid_downsampled_map: RID = wave_generator.descriptors[&"downsampled_map"].rid  # <-- CHANGED
	var device: RenderingDevice = RenderingServer.get_rendering_device()

	var tex: PackedByteArray = device.texture_get_data(rid_downsampled_map, idx)
	var img: Image = Image.create_from_data(
		wave_generator.cpu_map_size, wave_generator.cpu_map_size, false, Image.FORMAT_RGBAH, tex
	)  # <-- CHANGED

	mutex.lock()
	_cpu_displacement_textures[idx] = img
	_is_reading_back = false
	mutex.unlock()


func _setup_cpu_displacement_textures() -> void:
	var _actually_used_textures_idx: Array[int] = []
	for i: int in range(parameters.size()):
		var cascade: WaveCascadeParameters = parameters[i]
		if cascade.displacement_scale > 0.001:
			_actually_used_textures_idx.append(i)

	# We must also push the initial setup to the Render Thread!
	RenderingServer.call_on_render_thread(
		_do_initial_texture_readback.bind(_actually_used_textures_idx)
	)


func _do_initial_texture_readback(used_indices: Array[int]) -> void:
	if not wave_generator or not wave_generator.descriptors.has(&"displacement_map"):
		return

	var rid_displacement_map: RID = wave_generator.descriptors[&"displacement_map"].rid
	var device: RenderingDevice = RenderingServer.get_rendering_device()

	mutex.lock()
	for i: int in used_indices:
		var tex: PackedByteArray = device.texture_get_data(rid_displacement_map, i)
		var img: Image = Image.create_from_data(
			wave_generator.map_size, wave_generator.map_size, false, Image.FORMAT_RGBAH, tex
		)
		_cpu_displacement_textures[i] = img
	mutex.unlock()


func _world_to_uv(W: Vector2, tile_length: Vector2) -> Vector2:
	return Vector2(
		(W[0] - tile_length.x * floor(W[0] / tile_length.x)) / tile_length.x,
		(W[1] - tile_length.y * floor(W[1] / tile_length.y)) / tile_length.y
	)


func get_height(world_pos: Vector3, steps: int = 3) -> float:
	var world_pos_xz: Vector2 = Vector2(world_pos.x, world_pos.z)
	var summed_height: float = 0.0

	mutex.lock()  # Lock while reading to prevent the thread pool from writing at the same time
	for cascade_index: int in _cpu_displacement_textures.keys():
		var displacement_scale: float = parameters[cascade_index].displacement_scale
		var tile_length: Vector2 = parameters[cascade_index].tile_length
		var x: Vector2 = world_pos_xz
		var y: Vector2 = Vector2.ZERO
		var y_raw: Color = Color.BLACK

		for i: int in range(steps):
			# Calculate the raw floating point pixel coordinate based on the TINY map
			var img_v: Vector2 = _world_to_uv(x, tile_length) * float(wave_generator.cpu_map_size)

			# Wrap safely within 128
			var pixel_x: int = wrapi(int(img_v.x), 0, wave_generator.cpu_map_size)
			var pixel_y: int = wrapi(int(img_v.y), 0, wave_generator.cpu_map_size)

			y_raw = _cpu_displacement_textures[cascade_index].get_pixel(pixel_x, pixel_y)
			y = Vector2(y_raw.r, y_raw.b)
			x = world_pos_xz - y

		summed_height += y_raw.g * displacement_scale
	mutex.unlock()

	return summed_height


func bake_waves_to_res_routine() -> void:
	print("Starting Ocean Bake...")
	var frames_to_bake: int = 64
	var time_step: float = 0.05
	var cascade_to_bake: int = 0

	# 1. Calculate the exact duration of the exported animation (64 * 0.05 = 3.2 seconds)
	var total_bake_duration: float = float(frames_to_bake) * time_step

	# 2. Force the simulation into a mathematically perfect loop
	for p: WaveCascadeParameters in parameters:
		p.loop_period = total_bake_duration
		p.time = 0.0  # Reset time to 0 so the loop starts cleanly
		p.should_generate_spectrum = true  # Force the GPU to rebuild the FFT!

	# Force a frame update so the GPU catches the reset before we start recording
	_update_water(0.0)
	RenderingServer.force_sync()

	var baked_images: Array[Image] = []

	for frame: int in range(frames_to_bake):
		_update_water(time_step)
		RenderingServer.force_sync()

		var rid_displacement_map: RID = wave_generator.descriptors[&"displacement_map"].rid
		var device: RenderingDevice = RenderingServer.get_rendering_device()
		var tex: PackedByteArray = device.texture_get_data(rid_displacement_map, cascade_to_bake)

		var img: Image = Image.create_from_data(
			wave_generator.map_size, wave_generator.map_size, false, Image.FORMAT_RGBAH, tex
		)
		baked_images.append(img)
		print("Baked frame %d/%d" % [frame + 1, frames_to_bake])

	print("Packaging frames into Texture2DArray...")

	# 3. Release the waves back to normal, chaotic simulation after the bake is done
	for p: WaveCascadeParameters in parameters:
		p.loop_period = 0.0
		p.should_generate_spectrum = true

	var texture_array: Texture2DArray = Texture2DArray.new()
	var err: Error = texture_array.create_from_images(baked_images)

	if err == OK:
		var save_path: String = "res://baked_waves/baked_ocean_array.res"
		ResourceSaver.save(texture_array, save_path)
		print("Bake Complete! Saved directly to: ", save_path)
	else:
		print("Failed to create Texture2DArray. Error code: ", err)


func force_reset_cascades() -> void:
	if parameters.size() == 0:
		return

	print("Resetting all wave cascade physics to default...")
	for p: WaveCascadeParameters in parameters:
		p.tile_length = Vector2(50.0, 50.0)
		p.displacement_scale = 1.0
		p.wind_speed = 15.0
		p.fetch_length = 100.0
		p.swell = 0.5
		p.spread = 0.5
		p.detail = 1.0
		p.should_generate_spectrum = true  # Forces GPU to recalculate

	# Trigger a uniform update
	_update_scales_uniform()
