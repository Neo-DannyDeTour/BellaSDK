shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap, repeat_disable;
uniform float proximity_fade_distance : hint_range(0.01, 2.0) = 0.25;
uniform float softness : hint_range(0.1, 4.0) = 2.0;

instance uniform vec4 leak_color : source_color = vec4(0.4, 0.7, 0.9, 0.6);
instance uniform bool is_billboard = false;

void vertex() {
	if (is_billboard) {
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
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float radial_dist = dot(centered_uv, centered_uv);
	if (radial_dist > 1.0) {
		discard;
	}

	float mask = pow(clamp(1.0 - radial_dist, 0.0, 1.0), softness);

	// Depth proximity fade
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float pixel_depth = upos.z / upos.w;
	float prox_fade = clamp((VERTEX.z - pixel_depth) / proximity_fade_distance, 0.0, 1.0);

	// Core highlight + base water tint
	vec3 core_tint = mix(leak_color.rgb, vec3(0.85, 0.96, 1.0), mask * 0.45);
	ALBEDO = core_tint * COLOR.rgb;
	ALPHA = mask * leak_color.a * COLOR.a * prox_fade;
}
