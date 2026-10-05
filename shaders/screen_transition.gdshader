shader_type canvas_item;

uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float fade_amount : hint_range(0.0, 1.0) = 0.0;
uniform float blur_amount : hint_range(0.0, 5.0) = 0.0;
uniform float blink_openness : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 screen_col = textureLod(screen_texture, SCREEN_UV, blur_amount);

	float center_offset = abs(UV.x - 0.5) * 2.0;
	float curvature = 1.0 - (center_offset * center_offset * 0.3);
	float eyelid_boundary = blink_openness * 0.75 * curvature;

	float edge_feather = 0.035;
	float top_lid = smoothstep(
		0.5 - eyelid_boundary - edge_feather,
		0.5 - eyelid_boundary + edge_feather,
		UV.y
	);
	float bottom_lid = smoothstep(
		0.5 + eyelid_boundary + edge_feather,
		0.5 + eyelid_boundary - edge_feather,
		UV.y
	);
	float eye_mask = clamp(top_lid * bottom_lid, 0.0, 1.0);

	if (blink_openness <= 0.001) {
		eye_mask = 0.0;
	}

	vec3 visual = mix(fade_color.rgb, screen_col.rgb, eye_mask);
	vec3 final_rgb = mix(visual, fade_color.rgb, fade_amount);

	float blur_alpha = clamp(blur_amount / 0.05, 0.0, 1.0);
	float eye_content_alpha = max(fade_amount, blur_alpha);
	float final_alpha = max(1.0 - eye_mask, eye_content_alpha);

	COLOR = vec4(final_rgb, final_alpha);
}
