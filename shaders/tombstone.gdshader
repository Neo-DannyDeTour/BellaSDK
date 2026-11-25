shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 stone_uv_scale = vec2(1.5, 2.2);

uniform vec3 stone_tint : source_color = vec3(0.88, 0.86, 0.82);
uniform vec3 grime_color : source_color = vec3(0.08, 0.07, 0.06);
uniform vec3 gold_color : source_color = vec3(0.72, 0.60, 0.26);
uniform vec2 emblem_center = vec2(0.5, 0.68);
uniform float emblem_radius = 0.22;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;

instance uniform float grime_height : hint_range(0.0, 1.0) = 0.45;
instance uniform float emblem_opacity : hint_range(0.0, 1.0) = 0.85;
instance uniform float moss_seed = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
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
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p = p * 2.03 + vec2(17.1, 31.7);
		amp *= 0.5;
	}
	return v;
}

// Double concentric crescent horn brackets matching the engraved emblem.
float crescent_brackets_mask(vec2 uv, float wear_noise) {
	vec2 p = (uv - emblem_center) * vec2(1.0, 1.35);
	p.x = abs(p.x);

	float outer_d1 = length(p - vec2(0.02, 0.0)) - emblem_radius;
	float outer_d2 = length(p - vec2(0.0, 0.0)) - (emblem_radius - 0.016);
	float outer_cres = max(outer_d1, -outer_d2);

	float inner_d1 = length(p - vec2(0.015, 0.0)) - (emblem_radius - 0.032);
	float inner_d2 = length(p - vec2(-0.004, 0.0)) - (emblem_radius - 0.045);
	float inner_cres = max(inner_d1, -inner_d2);

	float d = min(outer_cres, inner_cres);
	d = max(d, abs(p.y) - emblem_radius * 0.78);
	d = max(d, 0.075 - p.x);

	float mask = 1.0 - smoothstep(-0.004, 0.005, d);
	return clamp(mask * smoothstep(0.18, 0.75, wear_noise), 0.0, 1.0);
}

void fragment() {
	vec2 seed_offset = vec2(moss_seed * 0.37, moss_seed * 0.23);
	vec2 tex_uv = UV * stone_uv_scale + seed_offset;
	vec2 st = UV * vec2(3.5, 6.0) + seed_offset * 10.0;

	// PBR granite textures + procedural vertical water-streak wear.
	vec3 tex_albedo = texture(albedo_tex, tex_uv).rgb * stone_tint;
	vec3 tex_norm = texture(normal_tex, tex_uv).rgb;
	vec3 tex_orm = texture(orm_tex, tex_uv).rgb;

	float streak = fbm(st * vec2(2.2, 0.45));
	float fine_grain = fbm(st * 4.5 + streak * 0.8);

	// Recessed face mask (COLOR.r == 1.0) & normalized height (COLOR.g).
	float is_recessed = COLOR.r;
	float norm_h = COLOR.g;

	// Darkening around the recessed inset border.
	vec2 border_dist = min(UV, 1.0 - UV);
	float edge_ao = smoothstep(0.0, 0.08, min(border_dist.x, border_dist.y));
	vec3 base_stone = tex_albedo * mix(1.0, mix(0.45, 1.0, edge_ao), is_recessed);

	// Gold emblem on recessed face.
	float gold_mask = crescent_brackets_mask(UV, fine_grain) * is_recessed * emblem_opacity;
	vec3 col = mix(base_stone, gold_color, gold_mask);

	// Bottom-up dirt/moisture gradient.
	float grime_top = max(grime_height + (streak - 0.5) * 0.28, 0.01);
	float grime_mask = clamp(1.0 - smoothstep(0.05, grime_top, norm_h), 0.0, 1.0);
	col = mix(col, grime_color, grime_mask * 0.88);

	ALBEDO = col;
	AO = mix(tex_orm.r, 1.0, gold_mask * 0.5);
	ROUGHNESS = mix(mix(tex_orm.g, 0.96, grime_mask), 0.42, gold_mask);
	METALLIC = mix(tex_orm.b, 0.65, gold_mask);
	NORMAL_MAP = tex_norm;
	NORMAL_MAP_DEPTH = normal_strength;
}
