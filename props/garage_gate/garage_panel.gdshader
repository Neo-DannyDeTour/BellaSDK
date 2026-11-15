shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D orm_texture : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec4 base_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float uv_scale : hint_range(0.1, 10.0) = 1.0;

instance uniform float wear_offset : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Keep V locked so horizontal stamped sheet-metal ribs align; offset U per panel
	vec2 uv_primary = UV * uv_scale + vec2(wear_offset * 0.43, 0.0);
	// Secondary rotated/scaled lookup breaks up macro tiling across panels
	vec2 uv_breakup = UV * (uv_scale * 1.67) + vec2(0.29 + wear_offset * 0.71, 0.37);

	vec3 albedo_tex = texture(albedo_texture, uv_primary).rgb;
	vec3 albedo_detail = texture(albedo_texture, uv_breakup).rgb;
	vec3 orm = texture(orm_texture, uv_primary).rgb;
	vec3 orm_detail = texture(orm_texture, uv_breakup).rgb;

	// Blend subtle macro breakup without disturbing horizontal rib normal alignment
	vec3 blended_albedo = mix(albedo_tex, albedo_tex * (0.75 + 0.5 * albedo_detail), 0.35);
	float grime = mix(1.0, 0.88, wear_offset);

	ALBEDO = blended_albedo * base_tint.rgb * grime;
	AO = min(orm.r, mix(orm.r, orm_detail.r, 0.35));
	ROUGHNESS = clamp(mix(orm.g, orm_detail.g, 0.25) + (wear_offset * 0.06), 0.05, 1.0);
	METALLIC = orm.b;
	NORMAL_MAP = texture(normal_texture, uv_primary).rgb;
}
