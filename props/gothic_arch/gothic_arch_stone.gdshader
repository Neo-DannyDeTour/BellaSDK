shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_texture : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float normal_scale : hint_range(0.0, 2.0) = 1.15;
uniform float micro_grain_strength : hint_range(0.0, 0.25) = 0.08;
uniform vec3 moss_color : source_color = vec3(0.18, 0.24, 0.14);
uniform float moss_sharpness : hint_range(1.0, 10.0) = 3.5;

instance uniform vec3 instance_tint : source_color = vec3(1.0, 1.0, 1.0);
instance uniform float wear_intensity : hint_range(0.0, 1.0) = 0.35;
instance uniform float moss_coverage : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_normal;
varying vec3 local_pos;

float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float value_noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
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

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	local_pos = VERTEX;
}

void fragment() {
	vec3 base_albedo = texture(albedo_texture, UV).rgb * instance_tint;
	vec3 orm = texture(orm_texture, UV).rgb;
	vec3 normal_map = texture(normal_texture, UV).rgb;

	// 3D triplanar-free procedural limestone micro-grain & vertical weathering
	float grain_hi = value_noise3d(local_pos * 28.0);
	float grain_med = value_noise3d(local_pos * 6.5);
	float grain_mod = (grain_hi * 0.65 + grain_med * 0.35 - 0.5) * 2.0 * micro_grain_strength;

	// Subtle base-of-pillar dampness darkening near floor (Y in [0.0, 0.65])
	float base_damp = smoothstep(0.0, 0.65, local_pos.y);
	float damp_factor = mix(0.82, 1.0, base_damp);

	// Cavity grime & chiselled edge highlight from baked AO + normal slope
	float cavity_mask = clamp(1.0 - orm.r, 0.0, 1.0);
	vec2 n_xy = normal_map.xy * 2.0 - 1.0;
	float bevel_edge = clamp(length(n_xy) * 0.85, 0.0, 1.0);

	vec3 stone_col = (base_albedo + vec3(grain_mod)) * damp_factor;
	stone_col = mix(stone_col, stone_col * 0.42, cavity_mask * wear_intensity);
	stone_col += vec3(0.05, 0.048, 0.042) * bevel_edge * wear_intensity * orm.r;

	vec3 norm = normalize(world_normal);
	float up_mask = clamp(norm.y, 0.0, 1.0);
	float moss_noise = value_noise3d(local_pos * 4.5);
	float moss_mask = clamp(
		pow(up_mask, moss_sharpness) * moss_coverage * orm.r * (0.6 + 0.8 * moss_noise),
		0.0,
		1.0
	);

	ALBEDO = clamp(mix(stone_col, moss_color, moss_mask), vec3(0.0), vec3(1.0));
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.78;
	ROUGHNESS = clamp(mix(orm.g - grain_mod * 0.35, 0.92, moss_mask), 0.1, 1.0);
	METALLIC = orm.b;
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = normal_scale;
}
