@tool
class_name LowAltitudeWeather
extends Node

# 1. The static variables remain exactly as they were
static var wind_dir: Vector3 = Vector3(1.0, 0.0, 0.5)
static var wind_spd: float = 2.5
static var coverage: float = 0.45

# 2. Proxy variables exposed to the Inspector
@export_group("Weather Settings")
@export var editor_wind_dir: Vector3 = Vector3(1.0, 0.0, 0.5):
	set(value):
		editor_wind_dir = value
		LowAltitudeWeather.wind_dir = value

@export var editor_wind_spd: float = 2.5:
	set(value):
		editor_wind_spd = value
		LowAltitudeWeather.wind_spd = value

@export var editor_coverage: float = 0.45:
	set(value):
		editor_coverage = value
		LowAltitudeWeather.coverage = value

@export_group("Nodes")
@export var local_cloud_volume: FogVolume


func _ready() -> void:
	if not local_cloud_volume:
		push_error("WeatherController: FogVolume is missing or unassigned!")
	elif not local_cloud_volume.material:
		push_error("WeatherController: Assigned FogVolume has no material!")


func _process(_delta: float) -> void:
	if local_cloud_volume and local_cloud_volume.material:
		var mat := local_cloud_volume.material as ShaderMaterial
		mat.set_shader_parameter("wind_direction", LowAltitudeWeather.wind_dir)
		mat.set_shader_parameter("wind_speed", LowAltitudeWeather.wind_spd)
		mat.set_shader_parameter("cloud_coverage", LowAltitudeWeather.coverage)
