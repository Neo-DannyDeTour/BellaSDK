shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float effect_strength : hint_range(0.0, 1.0) = 1.0;
uniform float brightness_boost : hint_range(1.0, 2.0) = 1.25;
uniform float blur_amount : hint_range(0.0, 3.0) = 0.8;

// Deuteranopia transformation matrix approximating canine dichromatic vision
const mat3 DOG_VISION_MATRIX = mat3(
	vec3(0.625, 0.375, 0.0),
	vec3(0.700, 0.300, 0.0),
	vec3(0.000, 0.300, 0.7)
);

void fragment() {
	vec2 uv = SCREEN_UV;

	// Slight acuity blur (simulating ~20/75 vision)
	vec2 pixel_size = SCREEN_PIXEL_SIZE * blur_amount;
	vec4 col = texture(screen_texture, uv) * 0.4;
	col += texture(screen_texture, uv + vec2(pixel_size.x, 0.0)) * 0.15;
	col += texture(screen_texture, uv - vec2(pixel_size.x, 0.0)) * 0.15;
	col += texture(screen_texture, uv + vec2(0.0, pixel_size.y)) * 0.15;
	col += texture(screen_texture, uv - vec2(0.0, pixel_size.y)) * 0.15;

	// Transform RGB space into canine dichromatic space
	vec3 dog_color = DOG_VISION_MATRIX * col.rgb;

	// Enhance contrast and tapetum lucidum low-light brightness
	dog_color *= brightness_boost;

	// Blend with original frame
	COLOR = vec4(mix(col.rgb, dog_color, effect_strength), 1.0);
}
