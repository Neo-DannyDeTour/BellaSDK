shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

const float APOTHEM = 0.92388;
const float CENTER_POST_LOCAL_X = 0.91388;

group_uniforms Albedo;
uniform vec3 base_iron_color : source_color = vec3(0.18, 0.19, 0.20);
uniform vec3 rust_color : source_color = vec3(0.38, 0.16, 0.08);
uniform vec3 grime_color : source_color = vec3(0.06, 0.07, 0.05);

group_uniforms Surface;
uniform sampler2D rust_noise : source_color, filter_linear_mipmap, repeat_enable;
uniform float triplanar_scale : hint_range(0.1, 10.0, 0.1) = 1.6;
uniform float triplanar_sharpness : hint_range(1.0, 16.0, 0.5) = 4.0;
uniform float rust_threshold : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float rust_contrast : hint_range(0.05, 0.5, 0.01) = 0.18;
uniform float bump_strength : hint_range(0.0, 2.0, 0.05) = 0.35;

group_uniforms Grime;
uniform float weld_grime_radius : hint_range(0.02, 0.35, 0.01) = 0.14;
uniform float bottom_damp_strength : hint_range(0.0, 1.0, 0.05) = 0.65;

instance uniform float rust_seed = 0.0;

varying vec3 v_obj_pos;
varying vec3 v_obj_normal;
varying float v_grime_weight;

void vertex() {
	v_obj_pos = VERTEX + vec3(rust_seed * 1.73, rust_seed * 2.41, rust_seed * 0.97);
	v_obj_normal = abs(NORMAL);

	// Local X = 0.0 is the outer hinge axis; |X| ~= 0.914 is the center post.
	float abs_x = abs(VERTEX.x);
	float dist_outer_rim = abs_x;
	float dist_center_post = abs(CENTER_POST_LOCAL_X - abs_x);
	float weld_dist = min(dist_outer_rim, dist_center_post);
	float weld_mask = 1.0 - smoothstep(0.0, weld_grime_radius, weld_dist);

	// Local Y spans [-APOTHEM, +APOTHEM]; bias grime toward bottom sewer floor.
	float height_01 = clamp((VERTEX.y + APOTHEM) / (2.0 * APOTHEM), 0.0, 1.0);
	float bottom_mask = (1.0 - height_01) * bottom_damp_strength;

	v_grime_weight = clamp(max(weld_mask * 0.85, bottom_mask), 0.0, 1.0);
}

float sample_triplanar(sampler2D tex, vec3 pos, vec3 weights) {
	float sx = texture(tex, pos.yz).r;
	float sy = texture(tex, pos.xz).r;
	float sz = texture(tex, pos.xy).r;
	return sx * weights.x + sy * weights.y + sz * weights.z;
}

void fragment() {
	vec3 blend_weights = pow(v_obj_normal, vec3(triplanar_sharpness));
	blend_weights /= max(dot(blend_weights, vec3(1.0)), 0.0001);

	vec3 scaled_pos = v_obj_pos * triplanar_scale;
	float n_macro = sample_triplanar(rust_noise, scaled_pos, blend_weights);
	float n_micro = sample_triplanar(rust_noise, scaled_pos * 3.17, blend_weights);
	float combined_noise = mix(n_macro, n_micro, 0.35);

	// Rust mask biased by noise and slightly encouraged near welds/damp zones.
	float rust_bias = combined_noise + v_grime_weight * 0.22;
	float rust_mask = smoothstep(
		rust_threshold - rust_contrast,
		rust_threshold + rust_contrast,
		rust_bias
	);

	// Grime accumulates in crevices and lower bars, modulated by macro noise.
	float grime_mask = smoothstep(0.25, 0.75, v_grime_weight * (0.55 + 0.45 * n_macro));

	vec3 col = mix(base_iron_color, rust_color * (0.75 + 0.5 * n_micro), rust_mask);
	ALBEDO = mix(col, grime_color, grime_mask);

	float metal = mix(0.88, 0.08, rust_mask);
	METALLIC = mix(metal, 0.0, grime_mask);

	float rough = mix(0.45, 0.88, rust_mask);
	ROUGHNESS = mix(rough, 0.92, grime_mask);

	// Screen-space derivative bump from micro/macro rust height.
	float height = combined_noise * (0.3 + 0.7 * rust_mask);
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(height);
	float dhdy = dFdy(height);
	vec3 surf_grad = (dhdx * cross(NORMAL, dpdy) + dhdy * cross(dpdx, NORMAL));
	NORMAL = normalize(NORMAL - surf_grad * bump_strength);
}
