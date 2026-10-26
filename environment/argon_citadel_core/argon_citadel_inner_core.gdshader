shader_type spatial;
render_mode cull_back, unshaded;

instance uniform float pulse_phase : hint_range(0.0, 1.0) = 0.0;

uniform vec4 orange_edge_color : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform vec4 cyan_edge_color : source_color = vec4(0.2, 0.88, 1.0, 1.0);
uniform float noise_scale : hint_range(0.5, 8.0) = 2.6;
uniform float displacement_strength : hint_range(0.0, 0.5) = 0.12;
uniform float instability_scale : hint_range(0.0, 0.6) = 0.28;
uniform float edge_tightness : hint_range(2.0, 10.0) = 5.2;
uniform float edge_intensity : hint_range(0.0, 6.0) = 2.2;

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
		p = p * 2.03 + vec3(13.1, 7.7, 5.3);
		amp *= 0.5;
	}
	return val;
}

// 0.00->0.25: shrink (1->0) | 0.25->0.50: hold 0 | 0.50->0.75: expand (0->1) | 0.75->1.00: hold 1
float get_core_envelope(float phase) {
	float shrink_t = clamp(phase * 4.0, 0.0, 1.0);
	float expand_t = clamp((phase - 0.5) * 4.0, 0.0, 1.0);
	float shrink_curve = 0.5 + 0.5 * cos(shrink_t * 3.14159265);
	float expand_curve = 0.5 - 0.5 * cos(expand_t * 3.14159265);
	return shrink_curve + expand_curve;
}

void vertex() {
	v_obj_pos = VERTEX;
	float env = get_core_envelope(pulse_phase);

	vec3 warp_coord = VERTEX * noise_scale + vec3(0.0, TIME * 0.45, TIME * 0.25);
	float warp = fbm3d(warp_coord);
	float secondary = fbm3d(warp_coord + vec3(warp * 2.0));

	// Decoupled axis noise for unstable, uneven radius vs height expansion.
	float rad_n = fbm3d(VERTEX * 0.85 + vec3(TIME * 1.35, -TIME * 0.9, 0.0));
	float hgt_n = fbm3d(VERTEX * 0.85 + vec3(-TIME * 0.95, TIME * 1.55, 4.7));

	float rad_scale = 1.0 + env * instability_scale * (0.25 + 0.95 * rad_n);
	float hgt_scale = 1.0 + env * instability_scale * (0.25 + 0.95 * hgt_n);

	VERTEX.xz *= rad_scale;
	VERTEX.y *= hgt_scale;
	VERTEX += NORMAL * (secondary - 0.5) * displacement_strength * env;
}

void fragment() {
	vec3 sample_pos = v_obj_pos * (noise_scale * 1.4) + vec3(TIME * 0.3);
	float eps = 0.05;
	float center = fbm3d(sample_pos);
	vec3 grad = vec3(
		fbm3d(sample_pos + vec3(eps, 0.0, 0.0)) - center,
		fbm3d(sample_pos + vec3(0.0, eps, 0.0)) - center,
		fbm3d(sample_pos + vec3(0.0, 0.0, eps)) - center
	);
	vec3 pert_normal = normalize(NORMAL + grad * 1.6);

	float fresnel = pow(1.0 - clamp(dot(pert_normal, VIEW), 0.0, 1.0), edge_tightness);
	float orange_mix = 1.0 - smoothstep(0.35, 0.75, pulse_phase);
	vec3 rim_color = mix(cyan_edge_color.rgb, orange_edge_color.rgb, orange_mix);

	ALBEDO = rim_color * fresnel * edge_intensity;
}
