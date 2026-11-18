shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform float alert_active : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D mugshot_tex : source_color, filter_nearest, repeat_disable;
uniform vec2 led_resolution = vec2(72.0, 108.0);
uniform vec3 warning_bg_color : source_color = vec3(0.96, 0.74, 0.02);
uniform vec3 warning_fg_color : source_color = vec3(0.06, 0.05, 0.03);
uniform vec3 alert_tint_color : source_color = vec3(1.0, 0.85, 0.65);
uniform float emission_strength : hint_range(0.5, 6.0) = 2.4;
uniform float line_scroll_speed : hint_range(0.0, 5.0) = 1.6;

float sd_triangle(vec2 p, float r) {
	const float k = sqrt(3.0);
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) {
		p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	}
	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

vec3 sample_warning_graphic(vec2 uv) {
	vec2 centered = (uv - vec2(0.5)) * vec2(1.0, 1.476);
	vec2 tri_p = vec2(centered.x, -centered.y + 0.03);
	float tri_outer = sd_triangle(tri_p, 0.28);
	float tri_inner = sd_triangle(tri_p, 0.22);

	// Exclamation mark inside warning triangle.
	float excl_bar = sd_box(centered - vec2(0.0, -0.02), vec2(0.024, 0.085));
	float excl_dot = sd_box(centered - vec2(0.0, 0.115), vec2(0.024, 0.024));
	float excl_mask = 1.0 - smoothstep(-0.005, 0.005, min(excl_bar, excl_dot));

	float tri_border = (1.0 - smoothstep(-0.005, 0.005, tri_outer))
		* smoothstep(-0.005, 0.005, tri_inner);
	float icon_mask = clamp(tri_border + excl_mask, 0.0, 1.0);

	// Chopped horizontal lines radiating outward to left and right sides.
	float abs_x = abs(centered.x);
	float side_region = smoothstep(0.27, 0.30, abs_x) * (1.0 - smoothstep(0.62, 0.66, abs_x));
	float band_y = abs(centered.y);
	float row_mask = 1.0 - smoothstep(0.014, 0.018, abs(fract(centered.y * 8.0) - 0.5) * 0.125);
	float row_height_limit = 1.0 - smoothstep(0.24, 0.27, band_y);
	float scroll_phase = abs_x * 10.0 - TIME * line_scroll_speed;
	float chop = step(0.42, fract(scroll_phase));
	float side_lines = side_region * row_mask * row_height_limit * chop;

	float fg_mask = clamp(icon_mask + side_lines, 0.0, 1.0);
	return mix(warning_bg_color, warning_fg_color, fg_mask);
}

void fragment() {
	// Quantize UV to low-resolution TV LED pixel grid.
	vec2 grid_uv = floor(UV * led_resolution) / led_resolution;
	vec2 cell_uv = fract(UV * led_resolution);

	vec3 base_img = vec3(0.0);
	if (alert_active >= 0.5) {
		vec3 mug = texture(mugshot_tex, grid_uv).rgb * alert_tint_color;
		// Subtle pulsing red/yellow frame on wanted state.
		vec2 edge = abs(UV - vec2(0.5));
		float border = step(0.46, max(edge.x, edge.y));
		float pulse = 0.5 + 0.5 * sin(TIME * 8.0);
		base_img = mix(mug, vec3(0.95, 0.18, 0.05), border * (0.5 + 0.5 * pulse));
	} else {
		base_img = sample_warning_graphic(grid_uv);
	}

	// Grazing angle & close-up intensity for TV LED subpixel visibility.
	float ndotv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float grazing = pow(1.0 - ndotv, 1.4);
	float pixel_footprint = max(fwidth(UV.x) * led_resolution.x, fwidth(UV.y) * led_resolution.y);
	float close_factor = 1.0 - smoothstep(0.15, 0.85, pixel_footprint);
	float led_visibility = clamp(max(close_factor, grazing * 1.15), 0.18, 1.0);

	// RGB vertical LED subpixel triads + black pixel matrix gap.
	float r_sub = smoothstep(0.05, 0.12, cell_uv.x) * (1.0 - smoothstep(0.28, 0.34, cell_uv.x));
	float g_sub = smoothstep(0.35, 0.41, cell_uv.x) * (1.0 - smoothstep(0.61, 0.67, cell_uv.x));
	float b_sub = smoothstep(0.68, 0.74, cell_uv.x) * (1.0 - smoothstep(0.90, 0.96, cell_uv.x));
	float row_gap = smoothstep(0.08, 0.16, cell_uv.y) * (1.0 - smoothstep(0.84, 0.92, cell_uv.y));

	vec3 subpixel_mask = vec3(r_sub, g_sub, b_sub) * row_gap * 2.4;
	vec3 led_color = mix(base_img, base_img * subpixel_mask, led_visibility);

	// Slight off-axis CRT/TN LCD color shift & brightness falloff at steep side angles.
	led_color *= mix(1.0, 0.72, grazing);

	ALBEDO = led_color * 0.15;
	ROUGHNESS = 0.18;
	METALLIC = 0.05;
	EMISSION = led_color * emission_strength;
}
