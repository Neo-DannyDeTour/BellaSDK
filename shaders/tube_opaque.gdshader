shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform vec4 albedo_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
instance uniform float metallic : hint_range(0.0, 1.0) = 0.0;
instance uniform float roughness : hint_range(0.0, 1.0) = 0.4;
instance uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	ALBEDO = mix(albedo_color.rgb, albedo_color.rgb * 1.25, fresnel * (1.0 - metallic));
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = 0.5;
}
