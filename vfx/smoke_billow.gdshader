shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Per-instance uniforms mutated via set_instance_shader_parameter() without material duplication.
instance uniform float expansion_scale : hint_range(0.1, 2.0) = 1.0;
instance uniform float heat_intensity : hint_range(0.0, 4.0) = 1.0;
instance uniform float erosion_offset : hint_range(-0.5, 0.5) = 0.0;

uniform vec4 core_fire_color : source_color = vec4(1.0, 0.55, 0.12, 1.0);
uniform vec4 hot_ember_color : source_color = vec4(0.85, 0.22, 0.04, 1.0);
uniform vec4 sunlit_smoke_color : source_color = vec4(0.32, 0.31, 0.30, 1.0);
uniform vec4 crevice_smoke_color : source_color = vec4(0.07, 0.07, 0.08, 1.0);
uniform float displacement_strength : hint_range(0.0, 1.5) = 0.42;
uniform float noise_frequency : hint_range(0.5, 6.0) = 2.1;
uniform float scroll_speed : hint_range(0.0, 3.0) = 0.65;
uniform float proximity_fade_distance : hint_range(0.05, 2.0) = 0.38;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying float v_lifetime_ratio;
varying float v_noise_sample;
varying vec3 v_local_pos;

float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float value_noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);

	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);

	float nxy0 = mix(nx00, nx10, u.y);
	float nxy1 = mix(nx01, nx11, u.y);

	return mix(nxy0, nxy1, u.z);
}

// 3-octave FBM generating crisp bulbous cauliflower lobes.
float fbm3(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	vec3 shift = vec3(17.3, 29.1, 11.7);
	for (int i = 0; i < 3; i++) {
		total += value_noise3d(p) * amp;
		p = p * 2.03 + shift;
		amp *= 0.5;
	}
	return total;
}

void vertex() {
	// INSTANCE_CUSTOM.y stores normalized particle age (0.0 -> 1.0) in GPUParticles3D.
	v_lifetime_ratio = clamp(INSTANCE_CUSTOM.y + erosion_offset, 0.0, 1.0);
	vec3 advected = VERTEX * noise_frequency + vec3(0.0, -TIME * scroll_speed, INSTANCE_CUSTOM.x * 7.13);
	float n = fbm3(advected);
	v_noise_sample = n;
	v_local_pos = advected;

	float growth = mix(0.65, 1.25, smoothstep(0.0, 0.45, v_lifetime_ratio)) * expansion_scale;
	VERTEX = (VERTEX + NORMAL * (n - 0.45) * displacement_strength) * growth;
}

void fragment() {
	// Analytical finite-difference normal perturbation for directional crevice contrast.
	float eps = 0.08;
	float nx = fbm3(v_local_pos + vec3(eps, 0.0, 0.0)) - v_noise_sample;
	float ny = fbm3(v_local_pos + vec3(0.0, eps, 0.0)) - v_noise_sample;
	float nz = fbm3(v_local_pos + vec3(0.0, 0.0, eps)) - v_noise_sample;
	vec3 perturbed_normal = normalize(NORMAL - vec3(nx, ny, nz) * 2.4);
	NORMAL = perturbed_normal;

	// Crevice mask: 0.0 in deep folds, 1.0 on bulbous outer ridges.
	float ridge_mask = smoothstep(0.22, 0.78, v_noise_sample);
	ALBEDO = mix(crevice_smoke_color.rgb, sunlit_smoke_color.rgb, ridge_mask) * COLOR.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.05;
	AO = mix(0.18, 1.0, ridge_mask);
	AO_LIGHT_AFFECT = 0.85;

	// Phase 0..1 internal fire core decaying rapidly into charcoal smoke.
	float fire_phase = (1.0 - smoothstep(0.04, 0.34, v_lifetime_ratio)) * heat_intensity;
	float core_crevice = 1.0 - ridge_mask;
	vec3 fire_grad = mix(hot_ember_color.rgb, core_fire_color.rgb, core_crevice);
	EMISSION = fire_grad * fire_phase * smoothstep(0.25, 0.85, core_crevice) * 5.5;

	// Phase 3 noise-driven alpha erosion + Fresnel grazing cleanup.
	float erosion_threshold = smoothstep(0.35, 1.0, v_lifetime_ratio);
	float alpha_mask = smoothstep(erosion_threshold - 0.18, erosion_threshold + 0.12, v_noise_sample);
	float fresnel = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 0.65);

	// Proximity depth fade eliminates hard intersections against Layer 1 geometry.
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float scene_depth = -upos.z / upos.w;
	float depth_fade = clamp((scene_depth + VERTEX.z) / proximity_fade_distance, 0.0, 1.0);

	ALPHA = clamp(alpha_mask * fresnel * depth_fade * COLOR.a, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.02;
}
