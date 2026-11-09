shader_type spatial;
instance uniform vec3 tint_color : source_color = vec3(1.0);
void fragment() {
	ALBEDO = tint_color;
	ROUGHNESS = 0.85;
}
