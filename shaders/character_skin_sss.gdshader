shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;
uniform float detail_normal_scale : hint_range(0.0, 1.5) = 0.25;
uniform float detail_uv_scale : hint_range(1.0, 64.0) = 18.0;
uniform float roughness_scale : hint_range(0.1, 2.0) = 0.92;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.42;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.35;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.65;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.14;
uniform float rim_tint : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	vec4 base_col = texture(albedo_tex, UV) * albedo_tint;
	vec3 orm = texture(orm_tex, UV).rgb;

	vec3 n_base = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	vec3 n_detail = texture(detail_normal_tex, UV * detail_uv_scale).rgb * 2.0 - 1.0;
	vec3 n_blend = normalize(vec3(
		n_base.xy * normal_scale + n_detail.xy * detail_normal_scale,
		max(n_base.z, 0.001)
	));

	ALBEDO = base_col.rgb;
	AO = mix(1.0, orm.r, ao_strength);
	ROUGHNESS = clamp(orm.g * roughness_scale, 0.22, 0.92);
	METALLIC = orm.b * 0.05;
	SPECULAR = specular_amount;
	NORMAL_MAP = n_blend * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	SSS_STRENGTH = sss_strength;
	RIM = rim_amount;
	RIM_TINT = rim_tint;
}
