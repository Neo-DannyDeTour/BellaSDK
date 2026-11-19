shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_orm : hint_roughness_g, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;

instance uniform vec3 paint_tint : source_color = vec3(1.0, 1.0, 1.0);
instance uniform float dampness : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 albedo_sample = texture(tex_albedo, UV).rgb;
	vec3 orm_sample = texture(tex_orm, UV).rgb;

	ALBEDO = albedo_sample * paint_tint * mix(1.0, 0.65, dampness);
	AO = orm_sample.r;
	ROUGHNESS = mix(orm_sample.g, 0.25, dampness);
	METALLIC = orm_sample.b;
	NORMAL_MAP = texture(tex_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}
