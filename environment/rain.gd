## Controls rain projector shader parameters on a [MeshInstance3D].
##
## Manages real-time adjustment of UV scrolling velocity, texture tiling,
## and droplet darkness directly on the active [ShaderMaterial].
extends MeshInstance3D

## The active material instance applied to surface 0.
@onready var _rain_mat: ShaderMaterial = get_active_material(0) as ShaderMaterial


## Initializes default heavy storm rain properties on scene load.
func _ready() -> void:
	set_rain_properties(-1.5, 3.0, 0.9)


## Updates shader uniform values to adjust rain speed, density, and opacity.
##
## [param y_speed] Controls vertical UV scroll velocity.
## [param size] Scales the UV repeat frequency.
## [param darkness] Blends texture visibility between 0.0 (clear) and 1.0 (black).
func set_rain_properties(y_speed: float, size: float, darkness: float) -> void:
	print(
		(
			"Applying rain settings -> speed: %s, size: %s, darkness: %s"
			% [
				y_speed,
				size,
				darkness,
			]
		)
	)
	if is_instance_valid(_rain_mat):
		_rain_mat.set_shader_parameter("scroll_speed", Vector2(0.0, y_speed))
		_rain_mat.set_shader_parameter("size_multiplier", size)
		_rain_mat.set_shader_parameter("blackness", darkness)


## Halts rain motion and renders the droplet overlay completely transparent.
func stop_rain() -> void:
	print("Rain stopped.")
	set_rain_properties(0.0, 1.0, 0.0)
