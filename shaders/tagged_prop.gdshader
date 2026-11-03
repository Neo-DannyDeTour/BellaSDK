shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform vec4 prop_color : source_color = vec4(0.2, 0.22, 0.25, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.1;

void fragment() {
	ALBEDO = prop_color.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
