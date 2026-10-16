shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 hot_color : source_color = vec4(4.5, 1.8, 0.3, 1.0);
uniform vec4 cool_color : source_color = vec4(0.06, 0.05, 0.05, 1.0);
uniform float stretch_factor : hint_range(1.0, 8.0) = 3.2;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.18;

varying float v_heat;

void vertex() {
	// COLOR.a holds normalized remaining life from the particle process material.
	v_heat = clamp(COLOR.a, 0.0, 1.0);

	// Taper the top/tail of the droplet to form a cohesive fluid teardrop.
	float taper = mix(0.28, 1.0, clamp(VERTEX.y + 0.5, 0.0, 1.0));
	VERTEX.xz *= taper;
	VERTEX.y *= mix(1.0, stretch_factor, v_heat);
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float core_heat = smoothstep(0.15, 0.95, v_heat);

	vec3 base_albedo = mix(cool_color.rgb, hot_color.rgb * 0.25, core_heat);
	vec3 emission_glow = hot_color.rgb * pow(core_heat, 2.0) * (1.0 + fresnel * 1.5);

	ALBEDO = base_albedo;
	ROUGHNESS = mix(0.65, roughness_val, core_heat);
	SPECULAR = 0.75;
	EMISSION = emission_glow;
}
