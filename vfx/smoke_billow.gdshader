shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled;

// Per-instance uniforms mutated via set_instance_shader_parameter() without material duplication.
instance uniform float expansion_scale : hint_range(0.1, 2.0) = 1.0;
instance uniform float heat_intensity : hint_range(0.0, 4.0) = 1.0;
instance uniform float erosion_offset : hint_range(-0.5, 0.5) = 0.0;

uniform vec4 core_fire_color : source_color = vec4(1.0, 0.58, 0.14, 1.0);
uniform vec4 hot_ember_color : source_color = vec4(0.92, 0.26, 0.05, 1.0);
uniform vec4 sunlit_smoke_color : source_color = vec4(0.86, 0.87, 0.89, 1.0);
uniform vec4 crevice_smoke_color : source_color = vec4(0.42, 0.44, 0.48, 1.0);
uniform float ambient_scatter_floor : hint_range(0.0, 0.5) = 0.18;
uniform float displacement_strength : hint_range(0.0, 0.8) = 0.34;
uniform float noise_frequency : hint_range(0.5, 6.0) = 2.4;
uniform float scroll_speed : hint_range(0.0, 3.0) = 0.55;
uniform float proximity_fade_distance : hint_range(0.05, 2.0) = 0.45;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying float v_lifetime_ratio;
varying float v_seed;

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

	return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

float fbm3(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	vec3 shift = vec3(17.3, 29.1, 11.7);
	for (int i = 0; i < 3; i++) {
		total += value_noise3d(p) * amp;
		p = p * 2.02 + shift;
		amp *= 0.5;
	}
	return total;
}

void vertex() {
	v_lifetime_ratio = clamp(INSTANCE_CUSTOM.y + erosion_offset, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.x * 5.17 + float(INSTANCE_ID) * 1.31;

	float growth = mix(0.55, 1.35, smoothstep(0.0, 0.45, v_lifetime_ratio)) * expansion_scale;
	vec3 scale_vec = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	) * growth;

	float angle = INSTANCE_CUSTOM.x;
	float s = sin(angle);
	float c = cos(angle);

	// Camera-facing particle billboard with Z-axis spin and preserved process scale.
	mat4 mat_world = mat4(
		normalize(INV_VIEW_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]),
		MODEL_MATRIX[3]
	);
	mat_world = mat_world * mat4(
		vec4(c * scale_vec.x, -s * scale_vec.x, 0.0, 0.0),
		vec4(s * scale_vec.y, c * scale_vec.y, 0.0, 0.0),
		vec4(0.0, 0.0, scale_vec.z, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}

	// Spherical Z-height map for volumetric impostor profile.
	float sphere_z = sqrt(max(0.0, 1.0 - r * r));
	vec3 sample_pos = vec3(p * noise_frequency, sphere_z * 1.2 + v_seed - TIME * scroll_speed);

	float n_base = fbm3(sample_pos);
	float n_detail = fbm3(sample_pos * 1.85 + vec3(n_base * 1.4));
	float cauliflower = mix(n_base, n_detail, 0.55);

	// Warp silhouette perimeter with cauliflower lobes (solid core, billowy rim).
	float warped_r = r - (cauliflower - 0.48) * displacement_strength * smoothstep(0.05, 0.85, r);
	float radial_mask = 1.0 - smoothstep(0.32, 0.92, warped_r);

	// Progressive noise-driven alpha erosion over lifetime.
	float erosion_cutoff = mix(-0.1, 0.72, smoothstep(0.38, 1.0, v_lifetime_ratio));
	float density = smoothstep(
		erosion_cutoff,
		erosion_cutoff + 0.32,
		radial_mask * (0.65 + 0.35 * cauliflower)
	);

	// Finite-difference normal perturbation over the view-space hemisphere.
	float eps = 0.09;
	float nx = fbm3(sample_pos + vec3(eps, 0.0, 0.0)) - cauliflower;
	float ny = fbm3(sample_pos + vec3(0.0, eps, 0.0)) - cauliflower;
	vec2 norm_xy = p * 0.85 + vec2(nx, -ny) * 1.65;
	float norm_z = sqrt(max(0.08, 1.0 - dot(norm_xy, norm_xy)));
	NORMAL = normalize(vec3(norm_xy, norm_z));

	// Lush grey smoke palette: bright sunlit puffs with soft slate-grey folds.
	float ridge_mask = smoothstep(0.24, 0.76, cauliflower * (0.6 + 0.4 * sphere_z));
	vec3 smoke_rgb = mix(crevice_smoke_color.rgb, sunlit_smoke_color.rgb, ridge_mask) * COLOR.rgb;
	ALBEDO = smoke_rgb;
	ROUGHNESS = 0.95;

	// Internal blackbody fire flash during initial expansion + multi-scatter ambient floor.
	float fire_phase = (1.0 - smoothstep(0.02, 0.32, v_lifetime_ratio)) * heat_intensity;
	float inner_fold = (1.0 - ridge_mask) * smoothstep(0.85, 0.15, r);
	vec3 fire_rgb = mix(
		hot_ember_color.rgb,
		core_fire_color.rgb,
		inner_fold
	) * fire_phase * inner_fold * 4.5;
	EMISSION = smoke_rgb * ambient_scatter_floor + fire_rgb;

	// Soft depth buffer contact fade against Physics/Render Layer 1 walls and floor.
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float scene_depth = -upos.z / upos.w;
	float depth_fade = clamp((scene_depth + VERTEX.z) / proximity_fade_distance, 0.0, 1.0);

	ALPHA = clamp(density * depth_fade * COLOR.a, 0.0, 1.0);
}

void light() {
	// Half-Lambert wrap illumination + silver-lining rim scatter for lush volumetric puffs.
	float half_lambert = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float wrap_diffuse = mix(0.38, 1.0, half_lambert * half_lambert);
	float rim_scatter = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2) * 0.35;
	DIFFUSE_LIGHT += (wrap_diffuse + rim_scatter) * LIGHT_COLOR * ATTENUATION * 0.3183;
}
