shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

instance uniform float pulse_phase : hint_range(0.0, 1.0) = 0.0;

uniform vec4 orange_energy : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform float expansion_scale : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float noise_scale : hint_range(0.5, 6.0, 0.1) = 6.0;
uniform float ring_thickness : hint_range(0.02, 0.35, 0.01) = 0.35;
uniform float liquid_warp_strength : hint_range(0.0, 0.4, 0.01) = 0.0;

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

// 0.00->0.25: shrink (1->0) | 0.25->0.50: hold 0 | 0.50->0.75: expand (0->1) | 0.75->1.00: hold 1
float get_ring_size(float phase) {
	float shrink_t = clamp(phase * 4.0, 0.0, 1.0);
	float expand_t = clamp((phase - 0.5) * 4.0, 0.0, 1.0);
	float shrink_curve = 0.5 + 0.5 * cos(shrink_t * 3.14159265);
	float expand_curve = 0.5 - 0.5 * cos(expand_t * 3.14159265);
	return shrink_curve + expand_curve;
}

void vertex() {
	v_obj_pos = VERTEX;
	float ring_size = get_ring_size(pulse_phase);
	float scale_mod = 1.08 + ring_size * expansion_scale * 0.42;

	vec3 flow_p = VERTEX * 2.1 + vec3(0.35, 0.72, -0.28) * TIME;
	float fluid_wobble = (fbm3d(flow_p) - 0.5) * liquid_warp_strength;

	VERTEX = VERTEX * scale_mod + NORMAL * fluid_wobble;
}

void fragment() {
	float ring_size = get_ring_size(pulse_phase);
	float small_factor = 1.0 - ring_size;
	float peak_boost = small_factor * small_factor;

	vec3 flow_a = v_obj_pos * 2.1 + vec3(0.35, 0.72, -0.28) * TIME;
	vec3 flow_b = v_obj_pos * 1.65 + vec3(-0.52, 0.34, 0.46) * TIME;
	float warp = (fbm3d(flow_a) + fbm3d(flow_b) - 1.0) * liquid_warp_strength;

	float active_thickness = ring_thickness + peak_boost * 0.08;
	float rim = clamp((1.0 - abs(dot(NORMAL, VIEW))) + warp, 0.0, 1.0);
	float inner_cut = smoothstep(0.82 - active_thickness, 0.84, rim);
	float outer_cut = 1.0 - smoothstep(0.86, 0.96, rim);
	float thin_ring = inner_cut * outer_cut;

	float n = noise3d(v_obj_pos * noise_scale + vec3(0.0, TIME * 1.6, -TIME * 0.8));
	float hdr_energy = mix(3.8, 14.0, peak_boost) + n * mix(2.2, 5.5, peak_boost);
	vec3 final_rgb = orange_energy.rgb * hdr_energy;

	// Visible for [0.00, 0.75] (75% of cycle); fluid fade-out approaching max diameter [0.68, 0.75]
	// and fluid re-entry [0.95, 1.00] to avoid pop at loop wrap.
	float fade_out = 1.0 - smoothstep(0.68, 0.75, pulse_phase);
	float fade_in = smoothstep(0.95, 1.0, pulse_phase);
	float vis_window = clamp(fade_out + fade_in, 0.0, 1.0);

	float final_alpha = clamp(thin_ring * (0.75 + n * 0.35) * vis_window, 0.0, 1.0);

	ALBEDO = final_rgb * final_alpha;
	ALPHA = final_alpha;
}
