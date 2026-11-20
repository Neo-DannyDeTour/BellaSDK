shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(0.88, 0.72, 0.42, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.42;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.2;

instance uniform vec3 emission_color : source_color = vec3(1.0, 0.68, 0.22);
instance uniform float emission_energy : hint_range(0.0, 16.0) = 2.5;

void fragment() {
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndotv, fresnel_power);
	float core_falloff = mix(1.0, 0.45, rim);

	ALBEDO = mix(albedo_color.rgb, albedo_color.rgb * 0.5, rim);
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
	EMISSION = emission_color * emission_energy * core_falloff;
}
