shader_type canvas_item;

// Required to read the rendered 3D viewport behind this 2D overlay
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Uniforms driven by DioramaPostProcess script (0: Off, 1: CRT, 2: VHS, 3: Pixelate, etc.)
uniform int filter_mode : hint_range(0, 30) = 0;
uniform float grain_amount : hint_range(0.0, 20.0) = 0.0;

// Random noise generator for film grain and spot distribution
float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Fast sepia gradient mapping
vec3 to_sepia(float luminance) {
	vec3 sepia_high = vec3(1.0, 0.89, 0.70);
	vec3 sepia_low = vec3(0.35, 0.25, 0.15);
	return mix(sepia_low, sepia_high, luminance);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// 1. UV Coordinate Transformations (Evaluated prior to sampling)
	if (filter_mode == 3) {
		// Pixelate
		vec2 grid = vec2(160.0, 120.0);
		uv = floor(SCREEN_UV * grid) / grid;
	} else if (filter_mode == 25) {
		// Old Photo: Edge wrinkling distortion
		float edge_dist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		float edge_mask = 1.0 - smoothstep(0.0, 0.15, edge_dist);
		vec2 wrinkle = vec2(
			sin(uv.y * 32.0 + 1.7) + cos(uv.x * 24.0),
			cos(uv.x * 32.0 + 2.8) + sin(uv.y * 24.0)
		) * 0.004 * edge_mask;
		uv = clamp(uv + wrinkle, vec2(0.0), vec2(1.0));
	}

	// 2. Sample the underlying 3D diorama render
	vec4 base_color = texture(screen_texture, uv);
	vec3 final_color = base_color.rgb;

	// 3. Apply Film Grain
	if (grain_amount > 0.0) {
		float noise = (random(SCREEN_UV + vec2(TIME * 0.1, TIME * 0.05)) - 0.5) * (grain_amount * 0.02);
		final_color += noise;
	}

	// 4. Color grading and screen filter passes
	if (filter_mode == 1) {
		// CRT
		float scanline = sin(SCREEN_UV.y * 800.0) * 0.04;
		final_color -= scanline;
	} else if (filter_mode == 5) {
		// Gameboy
		float lum = dot(final_color, vec3(0.299, 0.587, 0.114));
		if (lum < 0.25) {
			final_color = vec3(0.06, 0.22, 0.06);
		} else if (lum < 0.5) {
			final_color = vec3(0.19, 0.38, 0.19);
		} else if (lum < 0.75) {
			final_color = vec3(0.54, 0.67, 0.06);
		} else {
			final_color = vec3(0.61, 0.73, 0.06);
		}
	} else if (filter_mode == 25) {
		// Old Photo: Tonal shift, yellowing, edge burn, and aging blotches
		float gray = dot(final_color, vec3(0.299, 0.587, 0.114)) * 0.88 + 0.06;
		vec3 sepia = to_sepia(gray);
		vec3 yellow_tint = vec3(1.0, 0.95, 0.65);
		sepia = mix(sepia, sepia * yellow_tint, 0.35 * gray);
		final_color = mix(final_color, sepia, 0.85);

		// Faded print wash
		final_color = mix(final_color, vec3(1.0), 0.08);

		// Vignette & corner burning
		vec2 d = (SCREEN_UV - 0.5) * 2.0;
		float vig = clamp(pow(dot(d, d), 0.9) * 0.6, 0.0, 1.0);
		final_color = mix(final_color, vec3(0.25, 0.18, 0.12), vig);

		// Aging blotches & stains
		float spot_noise = random(floor(SCREEN_UV * 26.0));
		if (spot_noise > 0.96) {
			final_color = mix(final_color, vec3(0.28, 0.18, 0.10), 0.38);
		}

		// Micro paper grain
		float paper_grain = (random(SCREEN_UV * 420.0) - 0.5) * 0.04;
		final_color += paper_grain;
	}

	COLOR = vec4(final_color, base_color.a);
}
