shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.25, 0.7, 1.0, 1.0);

uniform float emission_energy : hint_range(1.0, 50.0) = 22.0;
uniform float core_sharpness : hint_range(1.0, 20.0) = 6.0;
uniform float glow_width : hint_range(0.1, 5.0) = 1.4;
uniform float distortion_strength : hint_range(0.0, 0.5) = 0.22;

float hash1d(float p) {
	return fract(sin(p * 127.1) * 43758.5453123);
}

void fragment() {
	float wave_a = sin(UV.x * 35.0 - TIME * 45.0) * 0.6;
	float wave_b = sin(UV.x * 75.0 + TIME * 30.0) * 0.4;
	float distorted_y = UV.y + ((wave_a + wave_b) * distortion_strength * 0.5);

	float center_dist = abs(distorted_y - 0.5) * 2.0;
	float longitudinal_fade = smoothstep(0.0, 0.03, UV.x) * smoothstep(1.0, 0.96, UV.x);
	float strobe = mix(0.7, 1.3, hash1d(floor(TIME * 30.0) + UV.x * 6.0));
	float energy_pulse = sin(UV.x * 30.0 - TIME * 40.0) * 0.25 + 0.85;

	float core_profile = pow(clamp(1.0 - center_dist, 0.0, 1.0), core_sharpness);
	float glow_profile = pow(clamp(1.0 - center_dist, 0.0, 1.0), glow_width);

	vec3 beam_glow = glow_profile * glow_color.rgb * 3.0;
	vec3 beam_core = core_profile * core_color.rgb * 8.0;

	vec3 final_color = (beam_glow + beam_core) * longitudinal_fade * energy_pulse * strobe;

	ALBEDO = final_color * emission_energy;
}
