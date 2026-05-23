extends MeshInstance3D

@onready var rain_mat: ShaderMaterial = get_active_material(0) as ShaderMaterial


func _ready() -> void:
	# Example: Start a heavy, dark rain storm when the level loads
	set_rain_properties(-1.5, 3.0, 0.9)


# A single function to control all your variables in real-time
func set_rain_properties(y_speed: float, size: float, darkness: float) -> void:
	if rain_mat:
		rain_mat.set_shader_parameter("scroll_speed", Vector2(0.0, y_speed))
		rain_mat.set_shader_parameter("size_multiplier", size)
		rain_mat.set_shader_parameter("blackness", darkness)


func stop_rain() -> void:
	# Make it invisible and stop moving
	set_rain_properties(0.0, 1.0, 0.0)
