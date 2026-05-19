class_name LowAltitudeWeather
extends Node

static var wind_dir: Vector3 = Vector3(1.0, 0.0, 0.5)
static var wind_spd: float = 2.5
static var coverage: float = 0.45 

@export var local_cloud_volume: FogVolume

func _process(_delta: float) -> void:
	if local_cloud_volume and local_cloud_volume.material:
		var mat := local_cloud_volume.material as ShaderMaterial
		mat.set_shader_parameter("wind_direction", LowAltitudeWeather.wind_dir)
		mat.set_shader_parameter("wind_speed", LowAltitudeWeather.wind_spd)
		mat.set_shader_parameter("cloud_coverage", LowAltitudeWeather.coverage)
