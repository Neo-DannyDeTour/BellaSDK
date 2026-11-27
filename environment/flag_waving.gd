@tool
## Controls dynamic cloth waving simulation on flags using vertex shaders and noise.
class_name FlagController
extends Node3D

## Shader uniform key for the flag albedo texture.
const PARAM_FLAG_TEXTURE: StringName = &"flag_texture"

## Shader uniform key for the wind noise texture.
const PARAM_WIND_NOISE: StringName = &"wind_noise"

## Instance shader uniform key for global wind direction vector.
const PARAM_WIND_DIRECTION: StringName = &"wind_direction"

## Instance shader uniform key for wind push intensity.
const PARAM_WIND_INTENSITY: StringName = &"wind_intensity"

## Instance shader uniform key for wind noise flutter strength.
const PARAM_NOISE_STRENGTH: StringName = &"noise_strength"

## Instance shader uniform key for wave animation speed.
const PARAM_WAVE_SPEED: StringName = &"wave_speed"

## Instance shader uniform key for wave displacement amplitude.
const PARAM_WAVE_AMPLITUDE: StringName = &"wave_amplitude"

## Instance shader uniform key for wave spatial frequency.
const PARAM_WAVE_FREQUENCY: StringName = &"wave_frequency"

## Instance shader uniform key for secondary wave phase ratio.
const PARAM_WAVE_PHASES: StringName = &"wave_phases"

## Instance shader uniform key for surface roughness.
const PARAM_ROUGHNESS: StringName = &"roughness"

## The texture assigned to this specific flag instance.
@export var flag_texture: Texture2D = null:
	set = set_flag_texture

## A seamless FastNoiseLite texture used to simulate random wind gusts.
@export var wind_noise: Texture2D = null:
	set = set_wind_noise

## The dimensions of the flag object in 3D space.
@export var flag_size: Vector2 = Vector2(1.0, 1.0):
	set = set_flag_size

## The 3D global direction in which the wind pushes the fabric.
@export var wind_direction: Vector3 = Vector3(0.0, 0.0, 1.0):
	set = set_wind_direction

## The overall strength or force of the directional wind pushing the flag.
@export var wind_intensity: float = 1.0:
	set = set_wind_intensity

## Determines how intensely noise fluttering affects the flag fabric.
@export var noise_strength: float = 0.2:
	set = set_noise_strength

## How fast the fabric flaps based on the wind speed.
@export var wave_speed: float = 2.5:
	set = set_wave_speed

## How high the folds of the fabric peak during the rippling animation.
@export var wave_amplitude: float = 0.15:
	set = set_wave_amplitude

## The amount of ripples stretching across the fabric width.
@export var wave_frequency: float = 3.0:
	set = set_wave_frequency

## Adds complexity to waves to make fabric movement appear organic.
@export var wave_phases: float = 2.0:
	set = set_wave_phases

## The material roughness, determining how shiny or matte the flag appears.
@export var roughness: float = 0.6:
	set = set_roughness

## Reference to the main mesh displaying the front of the flag.
@export var front_mesh: MeshInstance3D

## Reference to the back mesh preventing Z-fighting artifacts.
@export var back_mesh: MeshInstance3D

## Base shared [Material] used to derive texture-keyed variants via [MaterialCache].
var _base_material: Material

## Shader material cached via [MaterialCache] preventing compilation hitches.
var _unique_material: ShaderMaterial


## Initializes material instance and applies configured flag properties.
func _ready() -> void:
	#print("FlagController: Initializing flag controller in _ready().")
	_initialize_material()
	_apply_all_settings()


## Retrieves or caches shared [ShaderMaterial] keyed by texture combination via [MaterialCache].
func _initialize_material() -> void:
	#print("FlagController: Initializing shared material via MaterialCache.")
	if not is_instance_valid(front_mesh):
		var found_front: Node = NodeQuery.find_first_child_of_type(self, MeshInstance3D)
		if found_front is MeshInstance3D:
			front_mesh = found_front as MeshInstance3D

	if is_instance_valid(front_mesh) and front_mesh.mesh != null:
		_base_material = front_mesh.mesh.surface_get_material(0)
		_sync_shared_material()


## Resolves and binds a shared [ShaderMaterial] keyed by texture and wind noise IDs.
func _sync_shared_material() -> void:
	if not is_instance_valid(_base_material) or not is_instance_valid(front_mesh):
		return

	var flag_id: int = flag_texture.get_instance_id() if is_instance_valid(flag_texture) else 0
	var noise_id: int = wind_noise.get_instance_id() if is_instance_valid(wind_noise) else 0
	var variant_key: String = "flag_%d_%d" % [flag_id, noise_id]
	_unique_material = MaterialCache.get_variant(_base_material, variant_key) as ShaderMaterial
	if not is_instance_valid(_unique_material):
		return

	if flag_texture != null:
		_unique_material.set_shader_parameter(PARAM_FLAG_TEXTURE, flag_texture)
	if wind_noise != null:
		_unique_material.set_shader_parameter(PARAM_WIND_NOISE, wind_noise)

	front_mesh.set_surface_override_material(0, _unique_material)
	if is_instance_valid(back_mesh):
		back_mesh.set_surface_override_material(0, _unique_material)


