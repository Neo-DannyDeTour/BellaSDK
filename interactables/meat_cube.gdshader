shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_tex = false;
uniform vec4 base_color : source_color = vec4(0.58, 0.08, 0.07, 1.0);
uniform vec4 fat_color : source_color = vec4(0.88, 0.72, 0.68, 1.0);
uniform float triplanar_scale = 0.8;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.24;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.35;
uniform float jiggle_radius : hint_range(0.1, 4.0) = 1.6;

instance uniform vec3 impact_local_pos = vec3(0.0, 1.0, 0.0);
instance uniform vec3 squish_vector = vec3(0.0);

varying vec3 v_obj_pos;
varying vec3 v_obj_normal;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
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

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise3d(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

vec3 sample_triplanar(sampler2D tex, vec3 pos, vec3 norm) {
	vec3 blend = abs(norm);
	blend = pow(blend, vec3(4.0));
	blend /= max(dot(blend, vec3(1.0)), 0.0001);
	vec3 cx = texture(tex, pos.zy * triplanar_scale).rgb;
	vec3 cy = texture(tex, pos.xz * triplanar_scale).rgb;
	vec3 cz = texture(tex, pos.xy * triplanar_scale).rgb;
	return cx * blend.x + cy * blend.y + cz * blend.z;
}

void vertex() {
	v_obj_pos = VERTEX;
	v_obj_normal = NORMAL;

	float dist = distance(VERTEX, impact_local_pos);
	float falloff = exp(-(dist * dist) / max(jiggle_radius * jiggle_radius, 0.001));

	// Global volume-preserving squash/stretch + localized impact indent
	float compress_y = squish_vector.y;
	float bulge_xz = -compress_y * 0.45;
	vec3 global_deform = vec3(
		VERTEX.x * bulge_xz + squish_vector.x * 0.35,
		VERTEX.y * compress_y,
		VERTEX.z * bulge_xz + squish_vector.z * 0.35
	);
	vec3 local_deform = squish_vector * falloff * 0.65;
	VERTEX += global_deform + local_deform;
}

void fragment() {
	vec3 p = v_obj_pos * 3.5;
	float marble = fbm(p + vec3(0.0, fbm(p * 1.6), 0.0));
	float marbling_mask = smoothstep(0.56, 0.78, marble);

	vec3 meat_albedo = mix(base_color.rgb, fat_color.rgb, marbling_mask);
	if (use_albedo_tex) {
		meat_albedo *= sample_triplanar(albedo_tex, v_obj_pos, v_obj_normal);
	}

	float micro = fbm(v_obj_pos * 18.0);
	ALBEDO = meat_albedo * (0.85 + 0.3 * micro);
	ROUGHNESS = clamp(roughness_val - marbling_mask * 0.08 + (micro - 0.5) * 0.06, 0.05, 1.0);
	SPECULAR = 0.65;

	// Object-space finite difference bump -> view-space NORMAL
	float eps = 0.02;
	float h0 = fbm(v_obj_pos * 14.0);
	float hx = fbm((v_obj_pos + vec3(eps, 0.0, 0.0)) * 14.0) - h0;
	float hy = fbm((v_obj_pos + vec3(0.0, eps, 0.0)) * 14.0) - h0;
	float hz = fbm((v_obj_pos + vec3(0.0, 0.0, eps)) * 14.0) - h0;
	vec3 obj_grad = vec3(hx, hy, hz) / eps;
	vec3 bumped_obj_n = normalize(v_obj_normal - obj_grad * bump_strength * 0.08);
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(bumped_obj_n, 0.0))).xyz);
}
