@tool
## Controls global wind parameters for shaders across the game world.
##
## [WindController] updates global shader parameters for wind intensity, speed, and direction
## based on its exported properties and its 3D rotation in the scene.
class_name WindController
extends Node3D

## Controls the overall strength of the wind effect across the game world.
@export_range(0.0, 5.0, 0.1, "or_greater") var wind_intensity: float = 1.0:
	set(new_intensity):
		wind_intensity = new_intensity
		RenderingServer.global_shader_parameter_set("wind_intensity", wind_intensity)
		if not Engine.is_editor_hint():
			print("Setting global wind intensity to: ", wind_intensity)

## Dictates the scrolling speed of the noise texture simulating wind gusts.
@export_range(0.0, 5.0, 0.01, "or_greater") var wind_speed: float = 1.0:
	set(new_speed):
		wind_speed = new_speed
		RenderingServer.global_shader_parameter_set("wind_speed", wind_speed)
		if not Engine.is_editor_hint():
			print("Setting global wind speed to: ", wind_speed)

## Stores the node's basis from the previous frame to avoid redundant shader updates.
var previous_rotation: Basis = Basis()


## Called when the node enters the scene tree for the first time.
## Initializes the global shader parameters with the current exported values.
func _ready() -> void:
	# Force initialize the global shader parameters on load/startup.
	RenderingServer.global_shader_parameter_set("wind_intensity", wind_intensity)
	RenderingServer.global_shader_parameter_set("wind_speed", wind_speed)
	_update_wind_direction()

	if not Engine.is_editor_hint():
		print("WindController initialized. Intensity: ", wind_intensity, ", Speed: ", wind_speed)


## Called every frame. Updates the wind direction global shader parameter if rotation changes.
## [param _delta] The time elapsed since the previous frame in seconds.
func _process(_delta: float) -> void:
	if basis.is_equal_approx(previous_rotation):
		return

	_update_wind_direction()


## Calculates the forward direction from the current basis and pushes it to the RenderingServer.
func _update_wind_direction() -> void:
	var wind_direction: Vector3 = Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	RenderingServer.global_shader_parameter_set("wind_direction", wind_direction)
	previous_rotation = basis

	if not Engine.is_editor_hint():
		print("Updated global wind direction: ", wind_direction)
