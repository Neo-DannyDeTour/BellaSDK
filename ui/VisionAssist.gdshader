shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, cull_disabled;

// 0 = Black & White (White Level + Black Outlines)
// 1 = Blue (Solid Slate Blue + Light Outlines)
// 2 = Pure Black (Black Level + White Outlines)
// 3 = Neutral Grey (Medium Grey + White Outlines)
// 4 = Desaturated (Greyscale Scene Texture)
uniform int mode : hint_range(0, 4) = 1;

uniform vec4 blue_base : source_color = vec4(0.05, 0.1, 0.45, 1.0);
uniform vec4 blue_outline : source_color = vec4(0.3, 0.5, 0.9, 1.0);
uniform vec4 grey_base : source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform vec4 grey_outline : source_color = vec4(0.85, 0.85, 0.85, 1.0);

uniform float outline_thickness : hint_range(0.5, 5.0) = 1.0;
uniform float depth_threshold = 0.025;
uniform float normal_threshold = 0.5;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	vec2 texel = (1.0 / VIEWPORT_SIZE) * outline_thickness;

	// --- EDGE DETECTION ---
	float d_center = texture(depth_texture, screen_uv).x;
	float d_up = texture(depth_texture, screen_uv + vec2(0.0, texel.y)).x;
	float d_down = texture(depth_texture, screen_uv + vec2(0.0, -texel.y)).x;
	float d_left = texture(depth_texture, screen_uv + vec2(texel.x, 0.0)).x;
	float d_right = texture(depth_texture, screen_uv + vec2(-texel.x, 0.0)).x;

	float depth_edge = abs(d_center - d_up) + abs(d_center - d_down) +
	                   abs(d_center - d_left) + abs(d_center - d_right);

	vec3 n_center = texture(normal_texture, screen_uv).rgb;
	vec3 n_up = texture(normal_texture, screen_uv + vec2(0.0, texel.y)).rgb;
	vec3 n_down = texture(normal_texture, screen_uv + vec2(0.0, -texel.y)).rgb;
	vec3 n_left = texture(normal_texture, screen_uv + vec2(texel.x, 0.0)).rgb;
	vec3 n_right = texture(normal_texture, screen_uv + vec2(-texel.x, 0.0)).rgb;

	float normal_edge = distance(n_center, n_up) + distance(n_center, n_down) +
	                    distance(n_center, n_left) + distance(n_center, n_right);

	bool is_edge = (depth_edge > depth_threshold) || (normal_edge > normal_threshold);

	vec3 final_bg = vec3(0.0);

	if (mode == 0) {
		// Pure white level with black outlines
		final_bg = is_edge ? vec3(0.0) : vec3(1.0);
	} else if (mode == 1) {
		// Blue level with lighter blue outlines
		final_bg = is_edge ? blue_outline.rgb : blue_base.rgb;
	} else if (mode == 2) {
		// Pure black level with white outlines
		final_bg = is_edge ? vec3(1.0) : vec3(0.0);
	} else if (mode == 3) {
		// Neutral grey with bright outlines
		final_bg = is_edge ? grey_outline.rgb : grey_base.rgb;
	} else if (mode == 4) {
		// Scene desaturation preserving original lighting and materials
		vec4 screen_col = texture(screen_texture, screen_uv);
		float lum = dot(screen_col.rgb, vec3(0.299, 0.587, 0.114));
		final_bg = vec3(lum);
	}

	ALBEDO = final_bg;
}
