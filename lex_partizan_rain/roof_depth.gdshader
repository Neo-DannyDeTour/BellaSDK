shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never, depth_test_disabled, cull_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
#if defined(RENDERER_COMPATIBILITY)
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
	bool is_sky = depth >= 0.99999;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	bool is_sky = depth <= 0.00001;
#endif
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 world_position = world.xyz / world.w;
	if (is_sky) {
		world_position.y = -1000.0;
	}
	ALBEDO = world_position;
}
