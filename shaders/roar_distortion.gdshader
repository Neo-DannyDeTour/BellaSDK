shader_type canvas_item;

const int BLUR_SAMPLES = 8;
const vec2 CENTER = vec2(0.5, 0.5);

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float wave_speed : hint_range(0.0, 30.0) = 18.0;
uniform float wave_frequency : hint_range(0.0, 100.0) = 45.0;
uniform float wave_strength : hint_range(0.0, 0.1) = 0.025;
uniform float blur_strength : hint_range(0.0, 0.3) = 0.12;
uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.015;
uniform float ring_highlight : hint_range(0.0, 0.3) = 0.08;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 dir = uv - CENTER;
	float dist = length(dir * aspect);
	vec2 norm_dir = normalize(dir + vec2(0.0001));

	float center_mask = smoothstep(0.05, 0.35, dist) * intensity;

	float wave = sin(dist * wave_frequency - TIME * wave_speed);
	wave = sign(wave) * pow(abs(wave), 0.6);
	vec2 wave_offset = norm_dir * wave * wave_strength * center_mask;

	vec3 final_color = vec3(0.0);
	float inv_samples = 1.0 / float(BLUR_SAMPLES);
	float inv_denom = 1.0 / float(BLUR_SAMPLES - 1);

	for (int i = 0; i < BLUR_SAMPLES; i++) {
		float t = float(i) * inv_denom;
		vec2 sample_uv = uv + wave_offset - (dir * t * blur_strength * center_mask);
		float ca_offset = t * chromatic_aberration * center_mask;

		float r = texture(screen_texture, sample_uv + norm_dir * ca_offset).r;
		float g = texture(screen_texture, sample_uv).g;
		float b = texture(screen_texture, sample_uv - norm_dir * ca_offset).b;

		final_color += vec3(r, g, b);
	}

	final_color *= inv_samples;
	final_color += max(0.0, wave) * ring_highlight * center_mask;

	COLOR = vec4(final_color, 1.0);
}
