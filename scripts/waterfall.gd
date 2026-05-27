extends MeshInstance3D

@export var scroll_speed: Vector2 = Vector2(0.0, -1.5)
@export var refraction_strength: float = 0.03
@export var water_tint: Color = Color(0.6, 0.8, 0.85, 0.3)

var _water_material: ShaderMaterial = null

func _ready() -> void:
	var mat: Material = get_surface_override_material(0)
	
	if mat is ShaderMaterial:
		_water_material = mat as ShaderMaterial
		_apply_shader_parameters()

func _apply_shader_parameters() -> void:
	if not _water_material:
		return
		
	_water_material.set_shader_parameter("scroll_speed", scroll_speed)
	_water_material.set_shader_parameter("refraction_strength", refraction_strength)
	_water_material.set_shader_parameter("water_tint", water_tint)

func set_flow_speed(new_speed: Vector2) -> void:
	scroll_speed = new_speed
	if _water_material:
		_water_material.set_shader_parameter("scroll_speed", scroll_speed)
