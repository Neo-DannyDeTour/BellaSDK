shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms BaseSurface;
uniform vec4 base_color : source_color = vec4(0.13, 0.21, 0.11, 1.0);
uniform float metallic_base : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.78;

group_uniforms Weathering;
uniform vec4 rust_color : source_color = vec4(0.28, 0.13, 0.07, 1.0);
uniform vec4 grime_color : source_color = vec4(0.05, 0.06, 0.05, 1.0);
uniform vec4 edge_wear_color : source_color = vec4(0.46, 0.49, 0.47, 1.0);
uniform float rust_amount : hint_range(0.0, 1.0) = 0.52;
uniform float edge_wear_strength : hint_range(0.0, 2.0) = 1.15;
uniform float edge_metallic : hint_range(0.0, 1.0) = 0.88;
uniform float edge_roughness : hint_range(0.0, 1.0) = 0.38;
uniform float grime_height : hint_range(0.0, 1.5) = 0.42;
uniform float noise_scale : hint_range(0.5, 20.0) = 4.5;
uniform float bump_strength : hint_range(0.0, 0.05) = 0.012;

varying vec3 v_obj_pos;
varying vec3 v_obj_normal;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
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

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);

	return mix(nxy0, nxy1, f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += value_noise(p) * amp;
		p = p * 2.03 + vec3(13.7, 7.1, 19.3);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_obj_pos = VERTEX;
	v_obj_normal = normalize(NORMAL);
}

void fragment() {
	vec3 sample_pos = v_obj_pos * noise_scale;
	float n_coarse = fbm3(sample_pos);
	float n_fine = value_noise(sample_pos * 5.5);

	// Bottom-up splash grime mask
	float lower_mask = clamp(1.0 - (v_obj_pos.y / max(grime_height, 0.001)), 0.0, 1.0);
	float grime_mask = smoothstep(0.25, 0.78, lower_mask * 0.75 + n_coarse * 0.55);

	// Rust concentration (biased toward lower wall panels and chipped edge borders)
	float up_bias = clamp(v_obj_normal.y * 0.35 + 0.35, 0.0, 1.0);
	float rust_field = n_coarse * 0.65 + n_fine * 0.25 + lower_mask * 0.25 + up_bias * 0.15 + COLOR.r * 0.25;
	float rust_thresh = 1.0 - rust_amount;
	float rust_mask = smoothstep(rust_thresh - 0.12, rust_thresh + 0.12, rust_field);

	// Baked vertex color edge mask (COLOR.r) modulated by high-frequency scratch noise
	float edge_signal = COLOR.r * edge_wear_strength * mix(0.45, 1.35, n_fine);
	float edge_mask = smoothstep(0.32, 0.78, edge_signal);

	// Base paint -> rust -> dark bottom grime -> bare steel/scuffed ridge highlights
	vec3 col = mix(base_color.rgb, rust_color.rgb, rust_mask);
	col = mix(col, grime_color.rgb, grime_mask * 0.85);
	col = mix(col, edge_wear_color.rgb, edge_mask);
	col *= mix(0.90, 1.08, n_fine);

	float weather_weight = clamp(max(rust_mask, grime_mask), 0.0, 1.0);
	float metal = mix(metallic_base * (1.0 - weather_weight * 0.9), edge_metallic, edge_mask);
	float rough = clamp(
		mix(mix(roughness_base, 0.96, weather_weight), edge_roughness, edge_mask),
		0.05,
		1.0
	);

	// Screen-space derivative bump mapping
	float height_val = n_coarse * 0.5 + rust_mask * 0.35 - edge_mask * 0.25;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(height_val);
	float dhdy = dFdy(height_val);
	vec3 surf_grad = (dhdx * cross(NORMAL, dpdy) + dhdy * cross(dpdx, NORMAL));
	NORMAL = normalize(NORMAL - surf_grad * bump_strength * 60.0);

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
}
