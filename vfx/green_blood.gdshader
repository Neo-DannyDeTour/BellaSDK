shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque;

// Green blood flipbook particle shader for unpacked 4x4 animated metaball atlases.
// Samples particle progress from INSTANCE_CUSTOM.z (or INSTANCE_CUSTOM.y lifetime fallback).

uniform sampler2D atlas_texture : source_color, filter_linear_mipmap;
uniform int columns : hint_range(1, 16) = 4;
uniform int rows : hint_range(1, 16) = 4;
uniform vec3 emissive_tint : source_color = vec3(0.2, 1.5, 0.3);
uniform float alpha_discard_threshold : hint_range(0.0, 1.0) = 0.1;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;

	// Spherical particle billboard preserving instance transform scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// Sample particle animation frame from custom properties passed from vertex stage:
	// v_custom.z is driven by ParticleProcessMaterial anim_speed.
	// Fall back to v_custom.y (normalized lifetime) when anim_speed is unconfigured.
	float anim_progress = v_custom.z;
	if (anim_progress <= 0.0001) {
		anim_progress = v_custom.y;
	}

	float total_frames = float(columns * rows);
	float frame_idx = clamp(floor(anim_progress * total_frames), 0.0, total_frames - 1.0);

	float col = mod(frame_idx, float(columns));
	float row = floor(frame_idx / float(columns));

	vec2 uv_scale = vec2(1.0 / float(columns), 1.0 / float(rows));
	vec2 uv_offset = vec2(col * uv_scale.x, row * uv_scale.y);
	vec2 clamped_uv = UV * uv_scale + uv_offset;

	vec4 tex = texture(atlas_texture, clamped_uv);
	ALBEDO = tex.rgb * emissive_tint;
	ALPHA = tex.a;

	if (ALPHA < alpha_discard_threshold) {
		discard;
	}
}
