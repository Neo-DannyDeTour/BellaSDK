shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 core_color : source_color = vec4(0.16, 0.005, 0.01, 1.0);
uniform vec4 edge_color : source_color = vec4(0.58, 0.015, 0.015, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.12;
uniform float specular_val : hint_range(0.0, 1.0) = 0.85;
uniform float stretch_mult : hint_range(1.0, 6.0) = 2.6;

varying float v_seed;
varying float v_life;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_seed = INSTANCE_CUSTOM.x;
	v_life = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);

	// Align local Y along velocity vector provided by ParticleProcessMaterial align_y.
	vec3 vel_view = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xyz;
	float vel_len = length(vel_view);
	vec3 axis_y = vel_len > 0.0001 ? (vel_view / vel_len) : vec3(0.0, 1.0, 0.0);

	vec3 raw_x = cross(axis_y, vec3(0.0, 0.0, 1.0));
	vec3 axis_x = length(raw_x) > 0.001 ? normalize(raw_x) : vec3(1.0, 0.0, 0.0);
	vec3 axis_z = normalize(cross(axis_x, axis_y));

	float scale_x = length(MODEL_MATRIX[0].xyz);
	float dynamic_stretch = mix(stretch_mult, 1.1, v_life);
	float scale_y = length(MODEL_MATRIX[1].xyz) * dynamic_stretch;

	MODELVIEW_MATRIX = mat4(
		vec4(axis_x * scale_x, 0.0),
		vec4(axis_y * scale_y, 0.0),
		vec4(axis_z * scale_x, 0.0),
		VIEW_MATRIX * MODEL_MATRIX[3]
	);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	// Taper width along Y to form an elongated teardrop/streak profile.
	uv.x *= mix(1.45, 0.75, clamp(UV.y, 0.0, 1.0));

	float radial_dist = length(uv);
	vec2 noise_uv = UV * vec2(4.5, 3.0) + vec2(v_seed * 17.3, v_seed * 9.1);
	float n1 = value_noise(noise_uv);
	float n2 = value_noise(noise_uv * 2.3 + vec2(3.7, 1.9));
	float liquid_mask = (1.0 - radial_dist) + (n1 * 0.45 + n2 * 0.25) - 0.28;

	float rim = clamp(radial_dist * 1.15, 0.0, 1.0);
	ALBEDO = mix(core_color.rgb, edge_color.rgb, rim) * COLOR.rgb;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;
	METALLIC = 0.0;

	ALPHA = clamp(liquid_mask, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = clamp(0.32 + v_life * 0.52, 0.3, 0.88);
}
