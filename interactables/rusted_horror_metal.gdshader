shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D worley_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grain_tex : repeat_enable, filter_linear_mipmap;

uniform vec3 base_iron_color : source_color = vec3(0.11, 0.10, 0.09);
uniform vec3 deep_rust_color : source_color = vec3(0.24, 0.07, 0.03);
uniform vec3 orange_rust_color : source_color = vec3(0.48, 0.18, 0.05);
uniform vec3 oil_grime_color : source_color = vec3(0.03, 0.03, 0.025);

uniform float triplanar_scale : hint_range(0.5, 10.0) = 2.8;
uniform float rust_coverage : hint_range(0.0, 1.0) = 0.62;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.65;

varying vec3 local_pos;
varying vec3 local_norm;

vec4 triplanar_sample(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.yz) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

float sample_pit_height(vec3 p, vec3 w) {
	return triplanar_sample(worley_tex, p, w).r * 0.6 + triplanar_sample(grain_tex, p * 4.5, w).r * 0.4;
}

void vertex() {
	local_pos = VERTEX;
	local_norm = NORMAL;
}

void fragment() {
	vec3 abs_norm = abs(local_norm);
	vec3 w = abs_norm / max(abs_norm.x + abs_norm.y + abs_norm.z, 0.0001);
	vec3 p = local_pos * triplanar_scale;

	vec4 cells = triplanar_sample(worley_tex, p, w);
	vec4 fine_cells = triplanar_sample(worley_tex, p * 2.7, w);
	float grain = triplanar_sample(grain_tex, p * 4.5, w).r;

	// Vertical oil & rust drip streaks accumulating toward bottom/top caps.
	float drip_noise = texture(grain_tex, vec2(atan(local_pos.x, local_pos.z) * 1.5, local_pos.y * 0.8)).r;
	float cap_accumulation = smoothstep(0.22, 0.48, abs(local_pos.y));
	float rust_raw = cells.r * 0.55 + fine_cells.g * 0.3 + grain * 0.15 + cap_accumulation * 0.25;
	float rust_mask = smoothstep(1.0 - rust_coverage - 0.18, 1.0 - rust_coverage + 0.15, rust_raw);
	float fresh_oxide = smoothstep(0.58, 0.85, rust_raw * fine_cells.r) * rust_mask;
	float oil_streaks = smoothstep(0.62, 0.88, drip_noise * (1.0 - cells.b)) * (0.5 + 0.5 * cap_accumulation);

	vec3 col = mix(base_iron_color, deep_rust_color, rust_mask);
	col = mix(col, orange_rust_color, fresh_oxide * 0.75);
	col = mix(col, oil_grime_color, oil_streaks * 0.8);

	// True 3D object-space gradient normal perturbation.
	float eps = 0.02;
	float h_center = sample_pit_height(p, w);
	float h_x = sample_pit_height(p + vec3(eps, 0.0, 0.0), w);
	float h_y = sample_pit_height(p + vec3(0.0, eps, 0.0), w);
	float h_z = sample_pit_height(p + vec3(0.0, 0.0, eps), w);
	vec3 grad = vec3(h_x - h_center, h_y - h_center, h_z - h_center) / eps;
	vec3 obj_perturbed = normalize(local_norm - grad * bump_strength * 0.035);
	vec3 view_bump = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(obj_perturbed, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, view_bump, 0.45));

	ALBEDO = col;
	METALLIC = mix(0.88, 0.08, clamp(rust_mask + oil_streaks * 0.5, 0.0, 1.0));
	ROUGHNESS = clamp(mix(0.42, 0.94, rust_mask) - oil_streaks * 0.28 + (grain - 0.5) * 0.1, 0.18, 0.98);
	SPECULAR = mix(0.6, 0.2, rust_mask);
}
