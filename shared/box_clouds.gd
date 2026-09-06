@tool
## Controls local low-altitude weather effects, specifically volumetric clouds.
##
## This script manages wind direction, wind speed, and cloud coverage parameters,
## applying them directly to a linked [FogVolume] via shader parameters. It exposes
## editor proxies for static weather variables used throughout the level.
class_name LowAltitudeWeather
extends Node

## The direction vector of the wind affecting the clouds.
@export_group("Weather Settings")
@export var editor_wind_dir: Vector3 = Vector3(1.0, 0.0, 0.5):
	set(value):
		editor_wind_dir = value
		LowAltitudeWeather.wind_dir = value

## The speed of the wind affecting the clouds.
@export var editor_wind_spd: float = 2.5:
	set(value):
		editor_wind_spd = value
		LowAltitudeWeather.wind_spd = value

## The density or coverage amount of the clouds.
@export var editor_coverage: float = 0.45:
	set(value):
		editor_coverage = value
		LowAltitudeWeather.coverage = value

## The [FogVolume] node used to render the local clouds.
@export_group("Nodes")
@export var local_cloud_volume: FogVolume

## Static variable for global wind direction.
static var wind_dir: Vector3 = Vector3(1.0, 0.0, 0.5)
## Static variable for global wind speed.
static var wind_spd: float = 2.5
## Static variable for global cloud coverage.
static var coverage: float = 0.45


## Validates node assignments on entry.
func _ready() -> void:
	if not is_instance_valid(local_cloud_volume):
		push_error("WeatherController: FogVolume is missing or unassigned!")
	elif not is_instance_valid(local_cloud_volume.material):
		push_error("WeatherController: Assigned FogVolume has no material!")


## Continuously applies the weather parameters to the fog volume's shader material.
func _process(_delta: float) -> void:
	if is_instance_valid(local_cloud_volume) and is_instance_valid(local_cloud_volume.material):
		var mat: ShaderMaterial = local_cloud_volume.material as ShaderMaterial
		if is_instance_valid(mat):
			mat.set_shader_parameter("wind_direction", LowAltitudeWeather.wind_dir)
			mat.set_shader_parameter("wind_speed", LowAltitudeWeather.wind_spd)
			mat.set_shader_parameter("cloud_coverage", LowAltitudeWeather.coverage)
