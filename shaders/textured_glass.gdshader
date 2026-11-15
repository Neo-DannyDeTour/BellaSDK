shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

group_uniforms Surface_Pattern;
uniform float pattern_scale : hint_range(1.0, 40.0, 0.5) = 8.0;
uniform float voronoi_mix : hint_range(0.0, 1.0, 0.05) = 0.65;
uniform float normal_strength : hint_range(0.0, 2.0, 0.05) = 0.45;
uniform float smudge_scale : hint_range(0.5, 20.0, 0.5) = 3.5;
uniform float smudge_strength : hint_range(0.0, 1.0, 0.05) = 0.25;

group_uniforms Optics_And_Material;
uniform float refraction_strength : hint_range(0.0, 0.2, 0.002) = 0.045;
uniform float chromatic_aberration : hint_range(0.0, 0.02, 0.0005) = 0.002;
uniform float frost_blur : hint_range(0.0, 5.0, 0.1) = 0.4;
uniform float base_roughness : hint_range(0.0, 1.0, 0.01) = 0.06;
uniform float specular : hint_range(0.0, 1.0, 0.05) = 0.75;
uniform float fresnel_power : hint_range(1.0, 8.0, 0.25) = 4.0;
uniform float fresnel_strength : hint_range(0.0, 1.0, 0.05) = 0.35;
uniform vec4 glass_tint : source_color = vec4(0.86, 0.96, 0.94, 0.14);
uniform vec3 fresnel_color : source_color = vec3(0.92, 0.98, 1.0);

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

// Smooth Voronoi (F1) for rippled / hammered glass cells without hard creases.
float smooth_voronoi(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float res = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g - f + o;
			float d = dot(r, r);
			res += exp(-6.0 * d);
		}
	}
	return -(1.0 / 6.0) * log(max(res, 0.0001));
}

float sample_glass_height(vec2 uv) {
	vec2 p = uv * pattern_scale;
	float wave = fbm(p * 0.65);
	float cells = smooth_voronoi(p + vec2(wave * 0.35));
	return mix(wave, cells, voronoi_mix);
}

void fragment() {
	// Finite-difference tangent-space normal from procedural heightfield.
	float eps = 0.0025;
	float h_c = sample_glass_height(UV);
	float h_x = sample_glass_height(UV + vec2(eps, 0.0));
	float h_y = sample_glass_height(UV + vec2(0.0, eps));
	vec2 grad = vec2(h_c - h_x, h_c - h_y) / eps;
	vec3 normal_ts = normalize(vec3(grad * normal_strength * 0.12, 1.0));

	// Transform perturbed normal to view space for PBR specular + Fresnel.
	NORMAL = normalize(
		TANGENT * normal_ts.x + BINORMAL * normal_ts.y + NORMAL * normal_ts.z
	);

	// Procedural smudge/dust mask modulating roughness and local frost blur.
	float smudge = smoothstep(0.35, 0.85, fbm(UV * smudge_scale + vec2(4.2, 1.7)));
	float local_roughness = clamp(base_roughness + smudge * smudge_strength, 0.02, 1.0);
	float blur_lod = frost_blur + smudge * smudge_strength * 2.5;

	// Screen-space refraction with optional chromatic dispersion.
	vec2 refract_offset = normal_ts.xy * refraction_strength;
	vec2 uv_r = clamp(SCREEN_UV + refract_offset * (1.0 + chromatic_aberration * 40.0), vec2(0.001), vec2(0.999));
	vec2 uv_g = clamp(SCREEN_UV + refract_offset, vec2(0.001), vec2(0.999));
	vec2 uv_b = clamp(SCREEN_UV + refract_offset * (1.0 - chromatic_aberration * 40.0), vec2(0.001), vec2(0.999));

	float r = textureLod(screen_texture, uv_r, blur_lod).r;
	float g = textureLod(screen_texture, uv_g, blur_lod).g;
	float b = textureLod(screen_texture, uv_b, blur_lod).b;
	vec3 refracted = vec3(r, g, b);

	// Schlick Fresnel rim reflection + glass tint absorption.
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, fresnel_power) * fresnel_strength;

	vec3 tinted = mix(refracted, glass_tint.rgb, glass_tint.a);
	vec3 final_glass = mix(tinted, fresnel_color, fresnel);

	ALBEDO = glass_tint.rgb * 0.05;
	EMISSION = final_glass;
	ROUGHNESS = local_roughness;
	METALLIC = 0.0;
	SPECULAR = specular;
	ALPHA = 1.0;
}
