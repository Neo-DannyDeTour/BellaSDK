shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap;
uniform int h_frames = 8;
uniform int v_frames = 8;
uniform float roughness_val = 0.18;
uniform float specular_val = 0.85;

instance uniform vec4 ichor_tint : source_color = vec4(0.72, 0.78, 0.08, 1.0);
instance uniform float anim_progress : hint_range(0.0, 1.0) = 0.0;
instance uniform float rot_angle = 0.0;

void vertex() {
	float c = cos(rot_angle);
	float s = sin(rot_angle);
	mat4 rot_mat = mat4(
		vec4(c, s, 0.0, 0.0),
		vec4(-s, c, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	mat4 scale_mat = mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	) * rot_mat * scale_mat;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float total_frames = float(max(h_frames * v_frames, 1));
	float frame_float = clamp(anim_progress, 0.0, 1.0) * max(total_frames - 1.0, 0.0);
	float frame_a_idx = floor(frame_float);
	float frame_b_idx = min(frame_a_idx + 1.0, total_frames - 1.0);
	float blend = fract(frame_float);

	vec2 frame_size = vec2(1.0 / float(max(h_frames, 1)), 1.0 / float(max(v_frames, 1)));

	float col_a = mod(frame_a_idx, float(max(h_frames, 1)));
	float row_a = floor(frame_a_idx / float(max(h_frames, 1)));
	vec2 uv_a = (vec2(col_a, row_a) + UV) * frame_size;

	float col_b = mod(frame_b_idx, float(max(h_frames, 1)));
	float row_b = floor(frame_b_idx / float(max(h_frames, 1)));
	vec2 uv_b = (vec2(col_b, row_b) + UV) * frame_size;

	vec4 tex_a = texture(albedo_atlas, uv_a);
	vec4 tex_b = texture(albedo_atlas, uv_b);
	vec4 albedo_sample = mix(tex_a, tex_b, blend);

	vec3 norm_a = texture(normal_atlas, uv_a).rgb;
	vec3 norm_b = texture(normal_atlas, uv_b).rgb;
	vec3 normal_sample = mix(norm_a, norm_b, blend);

	ALBEDO = albedo_sample.rgb * ichor_tint.rgb;
	ALPHA = albedo_sample.a * ichor_tint.a;
	NORMAL_MAP = normal_sample;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;
}
