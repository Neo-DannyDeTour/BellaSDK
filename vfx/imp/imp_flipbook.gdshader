shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform sampler2D flipbook_texture : source_color, filter_linear, repeat_disable;
uniform vec4 tint_color : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float hdr_intensity : hint_range(0.5, 20.0) = 6.5;
uniform int h_frames : hint_range(1, 16) = 8;
uniform int v_frames : hint_range(1, 16) = 8;
uniform float manual_progress : hint_range(0.0, 1.0) = 0.0;
uniform bool use_particle_lifetime = true;
uniform bool billboard = true;
uniform float alpha_boost : hint_range(0.5, 4.0) = 1.6;

varying float v_lifetime;

void vertex() {
	v_lifetime = use_particle_lifetime ? clamp(INSTANCE_CUSTOM.y, 0.0, 1.0) : manual_progress;
	if (billboard) {
		// Preserve per-particle view-space center (MODELVIEW_MATRIX[3]) and scale.
		float c = cos(INSTANCE_CUSTOM.x);
		float s = sin(INSTANCE_CUSTOM.x);
		float sx = length(MODELVIEW_MATRIX[0].xyz);
		float sy = length(MODELVIEW_MATRIX[1].xyz);
		float sz = length(MODELVIEW_MATRIX[2].xyz);
		MODELVIEW_MATRIX = mat4(
			vec4(c * sx, s * sx, 0.0, 0.0),
			vec4(-s * sy, c * sy, 0.0, 0.0),
			vec4(0.0, 0.0, sz, 0.0),
			MODELVIEW_MATRIX[3]
		);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

vec2 get_cell_uv(vec2 uv, float frame_idx, vec2 grid) {
	float col = mod(frame_idx, grid.x);
	float row = floor(frame_idx / grid.x);
	vec2 safe_uv = clamp(uv, vec2(0.004), vec2(0.996));
	return (safe_uv + vec2(col, row)) / grid;
}

void fragment() {
	vec2 grid = vec2(float(h_frames), float(v_frames));
	float total_frames = grid.x * grid.y;
	float exact_frame = clamp(v_lifetime, 0.0, 0.999) * (total_frames - 1.0);
	float frame_a = floor(exact_frame);
	float frame_b = min(frame_a + 1.0, total_frames - 1.0);
	float blend_t = fract(exact_frame);

	vec4 tex_a = texture(flipbook_texture, get_cell_uv(UV, frame_a, grid));
	vec4 tex_b = texture(flipbook_texture, get_cell_uv(UV, frame_b, grid));
	vec4 sample_col = mix(tex_a, tex_b, blend_t);

	float fade_in = smoothstep(0.0, 0.08, v_lifetime);
	float edge_fade = smoothstep(1.0, 0.80, v_lifetime);
	float quad_mask = smoothstep(0.5, 0.44, length(UV - vec2(0.5)));
	float arc_alpha = clamp(sample_col.a * alpha_boost, 0.0, 1.0);

	vec3 final_rgb = sample_col.rgb * tint_color.rgb * COLOR.rgb * hdr_intensity;
	float final_alpha = arc_alpha * COLOR.a * tint_color.a * fade_in * edge_fade * quad_mask;

	ALBEDO = final_rgb;
	ALPHA = final_alpha;
}
