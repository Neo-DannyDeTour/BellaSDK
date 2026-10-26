shader_type canvas_item;
render_mode unshaded;

// Color and baseline opacity of anime speed lines.
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);

// Inner circle radius where lines fade out completely to keep player view clear.
uniform float center_radius : hint_range(0.0, 1.0) = 0.38;

// Softness of center radial fade boundary.
uniform float feather : hint_range(0.01, 0.5) = 0.18;

// Total angular count/density of radial speed rays.
uniform float line_density : hint_range(10.0, 200.0) = 90.0;

// Frame rate / frequency of temporal ray jitter (simulating animated anime action).
uniform float jitter_speed : hint_range(1.0, 50.0) = 24.0;

// Master opacity driven by tween when wall running.
uniform float effect_alpha : hint_range(0.0, 1.0) = 0.0;

// High-speed pseudo-random generator
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float dist = length(p);

	if (effect_alpha <= 0.001 || dist < center_radius) {
		COLOR = vec4(0.0);
	} else {
		// Polar angle in radians [-PI, PI] mapped to [0.0, 1.0]
		float angle = atan(p.y, p.x);
		float norm_angle = (angle + 3.14159265359) / 6.28318530718;

		// Quantized anime flicker time step
		float time_step = floor(TIME * jitter_speed);

		// Angular ray sector indexing (rounded density avoids seam at 0 / 2*PI)
		float density = round(line_density);
		float ray_coord = norm_angle * density;
		float ray_idx = mod(floor(ray_coord), density);
		float ray_frac = fract(ray_coord);

		// Procedural ray presence, inner start offset, and width per sector
		float ray_seed = hash(vec2(ray_idx, time_step));
		float ray_seed2 = hash(vec2(ray_idx * 1.73 + 3.1, time_step * 0.91 + 5.7));

		// Spawn lines on high-activation rays (~42% density of total sectors)
		float ray_active = step(0.58, ray_seed);

		// Staggered ray inner reach (some rays stretch closer into center than others)
		float ray_start = center_radius + ray_seed2 * 0.15;
		float radial_fade = smoothstep(ray_start, ray_start + feather, dist);

		// Triangular / tapered ray profile centered within sector
		float dist_from_ray_center = abs(ray_frac - 0.5) * 2.0;
		float line_width = mix(
			0.12, 0.45, clamp((dist - center_radius) / (0.75 - center_radius), 0.0, 1.0)
		);
		float ray_shape = smoothstep(line_width, 0.0, dist_from_ray_center);

		// Secondary harmonic fine-line layer for anime texture depth
		float density2 = round(line_density * 1.6);
		float ray_coord2 = norm_angle * density2;
		float ray_idx2 = mod(floor(ray_coord2), density2);
		float ray_frac2 = fract(ray_coord2);
		float ray_seed_fine = hash(vec2(ray_idx2 + 77.0, time_step));
		float ray_active_fine = step(0.72, ray_seed_fine);
		float dist_from_center_fine = abs(ray_frac2 - 0.5) * 2.0;
		float ray_shape_fine = smoothstep(0.2, 0.0, dist_from_center_fine);
		float radial_fade_fine = smoothstep(
			center_radius + 0.05, center_radius + feather + 0.1, dist
		);

		// Combine primary and secondary rays
		float primary_streak = ray_active * ray_shape * radial_fade;
		float secondary_streak = ray_active_fine * ray_shape_fine * radial_fade_fine * 0.7;
		float total_streak = clamp(primary_streak + secondary_streak, 0.0, 1.0);

		COLOR = vec4(line_color.rgb, total_streak * line_color.a * effect_alpha);
	}
}
