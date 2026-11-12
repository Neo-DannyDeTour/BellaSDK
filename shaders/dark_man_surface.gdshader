shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;

uniform float roughness_scale : hint_range(0.1, 2.0) = 1.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float rim_sheen : hint_range(0.0, 1.0) = 0.22;

instance uniform float wear_amount : hint_range(0.0, 1.0) = 0.15;
instance uniform vec4 tint_shift : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec3 base_col = texture(albedo_tex, UV).rgb * tint_shift.rgb;
	vec3 orm = texture(orm_tex, UV).rgb;

	// Edge wear lifts elastomer roughness and slightly desaturates dark surface
	float edge_mask = clamp((1.0 - orm.r) * wear_amount * 2.5, 0.0, 1.0);
	ALBEDO = mix(base_col, base_col + vec3(0.045), edge_mask);

	AO = orm.r;
	AO_LIGHT_AFFECT = 0.85;
	ROUGHNESS = clamp(orm.g * roughness_scale + edge_mask * 0.35, 0.05, 1.0);
	METALLIC = orm.b;

	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;

	// Subtle grazing elastomer sheen without blowing out dark silhouette
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	SPECULAR = clamp(0.5 + fresnel * rim_sheen, 0.0, 1.0);
}