## Sets a per-instance shader parameter on both front and back flag meshes.
func _set_instance_param(param: StringName, val: Variant) -> void:
	if is_instance_valid(front_mesh):
		front_mesh.set_instance_shader_parameter(param, val)
	if is_instance_valid(back_mesh):
		back_mesh.set_instance_shader_parameter(param, val)


## Applies all exported property values to the shared material and instance uniforms.
func _apply_all_settings() -> void:
	print("FlagController: Applying all exported property parameters.")
	_sync_shared_material()
	set_flag_size(flag_size)
	set_wind_direction(wind_direction)
	set_wind_intensity(wind_intensity)
	set_noise_strength(noise_strength)
	set_wave_speed(wave_speed)
	set_wave_amplitude(wave_amplitude)
	set_wave_frequency(wave_frequency)
	set_wave_phases(wave_phases)
	set_roughness(roughness)


## Sets flag albedo texture and updates shared texture-keyed shader material.
func set_flag_texture(value: Texture2D) -> void:
	print("FlagController: set_flag_texture() called.")
	flag_texture = value
	if not is_inside_tree():
		return
	_sync_shared_material()


## Sets wind noise texture and updates shared texture-keyed shader material.
func set_wind_noise(value: Texture2D) -> void:
	print("FlagController: set_wind_noise() called.")
	wind_noise = value
	if not is_inside_tree():
		return
	_sync_shared_material()


## Sets physical dimensions of flag front and back meshes.
func set_flag_size(value: Vector2) -> void:
	print("FlagController: set_flag_size() called with value: ", value)
	flag_size = value
	if not is_inside_tree():
		return
	if is_instance_valid(front_mesh):
		front_mesh.scale = Vector3(flag_size.x, flag_size.y, 1.0)
	if is_instance_valid(back_mesh):
		back_mesh.scale = Vector3(flag_size.x, flag_size.y, 1.0)


## Sets global wind direction vector via per-instance shader uniform.
func set_wind_direction(value: Vector3) -> void:
	print("FlagController: set_wind_direction() called with value: ", value)
	wind_direction = value
	if not is_inside_tree():
		return
	_set_instance_param(PARAM_WIND_DIRECTION, wind_direction)


## Sets wind intensity force scalar via per-instance shader uniform.
func set_wind_intensity(value: float) -> void:
	print("FlagController: set_wind_intensity() called with value: ", value)
	wind_intensity = value
	if not is_inside_tree():
		return
	_set_instance_param(PARAM_WIND_INTENSITY, wind_intensity)


## Sets noise flutter strength scalar via per-instance shader uniform.
func set_noise_strength(value: float) -> void:
	print("FlagController: set_noise_strength() called with value: ", value)
	noise_strength = value
	if not is_inside_tree():
		return
	_set_instance_param(PARAM_NOISE_STRENGTH, noise_strength)


## Sets wave flap animation speed via per-instance shader uniform.
func set_wave_speed(value: float) -> void:
	print("FlagController: set_wave_speed() called with value: ", value)
	wave_speed = value
	if not is_inside_tree():
		return
	_set_instance_param(PARAM_WAVE_SPEED, wave_speed)


## Sets wave ripple vertical amplitude via per-instance shader uniform.
func set_wave_amplitude(value: float) -> void:
	print("FlagController: set_wave_amplitude() called with value: ", value)
	wave_amplitude = value
	if not is_inside_tree():
		return
	_set_instance_param(PARAM_WAVE_AMPLITUDE, wave_amplitude)


## Sets wave ripple horizontal frequency via per-instance shader uniform.
func set_wave_frequency(value: float) -> void:
	print("FlagController: set_wave_frequency() called with value: ", value)
	wave_frequency = value
	if not is_inside_tree():
		return
	_set_instance_param(PARAM_WAVE_FREQUENCY, wave_frequency)


## Sets wave complexity harmonic phase count via per-instance shader uniform.
func set_wave_phases(value: float) -> void:
	print("FlagController: set_wave_phases() called with value: ", value)
	wave_phases = value
	if not is_inside_tree():
		return
	_set_instance_param(PARAM_WAVE_PHASES, wave_phases)


## Sets surface roughness property via per-instance shader uniform.
func set_roughness(value: float) -> void:
	print("FlagController: set_roughness() called with value: ", value)
	roughness = value
	if not is_inside_tree():
		return
	_set_instance_param(PARAM_ROUGHNESS, roughness)
