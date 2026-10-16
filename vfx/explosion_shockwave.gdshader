shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
instance uniform float explosion_progress : hint_range(0.0, 1.0) = 0.0;
instance uniform float distortion_strength : hint_range(0.0, 0.15) = 0.045;
uniform float aberration_amount : hint_range(0.0, 0.03) = 0.008;

float wave_noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float ring_mask = smoothstep(0.25, 0.78, fresnel) * smoothstep(1.0, 0.82, fresnel);
	float fade = pow(1.0 - clamp(explosion_progress, 0.0, 1.0), 1.6);

	float shimmer = wave_noise(UV * 18.0 + vec2(TIME * 4.0)) * 2.0 - 1.0;
	vec2 offset = normalize(NORMAL.xy + vec2(0.0001)) * ring_mask * distortion_strength * fade;
	offset += vec2(shimmer * 0.003 * fade);

	float r = texture(screen_texture, SCREEN_UV + offset * (1.0 + aberration_amount)).r;
	float g = texture(screen_texture, SCREEN_UV + offset).g;
	float b = texture(screen_texture, SCREEN_UV + offset * (1.0 - aberration_amount)).b;

	ALBEDO = vec3(r, g, b);
	ALPHA = clamp(ring_mask * fade * 2.2, 0.0, 1.0);
}
