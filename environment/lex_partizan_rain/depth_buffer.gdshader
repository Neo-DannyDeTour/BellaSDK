shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
#if defined(RENDERER_COMPATIBILITY)
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 world_position = world.xyz / world.w;
	ALBEDO = vec3(world_position.y * 0.05);
}
