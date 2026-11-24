shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform int blast_count = 0;
uniform vec4 blast_points[4];
uniform vec4 blast_dirs[4];
uniform float panel_height = 3.0;
uniform vec3 steel_color : source_color = vec3(0.24, 0.19, 0.16);

varying vec3 v_obj_pos;

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
	float pin = smoothstep(0.0, 0.2, VERTEX.y) * smoothstep(0.0, 0.2, panel_height - VERTEX.y);
	for (int i = 0; i < 4; i++) {
		if (i >= blast_count) {
			break;
		}
		float dist = distance(VERTEX, blast_points[i].xyz);
		float r = max(blast_points[i].w, 0.001);
		float t = clamp(1.0 - dist / r, 0.0, 1.0);
		float falloff = t * t;
		VERTEX += blast_dirs[i].xyz * (blast_dirs[i].w * falloff * pin);
	}
}

void fragment() {
	float rust_noise = fbm(v_obj_pos * 18.0);
	float fine_noise = value_noise(v_obj_pos * 64.0 + vec3(2.3, 5.7, 1.1));
	float pat = smoothstep(0.25, 0.78, rust_noise * 0.7 + fine_noise * 0.3);

	vec3 dark_oxide = steel_color * 0.68;
	vec3 rust_tint = steel_color * vec3(1.18, 0.96, 0.84);
	ALBEDO = mix(dark_oxide, rust_tint, pat);
	METALLIC = 0.85;
	ROUGHNESS = 0.55;
}
