shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 curvature = vec2(0.35, -0.25);
uniform vec2 edge_feather = vec2(0.18, 0.22);

instance uniform vec4 tint : source_color = vec4(0.35, 0.75, 1.0, 1.0);
instance uniform vec2 uv_scale = vec2(3.2, 0.24);
instance uniform vec2 scroll_speed = vec2(0.0, -0.65);
instance uniform float noise_power = 3.0;
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// UV ranges [0..1]. Center X around 0.0 [-0.5..0.5], Y from bottom to top.
	float centered_x = UV.x - 0.5;
	float height_factor = 1.0 - UV.y;
	// Parabolic horizontal bow + vertical crest sweep.
	VERTEX.z += (centered_x * centered_x) * curvature.x * 4.0;
	VERTEX.z += sin(height_factor * PI) * curvature.y;
}

void fragment() {
	vec2 scrolled_uv = UV * uv_scale + (TIME * scroll_speed);
	float n = texture(noise_tex, scrolled_uv).r;
	float dissolved = pow(max(n, 0.001), noise_power);

	// Analytical UV edge mask replacing external painted PNG mask.
	float mask_x = smoothstep(0.0, edge_feather.x, UV.x)
			* smoothstep(1.0, 1.0 - edge_feather.x, UV.x);
	float mask_y = smoothstep(0.0, edge_feather.y, UV.y)
			* smoothstep(1.0, 1.0 - edge_feather.y, UV.y);
	float edge_mask = mask_x * mask_y;

	float final_alpha = clamp(dissolved * edge_mask * tint.a * fade, 0.0, 1.0);
	ALBEDO = tint.rgb * dissolved * 2.0;
	ALPHA = final_alpha;
}
