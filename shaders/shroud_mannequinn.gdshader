shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_orm : hint_roughness_g, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;

instance uniform float grime_amount : hint_range(0.0, 1.0) = 0.2;
instance uniform vec3 tint_shift : source_color = vec3(1.0);

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	vec4 alb = texture(tex_albedo, UV);
	vec3 orm = texture(tex_orm, UV).rgb;

	// Darken lower hem and AO crevices based on per-instance grime_amount
	float hem_mask = 1.0 - smoothstep(0.0, 0.55, local_y);
	float crevice_mask = 1.0 - orm.r;
	float grime_factor = clamp((hem_mask * 0.75 + crevice_mask * 0.45) * grime_amount, 0.0, 0.85);
	vec3 grime_color = vec3(0.14, 0.13, 0.11);

	ALBEDO = mix(alb.rgb * tint_shift, grime_color, grime_factor);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.75;
	ROUGHNESS = clamp(orm.g + grime_factor * 0.1, 0.08, 1.0);
	METALLIC = orm.b;

	NORMAL_MAP = texture(tex_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}
