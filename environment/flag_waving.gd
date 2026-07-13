@tool
extends Node3D
class_name FlagController

## The texture assigned to this specific flag instance.
@export var flag_texture: Texture2D = null : set = set_flag_texture

## A seamless FastNoiseLite texture used to simulate random wind gusts.
@export var wind_noise: Texture2D = null : set = set_wind_noise

## The dimensions of the flag object in 3D space.
@export var flag_size: Vector2 = Vector2(1.0, 1.0) : set = set_flag_size

## The 3D global direction in which the wind pushes the fabric.
@export var wind_direction: Vector3 = Vector3(0.0, 0.0, 1.0) : set = set_wind_direction

## The overall strength or force of the directional wind pushing the flag.
@export var wind_intensity: float = 1.0 : set = set_wind_intensity

## Determines how intensely the noise texture chaotic fluttering affects the flag.
@export var noise_strength: float = 0.2 : set = set_noise_strength

## How fast the fabric flaps based on the wind speed.
@export var wave_speed: float = 2.5 : set = set_wave_speed

## How high the folds of the fabric peak during the rippling animation.
@export var wave_amplitude: float = 0.15 : set = set_wave_amplitude

## The amount of ripples stretching across the fabric width.
@export var wave_frequency: float = 3.0 : set = set_wave_frequency

## Adds complexity to the waves to make the fabric appear more organic.
@export var wave_phases: float = 2.0 : set = set_wave_phases

## The material roughness, determining how shiny or matte the flag appears.
@export var roughness: float = 0.6 : set = set_roughness

## Reference to the main mesh displaying the front of the flag.
@export var front_mesh: MeshInstance3D

## Reference to the duplicated mesh showing the back of the flag to avoid Z-fighting.
@export var back_mesh: MeshInstance3D

## The locally duplicated ShaderMaterial so instances don't share parameters globally.
var _unique_material: ShaderMaterial

func _ready() -> void:
	_initialize_material()
	_apply_all_settings()

func _initialize_material() -> void:
	print("FlagController: Initializing unique material.")
	if front_mesh and front_mesh.mesh:
		var base_mat: Material = front_mesh.mesh.surface_get_material(0)
		if base_mat:
			_unique_material = base_mat.duplicate() as ShaderMaterial
			front_mesh.set_surface_override_material(0, _unique_material)
			if back_mesh:
				back_mesh.set_surface_override_material(0, _unique_material)

func _apply_all_settings() -> void:
	if flag_texture:
		set_flag_texture(flag_texture)
	if wind_noise:
		set_wind_noise(wind_noise)
	set_flag_size(flag_size)
	set_wind_direction(wind_direction)
	set_wind_intensity(wind_intensity)
	set_noise_strength(noise_strength)
	set_wave_speed(wave_speed)
	set_wave_amplitude(wave_amplitude)
	set_wave_frequency(wave_frequency)
	set_wave_phases(wave_phases)
	set_roughness(roughness)

func set_flag_texture(value: Texture2D) -> void:
	flag_texture = value
	if not is_node_ready():
		return
	print("FlagController: set_flag_texture() called.")
	if _unique_material:
		_unique_material.set_shader_parameter("flag_texture", flag_texture)

func set_wind_noise(value: Texture2D) -> void:
	wind_noise = value
	if not is_node_ready():
		return
	print("FlagController: set_wind_noise() called.")
	if _unique_material:
		_unique_material.set_shader_parameter("wind_noise", wind_noise)

func set_flag_size(value: Vector2) -> void:
	flag_size = value
	if not is_node_ready():
		return
	print("FlagController: set_flag_size() called with value ", flag_size)
	if front_mesh:
		front_mesh.scale = Vector3(flag_size.x, flag_size.y, 1.0)
	if back_mesh:
		back_mesh.scale = Vector3(flag_size.x, flag_size.y, 1.0)

func set_wind_direction(value: Vector3) -> void:
	wind_direction = value
	if not is_node_ready():
		return
	print("FlagController: set_wind_direction() called with value ", wind_direction)
	if _unique_material:
		_unique_material.set_shader_parameter("wind_direction", wind_direction)

func set_wind_intensity(value: float) -> void:
	wind_intensity = value
	if not is_node_ready():
		return
	print("FlagController: set_wind_intensity() called with value ", wind_intensity)
	if _unique_material:
		_unique_material.set_shader_parameter("wind_intensity", wind_intensity)

func set_noise_strength(value: float) -> void:
	noise_strength = value
	if not is_node_ready():
		return
	print("FlagController: set_noise_strength() called with value ", noise_strength)
	if _unique_material:
		_unique_material.set_shader_parameter("noise_strength", noise_strength)

func set_wave_speed(value: float) -> void:
	wave_speed = value
	if not is_node_ready():
		return
	print("FlagController: set_wave_speed() called with value ", wave_speed)
	if _unique_material:
		_unique_material.set_shader_parameter("wave_speed", wave_speed)

func set_wave_amplitude(value: float) -> void:
	wave_amplitude = value
	if not is_node_ready():
		return
	print("FlagController: set_wave_amplitude() called with value ", wave_amplitude)
	if _unique_material:
		_unique_material.set_shader_parameter("wave_amplitude", wave_amplitude)

func set_wave_frequency(value: float) -> void:
	wave_frequency = value
	if not is_node_ready():
		return
	print("FlagController: set_wave_frequency() called with value ", wave_frequency)
	if _unique_material:
		_unique_material.set_shader_parameter("wave_frequency", wave_frequency)

func set_wave_phases(value: float) -> void:
	wave_phases = value
	if not is_node_ready():
		return
	print("FlagController: set_wave_phases() called with value ", wave_phases)
	if _unique_material:
		_unique_material.set_shader_parameter("wave_phases", wave_phases)

func set_roughness(value: float) -> void:
	roughness = value
	if not is_node_ready():
		return
	print("FlagController: set_roughness() called with value ", roughness)
	if _unique_material:
		_unique_material.set_shader_parameter("roughness", roughness)
