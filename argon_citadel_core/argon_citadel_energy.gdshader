shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// 0 = Axial Beam, 1 = Plasma Arc Ribbon
uniform int energy_mode : hint_range(0, 1) = 0;

instance uniform float pulse_phase : hint_range(0.0, 1.0) = 0.0;
instance uniform float arc_seed = 0.0;

uniform vec4 cyan_energy : source_color = vec4(0.2, 0.88, 1.0, 1.0);
uniform float arc_half_length = 2.1;

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

void vertex() {
	v_obj_pos = VERTEX;
	if (energy_mode == 1) {
		float norm_z = clamp(VERTEX.z / arc_half_length, -1.0, 1.0);
		float pin = 1.0 - norm_z * norm_z;
		vec3 sample_p = vec3(VERTEX.z * 2.4, TIME * 22.0, arc_seed * 17.3);
		float jx = noise3d(sample_p) - 0.5;
		float jy = noise3d(sample_p + vec3(11.7, 5.3, 2.9)) - 0.5;
		VERTEX.x += jx * 0.85 * pin;
		VERTEX.y += jy * 0.85 * pin;
	}
}

void fragment() {
	vec3 final_rgb = vec3(0.0);
	float final_alpha = 0.0;

	if (energy_mode == 0) {
		float radial = pow(abs(dot(NORMAL, VIEW)), 1.8);
		float vertical_fade = 1.0 - smoothstep(8.0, 11.8, abs(v_obj_pos.y));
		float scroll = noise3d(
			vec3(v_obj_pos.x * 3.0, v_obj_pos.y * 0.6 - TIME * 4.5, v_obj_pos.z * 3.0)
		);
		float surge = 0.55 + 0.45 * sin(pulse_phase * 3.14159265);
		final_rgb = cyan_energy.rgb * (1.8 + scroll * 2.4) * surge;
		final_alpha = clamp(radial * vertical_fade * (0.45 + scroll * 0.55), 0.0, 1.0);
	} else {
		float end_fade = 1.0 - pow(clamp(abs(v_obj_pos.z / arc_half_length), 0.0, 1.0), 4.0);
		float flicker = noise3d(vec3(v_obj_pos.z * 4.0, TIME * 30.0, arc_seed));
		final_rgb = mix(cyan_energy.rgb, vec3(1.0), 0.45) * 5.5;
		final_alpha = clamp(end_fade * pulse_phase * (0.5 + flicker * 0.5), 0.0, 1.0);
	}

	ALBEDO = final_rgb * final_alpha;
	ALPHA = final_alpha;
}
