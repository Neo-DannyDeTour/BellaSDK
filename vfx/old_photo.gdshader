shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// Overall age multiplier (0.0 = original, 1.0 = fully aged)
uniform float age : hint_range(0.0, 1.0) = 1.0;

// Sepia & color aging
uniform float sepia_strength : hint_range(0.0, 1.0) = 0.85;
uniform float yellowing : hint_range(0.0, 1.0) = 0.35;
uniform float fade : hint_range(0.0, 1.0) = 0.15;

// Edge wear / Wrinkles
uniform float wrinkle_amount : hint_range(0.0, 1.0) = 0.25;
uniform float wrinkle_scale : hint_range(1.0, 50.0) = 12.0;

// Edge & Corner darkening
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.6;
uniform float vignette_sharpness : hint_range(0.1, 5.0) = 1.8;

// Aging spots / blotches
uniform float spot_density : hint_range(1.0, 50.0) = 15.0;
uniform float spot_strength : hint_range(0.0, 1.0) = 0.45;

// Film / Paper grain
uniform float grain_strength : hint_range(0.0, 1.0) = 0.25;

// Randomization seed
uniform vec2 seed = vec2(12.9898, 78.233);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.1 + seed;
		a *= 0.5;
	}
	return v;
}

vec3 to_sepia(float luminance) {
	vec3 sepia_high = vec3(1.0, 0.89, 0.70);
	vec3 sepia_low = vec3(0.35, 0.25, 0.15);
	return mix(sepia_low, sepia_high, luminance);
}

void add_edge_wrinkling(inout vec2 uv, float edge_mask) {
	vec2 wrinkle_uv = uv * wrinkle_scale + seed;
	vec2 distortion = vec2(
		fbm(wrinkle_uv + vec2(1.7, 9.2)),
		fbm(wrinkle_uv + vec2(8.3, 2.8))
	) * 2.0 - 1.0;

	uv += distortion * wrinkle_amount * 0.1 * edge_mask * age;
	uv = clamp(uv, vec2(0.0), vec2(1.0));
}

void add_sepia_tint(vec2 uv, inout vec3 col) {
	float grayscale = dot(col, vec3(0.299, 0.587, 0.114));
	grayscale = grayscale * 0.88 + 0.06;

	vec3 sepia = to_sepia(grayscale);
	vec3 yellow_tint = vec3(1.0, 0.95, 0.65);

	sepia = mix(sepia, sepia * yellow_tint, yellowing * grayscale);
	col = mix(col, sepia, sepia_strength * age);
}

void add_spots(vec2 uv, inout vec3 col) {
	vec2 spot_uv = uv * spot_density + seed;
	float spot_noise = fbm(spot_uv) * 0.5;
	spot_noise += fbm(spot_uv * 2.3 + vec2(5.2, 1.3)) * 0.3;
	spot_noise += fbm(spot_uv * 4.7 + vec2(1.8, 7.4)) * 0.2;

	float spots = 1.0 - smoothstep(0.65, 0.82, spot_noise);
	vec3 spot_color = vec3(0.28, 0.18, 0.10);

	col = mix(col, col * spot_color, (1.0 - spots) * spot_strength * age);
}

void add_vignette(vec2 uv, inout vec3 col) {
	vec2 d = (uv - 0.5) * 2.0;
	float dist = dot(d, d);
	float vig = clamp(pow(dist, vignette_sharpness * 0.5) * vignette_strength * age, 0.0, 1.0);
	vec3 vig_color = vec3(0.25, 0.18, 0.12);

	col = mix(col, col * vig_color, vig);
}

void add_corner_darkness(vec2 uv, inout vec3 col, float edge_dist) {
	float corner_dist = 1.0 - clamp(edge_dist * 4.0, 0.0, 1.0);
	float corner_noise = fbm(uv * 8.0 + seed);
	float darkness = corner_dist * (0.6 + 0.4 * corner_noise) * age;

	vec3 dark_color = vec3(0.20, 0.12, 0.08);
	col = mix(col, col * dark_color, darkness * 0.6);
}

void add_paper_grain(vec2 uv, inout vec3 col) {
	float grain = hash12(uv * 500.0 + seed);
	grain = grain * 2.0 - 1.0;
	col += grain * grain_strength * 0.1 * age;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	float edge_dist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float edge_mask = 1.0 - smoothstep(0.0, 0.15, edge_dist);

	add_edge_wrinkling(uv, edge_mask);

	vec3 col = texture(screen_texture, uv).rgb;

	add_sepia_tint(uv, col);
	col = mix(col, vec3(1.0), fade * age * 0.5);
	add_spots(uv, col);
	add_vignette(uv, col);
	add_corner_darkness(uv, col, edge_dist);
	add_paper_grain(uv, col);

	COLOR = vec4(col, 1.0);
}
