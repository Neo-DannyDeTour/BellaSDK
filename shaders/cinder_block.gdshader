shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.42, 0.43, 0.41);
uniform vec3 grime_color : source_color = vec3(0.18, 0.17, 0.15);
uniform float noise_scale : hint_range(1.0, 100.0) = 28.0;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.45;
instance uniform float grime_seed : hint_range(0.0, 100.0) = 0.0;

varying vec3 v_obj_pos;
varying vec3 v_obj_normal;

float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(
			mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x),
			f.y
		),
		mix(
			mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x),
			f.y
		),
		f.z
	);
}

float fbm(vec3 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += value_noise(p) * amp;
		p *= 2.15;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_obj_pos = VERTEX;
	v_obj_normal = abs(NORMAL);
}

void fragment() {
	vec3 seed_offset = vec3(grime_seed * 1.37, grime_seed * 2.91, grime_seed * 0.73);
	vec3 p = (v_obj_pos * noise_scale) + seed_offset;

	float pores = fbm(p);
	float macro_grime = fbm(v_obj_pos * 4.5 + seed_offset);
	float cavity_ao = COLOR.r;

	vec3 col = mix(grime_color, base_color, smoothstep(0.25, 0.75, pores * macro_grime));
	ALBEDO = col * cavity_ao;
	ROUGHNESS = clamp(mix(0.96, 0.78, pores), 0.0, 1.0);
	SPECULAR = 0.15;

	float eps = 0.02;
	float dx = fbm(p + vec3(eps, 0.0, 0.0)) - pores;
	float dy = fbm(p + vec3(0.0, eps, 0.0)) - pores;
	NORMAL_MAP = normalize(vec3(-dx * bump_strength, -dy * bump_strength, 1.0)) * 0.5 + 0.5;
}
