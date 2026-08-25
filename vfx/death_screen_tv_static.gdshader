shader_type canvas_item;

uniform sampler2D image_texture : filter_linear;
uniform float static_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float scanline_count = 240.0;
uniform float vignette_strength = 0.5;

float random_noise(vec2 uv, float time) {
	return fract(sin(dot(uv + vec2(time * 12.9898, time * 78.233), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Subtle CRT scanline effect
	float scanline = sin(uv.y * scanline_count * 3.14159) * 0.08;

	// Image background sampling
	vec4 base_color = texture(image_texture, uv);
	base_color.rgb -= scanline;

	// Procedural high-frequency static noise
	float noise = random_noise(uv, TIME);
	vec3 static_color = vec3(noise);

	// Vignette edge darkening
	vec2 vignette_uv = uv * (1.0 - uv.yx);
	float vig = vignette_uv.x * vignette_uv.y * 15.0;
	vig = clamp(pow(vig, vignette_strength), 0.0, 1.0);

	// Blend static noise with underlying picture
	vec3 final_color = mix(base_color.rgb, static_color, static_intensity) * vig;

	COLOR = vec4(final_color, 1.0);
}
