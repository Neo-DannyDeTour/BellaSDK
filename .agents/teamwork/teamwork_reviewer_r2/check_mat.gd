extends SceneTree


func _init() -> void:
	var mat: ShaderMaterial = load("res://props/gothic_arch/gothic_arch_mat.tres") as ShaderMaterial
	print("normal_scale: ", mat.get_shader_parameter(&"normal_scale"))
	print("moss_color: ", mat.get_shader_parameter(&"moss_color"))
	print("moss_sharpness: ", mat.get_shader_parameter(&"moss_sharpness"))
	quit(0)
