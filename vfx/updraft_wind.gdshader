shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 cloud_color : source_color = vec4(0.85, 0.95, 1.0, 0.35);
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float swirl_speed : hint_range(0.0, 5.0) = 1.2;
uniform float softness : hint_range(0.05, 0.5) = 0.35;

void vertex() {
	// Extract model scale from the ModelView matrix
	vec3 model_scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);

	// Clear rotation relative to camera view while preserving particle scale
	MODELVIEW_MATRIX[0].xyz = vec3(model_scale.x, 0.0, 0.0);
	MODELVIEW_MATRIX[1].xyz = vec3(0.0, model_scale.y, 0.0);
	MODELVIEW_MATRIX[2].xyz = vec3(0.0, 0.0, model_scale.z);
}

void fragment() {
	// Circular distance mask eliminating rectangular quad borders
	vec2 center_offset = UV - vec2(0.5);
	float dist = length(center_offset) * 2.0;
	float circle_mask = smoothstep(1.0, 1.0 - softness, dist);

	// Multi-frequency noise sampling for swirling air pockets
	vec2 uv_a = UV + vec2(TIME * swirl_speed * 0.1, -TIME * swirl_speed * 0.2);
	vec2 uv_b = UV + vec2(-TIME * swirl_speed * 0.15, -TIME * swirl_speed * 0.1);
	float noise_a = texture(noise_texture, uv_a).r;
	float noise_b = texture(noise_texture, uv_b).g;
	float cloud_noise = smoothstep(0.2, 0.85, noise_a * noise_b * 1.8);

	ALBEDO = cloud_color.rgb;
	ALPHA = circle_mask * cloud_noise * cloud_color.a * COLOR.a;
}
