shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform bool enable_desaturation = true;
uniform float desaturation_amount : hint_range(0.0, 1.0) = 0.65;
uniform float trail_decay : hint_range(0.1, 0.99) = 0.9;
uniform float zoom_amount : hint_range(0.0, 0.05) = 0.005;
uniform float drunk_speed : hint_range(0.0, 20.0) = 3.5;
uniform float drunk_amplitude : hint_range(0.0, 0.05) = 0.003;
uniform float blur_radius : hint_range(0.0, 5.0) = 1.5;
uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.003;

const int TAP_COUNT = 8;
const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);

void fragment() {
	if (intensity <= 0.0001) {
		COLOR = texture(screen_texture, SCREEN_UV);
	} else {
		float t = TIME * drunk_speed;
		vec2 wave_offset = vec2(
			sin(SCREEN_UV.y * 10.0 + t) + cos(SCREEN_UV.x * 6.0 + t * 0.8),
			cos(SCREEN_UV.x * 10.0 + t) + sin(SCREEN_UV.y * 6.0 + t * 1.2)
		) * (drunk_amplitude * intensity);

		vec2 base_uv = SCREEN_UV + wave_offset;
		vec2 center_dir = base_uv - vec2(0.5);
		vec2 ca_shift = center_dir * (chromatic_aberration * intensity * 2.0);
		float radial_step = zoom_amount * blur_radius * intensity;

		vec3 accum_col = vec3(0.0);
		float weight_sum = 0.0;
		float current_weight = 1.0;

		for (int i = 0; i < TAP_COUNT; i++) {
			float tap_scale = 1.0 - (float(i) * radial_step);
			vec2 tap_uv = vec2(0.5) + center_dir * tap_scale;

			float r = texture(screen_texture, clamp(tap_uv + ca_shift, vec2(0.0), vec2(1.0))).r;
			float g = texture(screen_texture, clamp(tap_uv, vec2(0.0), vec2(1.0))).g;
			float b = texture(screen_texture, clamp(tap_uv - ca_shift, vec2(0.0), vec2(1.0))).b;

			accum_col += vec3(r, g, b) * current_weight;
			weight_sum += current_weight;
			current_weight *= trail_decay;
		}

		vec3 final_rgb = accum_col / max(weight_sum, 0.0001);

		if (enable_desaturation) {
			float luma = dot(final_rgb, LUMA_WEIGHTS);
			final_rgb = mix(final_rgb, vec3(luma), desaturation_amount * intensity);
		}

		COLOR = vec4(final_rgb, 1.0);
	}
}
