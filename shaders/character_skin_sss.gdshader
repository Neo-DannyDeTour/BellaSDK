shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, sss_mode_skin;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float normal_scale : hint_range(0.0, 2.0) = 0.35;
uniform float detail_normal_scale : hint_range(0.0, 1.5) = 0.03;
uniform float detail_uv_scale : hint_range(1.0, 64.0) = 14.0;
uniform float roughness_scale : hint_range(0.1, 2.0) = 0.95;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.28;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.25;
uniform vec4 sss_transmittance_color : source_color = vec4(0.92, 0.45, 0.34, 0.20);
uniform float sss_transmittance_depth : hint_range(0.01, 2.0) = 0.12;
uniform float sss_transmittance_boost : hint_range(0.0, 1.0) = 0.05;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.48;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.05;
uniform float rim_tint : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	vec4 base_col = texture(albedo_tex, UV) * albedo_tint;
	vec3 orm = texture(orm_tex, UV).rgb;

	vec2 nb_xy = texture(normal_tex, UV).rg * 2.0 - 1.0;
	vec2 nd_xy = texture(detail_normal_tex, UV * detail_uv_scale).rg * 2.0 - 1.0;
	float nb_z = sqrt(max(1.0 - dot(nb_xy, nb_xy), 0.001));
	vec3 n_blend = normalize(vec3(
		nb_xy * normal_scale + nd_xy * detail_normal_scale,
		nb_z
	));

	ALBEDO = base_col.rgb;
	AO = mix(1.0, orm.r, ao_strength);
	ROUGHNESS = clamp(orm.g * roughness_scale, 0.52, 0.84);
	METALLIC = orm.b * 0.05;
	SPECULAR = specular_amount;
	NORMAL_MAP = n_blend * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	SSS_STRENGTH = sss_strength;
	SSS_TRANSMITTANCE_COLOR = sss_transmittance_color;
	SSS_TRANSMITTANCE_DEPTH = sss_transmittance_depth;
	SSS_TRANSMITTANCE_BOOST = sss_transmittance_boost;
	RIM = rim_amount;
	RIM_TINT = rim_tint;
}
