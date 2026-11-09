shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_texture : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(-4.0, 4.0) = 1.25;

instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec2 uv_scale = vec2(1.0, 1.0);

void fragment() {
	vec2 scaled_uv = UV * uv_scale;
	vec4 albedo_tex = texture(albedo_texture, scaled_uv);
	vec3 orm_tex = texture(orm_texture, scaled_uv).rgb;

	ALBEDO = albedo_tex.rgb * tint.rgb;
	AO = orm_tex.r;
	ROUGHNESS = orm_tex.g;
	METALLIC = orm_tex.b;
	NORMAL_MAP = texture(normal_texture, scaled_uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}
