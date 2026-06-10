class_name WaterfallController
extends MeshInstance3D

@export var waterfall_material: ShaderMaterial


func set_waterfall_color(new_color: Color) -> void:
	print("WaterfallController: Updating waterfall base color to ", new_color)
	if waterfall_material != null:
		# If you pass a color with alpha, we can extract it to drive opacity too,
		# but changing the dedicated opacity parameter is cleaner.
		var color_vec3: Vector3 = Vector3(new_color.r, new_color.g, new_color.b)
		waterfall_material.set_shader_parameter("color", color_vec3)


func adjust_flow_speed(new_speed: float) -> void:
	print("WaterfallController: Adjusting waterfall flow speed to ", new_speed)
	if waterfall_material != null:
		waterfall_material.set_shader_parameter("speed", new_speed)


func set_opacity(new_opacity: float) -> void:
	print("WaterfallController: Setting waterfall opacity to ", new_opacity)
	if waterfall_material != null:
		waterfall_material.set_shader_parameter("opacity", new_opacity)


func _ready() -> void:
	print("WaterfallController: Initialized 3D FBM Waterfall shader.")
	if material_override is ShaderMaterial:
		waterfall_material = material_override as ShaderMaterial
