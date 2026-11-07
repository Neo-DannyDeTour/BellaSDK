shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center_uv = vec2(0.5, 0.5);
uniform float blur_strength : hint_range(0.0, 0.25) = 0.08;
uniform float aberration_strength : hint_range(0.0, 0.1) = 0.03;
uniform float jitter_amount : hint_range(0.0, 0.05) = 0.008;
uniform float vignette_power : hint_range(0.0, 4.0) = 2.2;

const int SAMPLES = 8;

void fragment() {
	// High-frequency psychic tremor UV offset.
	vec2 shake = vec2(
		sin(TIME * 73.0 + SCREEN_UV.y * 25.0),
		cos(TIME * 61.0 + SCREEN_UV.x * 25.0)
	) * jitter_amount * intensity * intensity;

	vec2 uv = SCREEN_UV + shake;
	vec2 dir = uv - center_uv;
	float dist = length(dir);

	vec3 accum = vec3(0.0);
	float inv_samples = 1.0 / float(SAMPLES);

	// 8-tap radial zoom blur with split R/G/B chromatic aberration.
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) * inv_samples;
		float scale = 1.0 - t * blur_strength * intensity;
		vec2 sample_uv = center_uv + dir * scale;
		vec2 ab_offset = dir * aberration_strength * intensity * (t + 0.25);

		float r = texture(screen_texture, clamp(sample_uv + ab_offset, 0.0, 1.0)).r;
		float g = texture(screen_texture, clamp(sample_uv, 0.0, 1.0)).g;
		float b = texture(screen_texture, clamp(sample_uv - ab_offset, 0.0, 1.0)).b;
		accum += vec3(r, g, b);
	}
	accum *= inv_samples;

	// Amber/sepia contrast crush + radial vignette dark pressure.
	float luma = dot(accum, vec3(0.2126, 0.7152, 0.0722));
	vec3 sepia = vec3(luma * 1.15, luma * 0.92, luma * 0.65);
	vec3 graded = mix(accum, sepia, intensity * 0.65);
	graded = clamp((graded - 0.5) * (1.0 + intensity * 1.4) + 0.5, 0.0, 1.0);

	float vig = clamp(1.0 - pow(dist * 1.35, vignette_power) * intensity, 0.0, 1.0);
	vec3 final_rgb = mix(texture(screen_texture, SCREEN_UV).rgb, graded * vig, intensity);

	COLOR = vec4(final_rgb, 1.0);
}
