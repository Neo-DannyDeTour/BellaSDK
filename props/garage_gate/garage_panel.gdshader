shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D orm_texture : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec4 base_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float uv_scale : hint_range(0.1, 10.0) = 1.0;

instance uniform float wear_offset : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV * uv_scale + vec2(wear_offset * 0.37, wear_offset * 0.19);
	vec3 albedo_tex = texture(albedo_texture, uv).rgb;
	vec3 orm = texture(orm_texture, uv).rgb;

	// Subtle per-panel grime modulation via instance uniform
	float grime = mix(1.0, 0.88, wear_offset);
	ALBEDO = albedo_tex * base_tint.rgb * grime;
	AO = orm.r;
	ROUGHNESS = clamp(orm.g + (wear_offset * 0.08), 0.05, 1.0);
	METALLIC = orm.b;
	NORMAL_MAP = texture(normal_texture, uv).rgb;
}
