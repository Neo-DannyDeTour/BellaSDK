shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float threshold : hint_range(0.0, 1.0) = 0.45;
uniform float softness : hint_range(0.001, 0.5) = 0.04;
uniform float jitter_strength : hint_range(0.0, 0.05) = 0.005;
uniform float flash_boost : hint_range(0.0, 1.0) = 0.0;
uniform vec4 light_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 dark_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	// Slight high-frequency jitter for cinematic intro tension.
	vec2 shake = vec2(
		sin(TIME * 67.0 + SCREEN_UV.y * 30.0),
		cos(TIME * 53.0 + SCREEN_UV.x * 30.0)
	) * jitter_strength * intensity;

	vec4 screen_col = texture(screen_texture, clamp(SCREEN_UV + shake, 0.0, 1.0));

	// Standard Rec. 709 luminance calculation.
	float luma = dot(screen_col.rgb, vec3(0.2126, 0.7152, 0.0722));

	// Dynamic harsh black & white thresholding with smoothstep edge band.
	float t_low = max(0.0, threshold - softness);
	float t_high = min(1.0, threshold + softness);
	float edge = smoothstep(t_low, t_high, luma);

	vec3 threshold_bw = mix(dark_color.rgb, light_color.rgb, edge);

	// Optional flash bloom / overexposure boost during peak pulse.
	threshold_bw += vec3(flash_boost * edge);

	// Blend smoothly between original screen render and harsh b&w based on intensity.
	vec3 final_rgb = mix(screen_col.rgb, threshold_bw, intensity);

	COLOR = vec4(final_rgb, 1.0);
}
