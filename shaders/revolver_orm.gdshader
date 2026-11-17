shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_orm : hint_roughness_g, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;

instance uniform float wear_contrast : hint_range(0.5, 2.0) = 1.0;
instance uniform float barrel_heat : hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 antigrav_rim_color : source_color = vec4(0.25, 0.65, 1.0, 0.0);

void fragment() {
	vec4 alb = texture(tex_albedo, UV);
	vec3 orm = texture(tex_orm, UV).rgb;

	ALBEDO = alb.rgb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.75;
	ROUGHNESS = clamp(orm.g * wear_contrast, 0.08, 1.0);
	METALLIC = orm.b;

	// OpenGL (+Y) Normal Map
	NORMAL_MAP = texture(tex_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;

	// Per-instance barrel heat & optional zero-G diorama rim emission
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 heat_glow = vec3(1.0, 0.28, 0.05) * barrel_heat * smoothstep(0.55, 0.95, UV.x);
	vec3 rim_glow = antigrav_rim_color.rgb * antigrav_rim_color.a * fresnel;
	EMISSION = heat_glow + rim_glow;
}
