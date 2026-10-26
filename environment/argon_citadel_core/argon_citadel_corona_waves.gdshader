shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

instance uniform float pulse_phase : hint_range(0.0, 1.0) = 0.0;

uniform vec4 orange_wave_color : source_color = vec4(1.0, 0.42, 0.06, 1.0);
uniform vec4 blue_wave_color : source_color = vec4(0.12, 0.78, 1.0, 1.0);
uniform float wave_frequency : hint_range(4.0, 130.0, 0.5) = 63.0;
uniform float wave_speed : hint_range(1.0, 15.0, 0.5) = 7.5;
uniform float noise_scale : hint_range(0.5, 8.0, 0.1) = 3.2;
uniform float liquid_warp_strength : hint_range(0.0, 0.4, 0.01) = 0.18;

varying vec3 v_obj_pos;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

float fbm3d(vec3 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		val += noise3d(p) * amp;
		p = p * 2.02 + vec3(9.3, 15.7, 4.1);
		amp *= 0.5;
	}
	return val;
}

void vertex() {
	v_obj_pos = VERTEX;
	float surge_expand = sin(clamp(pulse_phase * 2.0, 0.0, 1.0) * 3.14159265);
	vec3 flow_p = VERTEX * 2.1 + vec3(0.35, 0.72, -0.28) * TIME;
	float fluid_wobble = (fbm3d(flow_p) - 0.5) * liquid_warp_strength;

	VERTEX = VERTEX * (1.0 + surge_expand * 0.22) + NORMAL * fluid_wobble;
}

void fragment() {
	vec3 flow_a = v_obj_pos * 2.1 + vec3(0.35, 0.72, -0.28) * TIME;
	vec3 flow_b = v_obj_pos * 1.65 + vec3(-0.52, 0.34, 0.46) * TIME;
	float fluid_warp = (fbm3d(flow_a) + fbm3d(flow_b) - 1.0) * liquid_warp_strength;

	float rim = clamp((1.0 - abs(dot(NORMAL, VIEW))) + fluid_warp, 0.0, 1.0);
	float band_mask = smoothstep(0.34, 0.52, rim) * (1.0 - smoothstep(0.86, 0.98, rim));
	float r_norm = clamp((rim - 0.34) / 0.58, 0.0, 1.0);

	float n = noise3d(v_obj_pos * noise_scale + vec3(0.0, TIME * 0.9, -TIME * 0.6));

	// Stage A (0.0 -> 0.5): Ring shrinks -> Huge orange glow + outward waves (center -> outside)
	float stage_a_env = sin(clamp(pulse_phase * 2.0, 0.0, 1.0) * 3.14159265);
	float waves_out = 0.5 + 0.5 * sin(r_norm * wave_frequency - TIME * wave_speed + n * 4.5);
	float a_orange_zone = (1.0 - smoothstep(0.15, 0.72, r_norm)) * (0.45 + 0.55 * waves_out);
	float a_blue_zone = smoothstep(0.45, 0.85, r_norm) * waves_out;
	vec3 col_a = (
		orange_wave_color.rgb * a_orange_zone * 5.2
		+ blue_wave_color.rgb * a_blue_zone * 3.8
	) * stage_a_env;
	float alpha_a = clamp((a_orange_zone + a_blue_zone * 0.85) * stage_a_env, 0.0, 1.0);

	// Stage B (0.5 -> 1.0): Ring grows -> Orange tries to glow, inward blue waves quench it
	float t_b = clamp((pulse_phase - 0.5) * 2.0, 0.0, 1.0);
	float stage_b_active = step(0.5, pulse_phase);
	float waves_in = 0.5 + 0.5 * sin(r_norm * wave_frequency + TIME * wave_speed + n * 4.5);

	float quench_front = 1.0 - t_b * 1.15;
	float orange_survive = 1.0 - smoothstep(quench_front - 0.18, quench_front + 0.12, r_norm);
	float orange_reignite = sin(clamp(t_b * 1.35, 0.0, 1.0) * 3.14159265);
	float b_orange_zone = (1.0 - smoothstep(0.0, 0.62, r_norm))
		* orange_survive * orange_reignite * (0.5 + 0.5 * waves_in);

	float blue_sweep_mask = smoothstep(quench_front - 0.22, quench_front + 0.08, r_norm);
	float b_blue_zone = blue_sweep_mask * waves_in * sin(t_b * 3.14159265);

	vec3 col_b = (
		orange_wave_color.rgb * b_orange_zone * 4.2
		+ blue_wave_color.rgb * b_blue_zone * 4.6
	) * stage_b_active;
	float alpha_b = clamp((b_orange_zone + b_blue_zone) * stage_b_active, 0.0, 1.0);

	vec3 final_rgb = col_a + col_b;
	float final_alpha = clamp((alpha_a + alpha_b) * band_mask, 0.0, 1.0);

	ALBEDO = final_rgb * final_alpha;
	ALPHA = final_alpha;
}
