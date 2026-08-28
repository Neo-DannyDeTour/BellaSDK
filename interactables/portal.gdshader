shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D viewport_texture : source_color, filter_linear;

void fragment() {
	// Sample the matched camera viewport perspective using full-screen UVs
	ALBEDO = texture(viewport_texture, SCREEN_UV).rgb;
}
