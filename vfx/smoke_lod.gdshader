shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D circle_mask : hint_default_white, filter_linear;
uniform vec4 smoke_color : source_color = vec4(0.35, 0.35, 0.35, 1.0);
uniform float max_lod : hint_range(0.0, 10.0) = 8.0;

void vertex() {
	mat4 mat_world = mat4(
		normalize(INV_VIEW_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]),
		MODEL_MATRIX[3]
	);
	mat_world = mat_world * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
}

void fragment() {
	float target_lod = COLOR.r * max_lod;
	float noise = textureLod(noise_tex, UV, target_lod).r;
	float mask = texture(circle_mask, UV).r;

	ALBEDO = smoke_color.rgb;
	ALPHA = clamp(noise * mask * COLOR.a * smoke_color.a, 0.0, 1.0);
}
