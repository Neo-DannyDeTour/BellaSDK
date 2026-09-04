shader_type canvas_item;

uniform vec2 ui_tilt;
uniform float perspective_strength : hint_range(0.0, 0.5) = 0.15;

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_thickness : hint_range(0.5, 8.0) = 2.0;
uniform float corner_cut : hint_range(0.0, 64.0) = 14.0;
uniform vec2 rect_size;
uniform float speed = 1.5;
uniform float trail_length = 0.3;
uniform float hover_intensity : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	vec2 safe_rect = max(rect_size, vec2(1.0));
	vec2 pivot = safe_rect / 2.0;
	vec2 offset = VERTEX - pivot;

	float depth = (offset.x / pivot.x) * ui_tilt.x + (offset.y / pivot.y) * ui_tilt.y;
	float perspective = 1.0 - (depth * perspective_strength);

	VERTEX = pivot + (offset * perspective);
}

void fragment() {
	if (hover_intensity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 half_size = rect_size * 0.5;
		vec2 p = abs((UV * rect_size) - half_size);

		// Analytical distance to straight edges and 45-degree chamfers
		float d_x = half_size.x - p.x;
		float d_y = half_size.y - p.y;
		float d_diag = ((half_size.x + half_size.y - corner_cut) - (p.x + p.y)) * 0.70710678;
		float min_dist = min(min(d_x, d_y), d_diag);

		// Crisp antialiased inner and outer borders
		float outer_mask = smoothstep(-0.5, 0.5, min_dist);
		float inner_mask = smoothstep(line_thickness + 0.5, line_thickness - 0.5, min_dist);
		float border_mask = outer_mask * inner_mask;

		vec2 center = rect_size * 0.5;
		vec2 offset = (UV * rect_size) - center;

		float angle = atan(offset.y, offset.x);
		float norm_angle = (angle + PI) / TAU;

		float time_offset = fract(TIME * speed);
		float diff = abs(norm_angle - time_offset);
		if (diff > 0.5) {
			diff = 1.0 - diff;
		}

		float glow = smoothstep(trail_length, 0.0, diff);
		float base_alpha = 0.18;
		float final_alpha = clamp(base_alpha + glow, 0.0, 1.0) * hover_intensity * border_mask;

		COLOR = vec4(line_color.rgb, final_alpha * line_color.a);
	}
}
