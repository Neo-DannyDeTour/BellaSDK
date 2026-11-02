shader_type canvas_item;

uniform vec2 rect_size = vec2(400.0, 48.0);
uniform vec2 mouse_pos = vec2(200.0, 24.0);
uniform float hover_intensity : hint_range(0.0, 1.0) = 0.0;

uniform vec4 tile_color : source_color = vec4(0.95, 0.05, 0.05, 0.92);
uniform vec4 core_glow_color : source_color = vec4(1.0, 0.35, 0.25, 1.0);

uniform float corner_cut : hint_range(0.0, 32.0) = 8.0;
uniform float tile_size : hint_range(4.0, 32.0) = 8.5;
uniform float effect_radius : hint_range(40.0, 500.0) = 220.0;
uniform float ripple_freq : hint_range(0.02, 0.3) = 0.11;
uniform float ripple_speed : hint_range(0.5, 10.0) = 3.8;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

mat2 rot2d(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

float sd_chamfer_box(vec2 p, vec2 b, float chamfer) {
	vec2 d = abs(p) - b;
	float box_dist = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
	float ch_dist = (abs(p.x) + abs(p.y)) - (b.x + b.y - chamfer);
	return max(box_dist, ch_dist * 0.70710678);
}

void fragment() {
	if (hover_intensity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 safe_size = max(rect_size, vec2(1.0));
		vec2 pixel_pos = UV * safe_size;
		vec2 half_size = safe_size * 0.5;
		vec2 centered_pos = pixel_pos - half_size;

		float cut = min(corner_cut, min(half_size.x, half_size.y) * 0.6);
		float box_sdf = sd_chamfer_box(centered_pos, half_size, cut);
		float inside_mask = 1.0 - smoothstep(0.0, 1.5, box_sdf);

		// Separated Square Grid Surface around Mouse
		vec2 to_mouse = pixel_pos - mouse_pos;
		float dist = length(to_mouse);
		float radial_norm = clamp(dist / max(effect_radius, 1.0), 0.0, 1.0);

		// Rotate grid by 45 degrees for diamond/square lattice
		vec2 rot_pos = rot2d(0.785398) * (pixel_pos - mouse_pos);
		vec2 cell_id = floor(rot_pos / tile_size);
		vec2 cell_uv = fract(rot_pos / tile_size) - vec2(0.5);

		vec2 cell_center_rot = (cell_id + vec2(0.5)) * tile_size;
		vec2 cell_center_local = (rot2d(-0.785398) * cell_center_rot) + mouse_pos;
		float cell_dist = length(cell_center_local - mouse_pos);
		float cell_radial = clamp(cell_dist / max(effect_radius, 1.0), 0.0, 1.0);

		float rnd = hash21(cell_id);

		// Concentric wave rings + central solid core
		float wave = sin(cell_dist * ripple_freq - TIME * ripple_speed) * 0.5 + 0.5;
		float core_mask = 1.0 - smoothstep(14.0, 44.0, cell_dist);
		float ring_envelope = (1.0 - smoothstep(0.12, 1.0, cell_radial)) * wave;

		// Random scatter pruning in outer rings
		float scatter_keep = step(cell_radial * 0.68, rnd + core_mask);
		float tile_scale = mix(
			clamp(ring_envelope * 0.92 * scatter_keep, 0.0, 0.88),
			0.96,
			core_mask
		);

		// Slight per-tile rotation jitter in the shattered wave zone
		float jitter_angle = (rnd - 0.5) * 0.55 * (1.0 - core_mask) * ring_envelope;
		vec2 tilted_uv = rot2d(jitter_angle) * cell_uv;

		float half_tile = tile_scale * 0.5;
		vec2 tile_d = abs(tilted_uv) - vec2(half_tile);
		float tile_sdf = max(tile_d.x, tile_d.y);
		float aa = 1.25 / tile_size;
		float square_mask = (1.0 - smoothstep(-aa, aa, tile_sdf)) * step(0.06, tile_scale);

		// Subtle inner bevel highlight on each square
		float square_edge = smoothstep(-aa * 3.0, 0.0, tile_sdf) * square_mask;
		vec3 sq_rgb = mix(
			tile_color.rgb,
			core_glow_color.rgb,
			core_mask * 0.45 + square_edge * 0.35
		);
		float sq_alpha = square_mask * tile_color.a * (1.0 - pow(radial_norm, 1.6));

		// Subtle left crimson accent bar + dark ambient backing inside row
		float left_accent = (1.0 - smoothstep(0.0, 3.5, pixel_pos.x)) * inside_mask * 0.85;
		float bg_alpha = inside_mask * 0.38 * (1.0 - radial_norm * 0.4);
		vec3 surface_rgb = mix(sq_rgb * sq_alpha, core_glow_color.rgb, left_accent);
		float surface_alpha = clamp(bg_alpha + sq_alpha + left_accent, 0.0, 1.0) * inside_mask;

		COLOR = vec4(surface_rgb, surface_alpha * hover_intensity);
	}
}
