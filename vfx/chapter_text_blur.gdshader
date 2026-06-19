shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 5.0) = 0.0;
uniform float fade_amount : hint_range(0.0, 1.0) = 0.0;
uniform float bloom_intensity : hint_range(1.0, 10.0) = 6.0;

// Golden angle for distributing samples in a perfect circle
const float GOLDEN_ANGLE = 2.39996323;

void fragment() {
	vec4 color = vec4(0.0);

	if (blur_amount > 0.0) {
		// Scale up the radius significantly for the blob effect
		float radius = blur_amount * 12.0;
		vec2 ps = TEXTURE_PIXEL_SIZE;

		// 16-tap circular sampling for smooth bokeh
		for (int i = 0; i < 16; i++) {
			float r = sqrt(float(i) + 0.5) / sqrt(16.0);
			float theta = float(i) * GOLDEN_ANGLE;
			vec2 offset = vec2(cos(theta), sin(theta)) * r * radius;
			color += texture(TEXTURE, UV + offset * ps);
		}
		color /= 16.0;

		// Boost brightness based on blur to create the glowing light effect
		float bloom_factor = mix(1.0, bloom_intensity, clamp(blur_amount / 2.0, 0.0, 1.0));
		color.rgb *= bloom_factor;
	} else {
		color = texture(TEXTURE, UV);
	}

	COLOR = color * COLOR;
	COLOR.a *= fade_amount;
}