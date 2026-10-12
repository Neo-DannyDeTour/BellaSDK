shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 wind_color : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float scroll_speed : hint_range(-10.0, 10.0) = 3.0;
uniform float column_opacity : hint_range(0.0, 1.0) = 0.08;
uniform float fresnel_power : hint_range(0.5, 6.0) = 3.0;

void fragment() {
	// Positive speed scrolls UV downward, causing visual flow upward
	vec2 uv_scrolled = vec2(UV.x, UV.y + (TIME * scroll_speed * 0.5));
	float noise = texture(noise_texture, uv_scrolled).r;

	// Curved falloff at cylinder extremities
	float edge_fade = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.75, UV.y);

	// Rim highlight to define the volume silhouette softly
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);

	ALBEDO = wind_color.rgb;
	ALPHA = noise * edge_fade * (fresnel * 0.6 + 0.4) * column_opacity * wind_color.a;
}
