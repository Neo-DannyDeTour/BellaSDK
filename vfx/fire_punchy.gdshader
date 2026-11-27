shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Per-instance uniforms mutated via set_instance_shader_parameter() without material duplication.
instance uniform float hdr_intensity : hint_range(0.5, 12.0) = 2.4;
instance uniform float flicker_speed : hint_range(0.5, 6.0) = 2.4;
instance uniform vec3 tint_shift : source_color = vec3(1.0, 1.0, 1.0);

uniform sampler2D flame_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform float depth_fade_distance : hint_range(0.05, 2.0) = 0.45;
uniform float warp_strength : hint_range(0.0, 0.3) = 0.032;
uniform float alpha_cutoff : hint_range(0.0, 0.8) = 0.16;
uniform float edge_softness : hint_range(0.01, 0.4) = 0.12;
uniform vec2 atlas_grid = vec2(4.0, 4.0);

varying vec2 v_cell_offset;
varying float v_lifetime_ratio;
varying float v_seed;

void vertex() {
	float total_cells = max(1.0, atlas_grid.x * atlas_grid.y);
	float cell_idx = mod(float(INSTANCE_ID), total_cells);
	v_cell_offset = vec2(mod(cell_idx, atlas_grid.x), floor(cell_idx / atlas_grid.x));
	v_lifetime_ratio = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = float(INSTANCE_ID) * 1.731 + INSTANCE_CUSTOM.x * 0.37;

	vec3 scale_vec = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);

	float angle = INSTANCE_CUSTOM.x;
	float s = sin(angle);
	float c = cos(angle);

	// Camera-facing billboard with Z-axis spin and preserved process scale.
	mat4 mat_world = mat4(
		normalize(INV_VIEW_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]),
		MODEL_MATRIX[3]
	);
	mat_world = mat_world * mat4(
		vec4(c * scale_vec.x, -s * scale_vec.x, 0.0, 0.0),
		vec4(s * scale_vec.y, c * scale_vec.y, 0.0, 0.0),
		vec4(0.0, 0.0, scale_vec.z, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
}

void fragment() {
	vec2 local_uv = clamp(UV, vec2(0.0), vec2(1.0));
	float height_up = clamp(1.0 - local_uv.y, 0.0, 1.0);
	float tip_factor = smoothstep(0.05, 0.88, height_up);

	// Subtle upward-scrolling curl shimmer over photographic Mantaflow flames.
	vec2 n_uv1 = vec2(
		local_uv.x * 1.2 + v_seed * 0.13,
		local_uv.y * 0.9 + TIME * flicker_speed * 0.72 + v_seed * 0.17
	);
	vec2 n_uv2 = vec2(
		local_uv.x * 2.4 - v_seed * 0.21,
		local_uv.y * 1.8 + TIME * flicker_speed * 1.28
	);
	float n1 = texture(noise_tex, n_uv1).r - 0.5;
	float n2 = texture(noise_tex, n_uv2).r - 0.5;
	float noise_warp = n1 * 0.65 + n2 * 0.35;

	vec2 warped_local = local_uv + vec2(n1 * 0.85, noise_warp * 1.25) * (
		warp_strength * (0.20 + 0.95 * tip_factor)
	);
	warped_local = clamp(warped_local, vec2(0.01), vec2(0.99));

	vec2 atlas_uv = (v_cell_offset + warped_local) / atlas_grid;
	vec4 tex = texture(flame_atlas, atlas_uv);

	float life_fade = smoothstep(0.0, 0.18, v_lifetime_ratio)
			* (1.0 - smoothstep(0.52, 1.0, v_lifetime_ratio));
	float flicker = 0.82 + 0.36 * clamp(n1 + 0.5, 0.0, 1.0);

	// Soft depth proximity fade against scene geometry.
	float depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	float depth_fade = 1.0;
	if (depth_raw > 0.00001) {
		vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
		view_pos.xyz /= view_pos.w;
		float depth_diff = abs(VERTEX.z - view_pos.z);
		depth_fade = clamp(depth_diff / max(depth_fade_distance, 0.01), 0.0, 1.0);
	}

	// Keep alpha_cutoff uniform referenced smoothly for subtle outer whisper fade in additive mode.
	float wisp_soft = smoothstep(0.0, max(0.04, alpha_cutoff * 0.25 + edge_softness * 0.25), tex.a);
	vec3 additive_rgb = tex.rgb * hdr_intensity * tint_shift * COLOR.rgb
			* life_fade * depth_fade * flicker * wisp_soft * COLOR.a;
	if (dot(additive_rgb, vec3(1.0)) <= 0.002) {
		discard;
	}

	ALBEDO = additive_rgb;
	ALPHA = 1.0;
}
